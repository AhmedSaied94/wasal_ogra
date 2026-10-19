"""The nightly backup (FR-039, FR-039a, contracts/operations.md "Backup job", research R9).

Real PostgreSQL. B2 is replaced only at the boto3 boundary, by moto's in-process S3.
"""

from __future__ import annotations

import base64
import hashlib
import json
import subprocess
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from unittest import mock

import psycopg
import pytest
from django.core.management import CommandError, call_command
from django.db import connection

from apps.accounts.models import User
from apps.common.services import backups
from apps.common.services.backups import BackupConfig, BackupError, Database
from apps.common.tests.b2 import (
    DAILY,
    ENDPOINT,
    MONDAY,
    PING,
    REGION,
    SUNDAY,
    WEEKLY,
    backup_config,
    fake_b2,
    keys,
    read,
)

pytestmark = pytest.mark.django_db(transaction=True)


@pytest.fixture
def s3() -> Iterator[Any]:
    with fake_b2() as client:
        yield client


@pytest.fixture
def config(tmp_path: Path) -> BackupConfig:
    return backup_config(tmp_path)


@pytest.fixture
def database() -> Database:
    return Database.from_settings(connection.settings_dict)


@pytest.fixture
def pings() -> Iterator[mock.MagicMock]:
    with mock.patch("apps.common.services.backups.monitoring.ping") as ping:
        yield ping


def download(s3: Any, bucket: str, key: str, path: Path) -> Path:
    path.write_bytes(read(s3, bucket, key))
    return path


def test_a_run_uploads_the_dump_then_its_metadata(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    with mock.patch.object(backups, "upload", wraps=backups.upload) as upload:
        backups.run_backup(config, database, now=MONDAY)

    base = "prod/2026/10/19/prod-20261019T010000Z"
    assert keys(s3, DAILY) == [f"{base}.dump", f"{base}.json"]
    assert [call.args[2] for call in upload.call_args_list] == [f"{base}.dump", f"{base}.json"]
    assert keys(s3, WEEKLY) == []


def test_the_weekly_day_also_writes_the_weekly_bucket(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    backups.run_backup(config, database, now=SUNDAY)

    base = "prod/2026/10/18/prod-20261018T010000Z"
    assert keys(s3, DAILY) == [f"{base}.dump", f"{base}.json"]
    assert keys(s3, WEEKLY) == [f"{base}.dump", f"{base}.json"]
    assert json.loads(read(s3, DAILY, f"{base}.json"))["retention_class"] == "daily"
    assert json.loads(read(s3, WEEKLY, f"{base}.json"))["retention_class"] == "weekly"


def test_the_metadata_describes_the_uploaded_dump(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    User.objects.create_user("alice", "a-long-enough-password-1")

    backups.run_backup(config, database, now=MONDAY)

    base = "prod/2026/10/19/prod-20261019T010000Z"
    meta = json.loads(read(s3, DAILY, f"{base}.json"))
    dump = read(s3, DAILY, f"{base}.dump")
    assert meta["schema_version"] == 1
    assert meta["environment"] == "prod"
    assert meta["created_at"] == "2026-10-19T01:00:00Z"
    assert meta["release"] == "a" * 40
    assert meta["postgres_version"].split(".")[0].isdigit()
    assert meta["retention_class"] == "daily"
    assert meta["dump"] == {
        "key": f"{base}.dump",
        "size_bytes": len(dump),
        "sha256": hashlib.sha256(dump).hexdigest(),
        "format": "custom",
    }
    assert meta["tables"]["public.accounts_user"] == 1
    assert "public.django_migrations" in meta["tables"]
    assert isinstance(meta["duration_s"], float)


def test_counts_and_dump_come_from_one_snapshot(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock, tmp_path: Path
) -> None:
    User.objects.create_user("alice", "a-long-enough-password-1")
    real_dump = backups.run_pg_dump

    def dump_after_a_concurrent_write(db: Database, snapshot: str, path: Path) -> None:
        # Another connection writes after the snapshot is exported, before pg_dump runs.
        User.objects.create_user("bob", "a-long-enough-password-1")
        real_dump(db, snapshot, path)

    with mock.patch.object(backups, "run_pg_dump", dump_after_a_concurrent_write):
        meta = backups.run_backup(config, database, now=MONDAY)

    assert User.objects.count() == 2
    assert meta["tables"]["public.accounts_user"] == 1
    dump = download(s3, DAILY, meta["dump"]["key"], tmp_path / "x.dump")
    data = subprocess.run(  # noqa: S603 - fixed arguments
        ["pg_restore", "--data-only", "--file=-", str(dump)],  # noqa: S607
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert "alice" in data
    assert "bob" not in data


def test_the_dump_passes_pg_restore_list(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock, tmp_path: Path
) -> None:
    meta = backups.run_backup(config, database, now=MONDAY)

    dump = download(s3, DAILY, meta["dump"]["key"], tmp_path / "x.dump")
    result = subprocess.run(  # noqa: S603 - fixed arguments
        ["pg_restore", "--list", str(dump)],  # noqa: S607
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "accounts_user" in result.stdout


def test_a_failed_dump_upload_leaves_no_metadata(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    def failing(client: Any, bucket: str, key: str, body: Path | bytes) -> None:
        raise ConnectionError("reset by peer, key=K0042secret")

    with mock.patch.object(backups, "upload", failing), pytest.raises(BackupError):
        backups.run_backup(config, database, now=MONDAY)

    assert keys(s3, DAILY) == []
    assert not config.state_file.exists()
    pings.assert_called_once()
    assert pings.call_args.kwargs["kind"] == "fail"
    # The reason names the step and the error type, never the error's own text.
    assert pings.call_args.kwargs["body"] == "upload failed: ConnectionError"


def test_a_failure_outside_any_step_still_pings_fail(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    with (
        mock.patch(
            "apps.common.services.backups.tempfile.TemporaryDirectory", side_effect=OSError("disk")
        ),
        pytest.raises(BackupError, match="backup failed: OSError"),
    ):
        backups.run_backup(config, database, now=MONDAY)

    assert pings.call_args.kwargs == {"kind": "fail", "body": "backup failed: OSError"}


def test_uploads_carry_their_md5_so_storage_refuses_damage(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    sent: list[dict[str, Any]] = []
    real_client = backups.s3_client

    def spying_client(cfg: BackupConfig) -> Any:
        client = real_client(cfg)
        put = client.put_object

        def recording_put(**kwargs: Any) -> Any:
            sent.append(kwargs)
            return put(**kwargs)

        client.put_object = recording_put
        return client

    with mock.patch.object(backups, "s3_client", spying_client):
        backups.run_backup(config, database, now=MONDAY)

    assert [call["Key"].rsplit(".", 1)[1] for call in sent] == ["dump", "json"]
    for call in sent:
        stored = read(s3, call["Bucket"], call["Key"])
        md5 = hashlib.md5(stored, usedforsecurity=False).digest()
        assert call["ContentMD5"] == base64.b64encode(md5).decode()


def test_a_failed_metadata_upload_pings_fail(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    real_upload = backups.upload

    def failing_json(client: Any, bucket: str, key: str, body: Path | bytes) -> None:
        if key.endswith(".json"):
            raise ConnectionError("reset by peer")
        real_upload(client, bucket, key, body)

    with mock.patch.object(backups, "upload", failing_json), pytest.raises(BackupError):
        backups.run_backup(config, database, now=MONDAY)

    assert [key for key in keys(s3, DAILY) if key.endswith(".json")] == []
    assert pings.call_args.kwargs["kind"] == "fail"


def test_success_pings_with_size_and_duration(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    meta = backups.run_backup(config, database, now=MONDAY)

    pings.assert_called_once()
    assert pings.call_args.args == (PING,)
    assert pings.call_args.kwargs.get("kind", "success") == "success"
    body = pings.call_args.kwargs["body"]
    assert f"size_bytes={meta['dump']['size_bytes']}" in body
    assert "duration_s=" in body


def test_the_latest_metadata_is_kept_on_the_host(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    meta = backups.run_backup(config, database, now=MONDAY)

    assert json.loads(config.state_file.read_text()) == meta


def test_counts_quote_identifiers(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    odd = 'odd "table"; drop'
    # Django's quote_name doesn't double embedded quotes, so quote by hand for the fixture.
    table = 'public."' + odd.replace('"', '""') + '"'
    with connection.cursor() as cursor:
        cursor.execute(f"CREATE TABLE {table} (id int)")
        cursor.execute(f"INSERT INTO {table} VALUES (1), (2)")  # noqa: S608 - fixed name
    try:
        meta = backups.run_backup(config, database, now=MONDAY)
    finally:
        with connection.cursor() as cursor:
            cursor.execute(f"DROP TABLE {table}")

    assert meta["tables"][f"public.{odd}"] == 2


def test_pg_dump_gets_the_password_from_its_environment(
    s3: Any, config: BackupConfig, database: Database, pings: mock.MagicMock
) -> None:
    real_run = subprocess.run
    seen: list[tuple[list[str], dict[str, str]]] = []

    def spy(argv: list[str], **kwargs: Any) -> Any:
        seen.append((argv, kwargs.get("env") or {}))
        return real_run(argv, **kwargs)

    with mock.patch("apps.common.services.backups.subprocess.run", spy):
        backups.run_backup(config, database, now=MONDAY)

    dumps = [(argv, env) for argv, env in seen if Path(argv[0]).name == "pg_dump"]
    assert dumps
    for argv, env in dumps:
        assert database.password not in " ".join(argv)
        assert env["PGPASSWORD"] == database.password
        assert "--format=custom" in argv
        assert any(arg.startswith("--snapshot=") for arg in argv)
    lists = [(argv, env) for argv, env in seen if Path(argv[0]).name == "pg_restore"]
    assert lists
    for argv, env in lists:
        assert database.password not in " ".join(argv)
        assert "PGPASSWORD" not in env


def test_tls_options_from_the_database_url_reach_libpq() -> None:
    database = Database.from_settings(
        {
            "NAME": "wassal",
            "USER": "wassal",
            "PASSWORD": "pw",
            "HOST": "db.internal",
            "PORT": "5432",
            "OPTIONS": {"sslmode": "verify-full", "sslrootcert": "/ca.pem", "connect_timeout": "3"},
        }
    )

    kwargs = database.connect_kwargs()
    assert kwargs["sslmode"] == "verify-full"
    assert kwargs["sslrootcert"] == "/ca.pem"
    env = database.libpq_env()
    assert env["PGSSLMODE"] == "verify-full"
    assert env["PGSSLROOTCERT"] == "/ca.pem"
    assert env["PGHOST"] == "db.internal"


def test_an_empty_host_keeps_libpqs_default_socket() -> None:
    database = Database.from_settings(
        {"NAME": "wassal", "USER": "wassal", "PASSWORD": "pw", "HOST": "", "PORT": ""}
    )

    assert "host" not in database.connect_kwargs()
    assert "port" not in database.connect_kwargs()
    assert "PGHOST" not in database.libpq_env()


def test_the_s3_client_is_configured_for_b2(config: BackupConfig) -> None:
    with mock.patch("apps.common.services.backups.boto3.client") as client:
        backups.s3_client(config)

    kwargs = client.call_args.kwargs
    assert client.call_args.args == ("s3",)
    assert kwargs["endpoint_url"] == ENDPOINT
    assert kwargs["region_name"] == REGION
    assert kwargs["aws_access_key_id"] == "test"
    options = kwargs["config"]
    assert options.signature_version == "s3v4"
    assert options.request_checksum_calculation == "when_required"
    assert options.response_checksum_validation == "when_required"


def test_the_database_parameters_come_from_settings(database: Database) -> None:
    with psycopg.connect(**database.connect_kwargs()) as conn:
        assert conn.execute("SELECT current_database()").fetchone() == (database.name,)


# -- the management command ------------------------------------------------------------------------

BACKUP_ENV = {
    "B2_S3_ENDPOINT": ENDPOINT,
    "B2_REGION": REGION,
    "B2_DAILY_BUCKET": DAILY,
    "B2_WEEKLY_BUCKET": WEEKLY,
    "B2_BACKUP_KEY_ID": "test",
    "B2_BACKUP_APP_KEY": "test",
    "BACKUP_PREFIX": "prod",
    "BACKUP_WEEKLY_WEEKDAY": "6",
    "HC_PING_BACKUP_URL": PING,
}


def test_the_command_reads_its_configuration(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    for name, value in BACKUP_ENV.items():
        monkeypatch.setenv(name, value)
    monkeypatch.setenv("BACKUP_STATE_FILE", str(tmp_path / "last.json"))
    with mock.patch.object(backups, "run_backup", return_value={"dump": {}}) as run:
        call_command("backup_db")

    config = run.call_args.args[0]
    assert config.daily_bucket == DAILY
    assert config.weekly_weekday == 6
    assert config.state_file == tmp_path / "last.json"


@pytest.mark.parametrize(
    ("name", "value", "message"),
    [
        ("B2_REGION", "", "B2_REGION is required"),
        ("B2_S3_ENDPOINT", "http://s3.example.test", "B2_S3_ENDPOINT is invalid"),
        ("BACKUP_PREFIX", "../prod", "BACKUP_PREFIX is invalid"),
        ("BACKUP_WEEKLY_WEEKDAY", "7", "BACKUP_WEEKLY_WEEKDAY is invalid"),
    ],
)
def test_bad_configuration_is_refused_and_reported(
    monkeypatch: pytest.MonkeyPatch, pings: mock.MagicMock, name: str, value: str, message: str
) -> None:
    for key, default in BACKUP_ENV.items():
        monkeypatch.setenv(key, default)
    monkeypatch.setenv(name, value)

    with pytest.raises(CommandError, match=message):
        call_command("backup_db")

    assert pings.call_args.kwargs["kind"] == "fail"
    assert message in pings.call_args.kwargs["body"]
