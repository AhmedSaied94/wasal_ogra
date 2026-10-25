"""The monthly restore drill (FR-040, data-model "Restore drill result" and "Invariant check").

`fetch` reads from a fake B2 (moto, at the boto3 boundary). `check` restores a real dump, made by
the backup service from the test database, into a fresh database that each test creates and drops.
"""

from __future__ import annotations

import dataclasses
import json
import re
import uuid
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import datetime
from io import StringIO
from pathlib import Path
from typing import Any
from unittest import mock

import psycopg
import pytest
from django.core.management import CommandError, call_command
from django.db import connection

from apps.accounts.models import User
from apps.common.services import backups, invariants, restore_drill
from apps.common.services.restore_drill import DrillError, FetchConfig
from apps.common.tests.b2 import (
    DAILY,
    ENDPOINT,
    MONDAY,
    REGION,
    RELEASE,
    SUNDAY,
    TUESDAY,
    WEEKLY,
    backup_config,
    fake_b2,
    read,
)

pytestmark = pytest.mark.django_db(transaction=True)

RESULT_FIELDS = {
    "started_at",
    "finished_at",
    "backup_key",
    "backup_created_at",
    "release",
    "checks",
    "restore_duration_s",
    "total_duration_s",
    "outcome",
    "failure",
}
UTC_STAMP = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ")
FETCH = FetchConfig(
    s3_endpoint=ENDPOINT,
    s3_region=REGION,
    daily_bucket=DAILY,
    weekly_bucket=WEEKLY,
    key_id="test",
    app_key="test",
    prefix="prod",
)

Backup = Callable[..., dict[str, Any]]


@pytest.fixture
def s3() -> Iterator[Any]:
    with fake_b2() as client, mock.patch("apps.common.services.backups.monitoring.ping"):
        yield client


@pytest.fixture
def backup(s3: Any, tmp_path: Path) -> Backup:
    """Take a real backup of the test database at `when`, with `daily` as its daily bucket."""

    def take(when: datetime = MONDAY, *, daily: str = DAILY) -> dict[str, Any]:
        config = dataclasses.replace(backup_config(tmp_path), daily_bucket=daily)
        database = backups.Database.from_settings(connection.settings_dict)
        return backups.run_backup(config, database, now=when)

    return take


@pytest.fixture
def drill_dir(tmp_path: Path) -> Path:
    path = tmp_path / "drill"
    path.mkdir()
    return path


@pytest.fixture
def drill_db() -> Iterator[dict[str, Any]]:
    """A fresh, empty database, like the drill's throwaway PostgreSQL container."""
    name = f"drill_{uuid.uuid4().hex[:12]}"
    with connection.cursor() as cursor:
        cursor.execute(f"CREATE DATABASE {name}")
    try:
        yield {**connection.settings_dict, "NAME": name}
    finally:
        with connection.cursor() as cursor:
            cursor.execute(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def fetch_backup(backup: Backup, drill_dir: Path) -> dict[str, Any]:
    User.objects.create_user("alice", "a-long-enough-password-1")
    backup()
    return restore_drill.fetch(FETCH, drill_dir)


def run_check(drill_dir: Path, drill_db: dict[str, Any], tolerance: int = 0) -> dict[str, Any]:
    return restore_drill.check(drill_dir, drill_db, tolerance=tolerance, release=RELEASE)


def edit_metadata(drill_dir: Path, change: Callable[[dict[str, Any]], object]) -> None:
    path = drill_dir / restore_drill.META_FILE
    meta = json.loads(path.read_text())
    change(meta)
    path.write_text(json.dumps(meta))


@contextmanager
def migration_rows(
    *, add: tuple[str, str] | None = None, drop_latest: str | None = None
) -> Iterator[None]:
    """Change `django_migrations` in the source database for one backup, then put it back."""
    removed: tuple[Any, ...] | None = None
    with connection.cursor() as cursor:
        if add:
            cursor.execute(
                "INSERT INTO django_migrations (app, name, applied) VALUES (%s, %s, now())", add
            )
        if drop_latest:
            cursor.execute(
                "DELETE FROM django_migrations WHERE id = "
                "(SELECT max(id) FROM django_migrations WHERE app = %s) "
                "RETURNING id, app, name, applied",
                [drop_latest],
            )
            removed = cursor.fetchone()
    try:
        yield
    finally:
        with connection.cursor() as cursor:
            if add:
                cursor.execute("DELETE FROM django_migrations WHERE app = %s AND name = %s", add)
            if removed:
                cursor.execute(
                    "INSERT INTO django_migrations (id, app, name, applied) "
                    "VALUES (%s, %s, %s, %s)",
                    removed,
                )


# -- fetch -----------------------------------------------------------------------------------------


def test_fetch_downloads_the_newest_complete_backup(
    s3: Any, backup: Backup, drill_dir: Path
) -> None:
    meta = backup(MONDAY)
    # A newer dump whose metadata never arrived is incomplete, so the drill skips it.
    s3.put_object(Bucket=DAILY, Key="prod/2026/10/20/prod-20261020T010000Z.dump", Body=b"partial")

    fetched = restore_drill.fetch(FETCH, drill_dir)

    assert fetched == meta
    dump = (drill_dir / restore_drill.DUMP_FILE).read_bytes()
    assert dump == read(s3, DAILY, meta["dump"]["key"])
    assert json.loads((drill_dir / restore_drill.META_FILE).read_text()) == meta


def test_fetch_looks_in_both_buckets(backup: Backup, drill_dir: Path) -> None:
    backup(SUNDAY)
    newest = backup(TUESDAY, daily=WEEKLY)

    fetched = restore_drill.fetch(FETCH, drill_dir)

    assert fetched["dump"]["key"] == newest["dump"]["key"]


def test_fetch_refuses_a_dump_whose_checksum_differs(
    s3: Any, backup: Backup, drill_dir: Path
) -> None:
    meta = backup(MONDAY)
    dump = bytearray(read(s3, DAILY, meta["dump"]["key"]))
    dump[-1] ^= 0xFF
    # A compromised write key can shadow a backup with a newer version under the same name.
    s3.put_object(Bucket=DAILY, Key=meta["dump"]["key"], Body=bytes(dump))

    with pytest.raises(DrillError, match="sha256 mismatch"):
        restore_drill.fetch(FETCH, drill_dir)


def test_fetch_refuses_metadata_that_names_another_dump(
    s3: Any, backup: Backup, drill_dir: Path
) -> None:
    meta = backup(MONDAY)
    key = meta["dump"]["key"].removesuffix(".dump") + ".json"
    s3.put_object(
        Bucket=DAILY,
        Key=key,
        Body=json.dumps({**meta, "dump": {**meta["dump"], "key": "prod/elsewhere.dump"}}),
    )

    with pytest.raises(DrillError, match="metadata"):
        restore_drill.fetch(FETCH, drill_dir)


def test_fetch_fails_when_no_backup_is_complete(s3: Any, drill_dir: Path) -> None:
    s3.put_object(Bucket=DAILY, Key="prod/2026/10/20/prod-20261020T010000Z.dump", Body=b"partial")

    with pytest.raises(DrillError, match="no complete backup"):
        restore_drill.fetch(FETCH, drill_dir)


# -- check -----------------------------------------------------------------------------------------


def test_a_good_backup_passes_every_check(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    meta = fetch_backup(backup, drill_dir)

    result = run_check(drill_dir, drill_db)

    assert set(result) == RESULT_FIELDS
    assert result["checks"] == {
        "restore": "pass",
        "migrations": "pass",
        "row_counts": "pass",
        "invariants": {
            "content.published_packs_intact": "pass",
            "economy.wallet_equals_ledger": "pass",
        },
    }
    assert result["outcome"] == "pass"
    assert result["failure"] is None
    assert result["backup_key"] == meta["dump"]["key"]
    assert result["backup_created_at"] == meta["created_at"]
    assert result["release"] == RELEASE
    assert UTC_STAMP.fullmatch(result["started_at"])
    assert UTC_STAMP.fullmatch(result["finished_at"])
    assert isinstance(result["restore_duration_s"], float)
    assert result["total_duration_s"] >= result["restore_duration_s"]


def test_invariants_run_against_the_restored_database(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    fetch_backup(backup, drill_dir)
    seen: list[Any] = []

    def users_restored(conn: Any) -> tuple[bool, str]:
        seen.append(conn.execute("SELECT username FROM accounts_user").fetchall())
        return True, "ok"

    invariants.register("test.users_restored")(users_restored)
    invariants.register("test.always_fails")(lambda conn: (False, "broken on purpose"))
    try:
        result = run_check(drill_dir, drill_db)
    finally:
        invariants.unregister("test.users_restored")
        invariants.unregister("test.always_fails")

    assert seen == [[("alice",)]]
    assert result["checks"]["invariants"] == {
        "content.published_packs_intact": "pass",
        "economy.wallet_equals_ledger": "pass",
        "test.users_restored": "pass",
        "test.always_fails": "fail",
    }
    assert result["outcome"] == "fail"
    assert "test.always_fails" in result["failure"]


def test_a_count_off_by_one_fails_at_tolerance_zero(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    fetch_backup(backup, drill_dir)
    edit_metadata(drill_dir, lambda meta: meta["tables"].update({"public.accounts_user": 2}))

    result = run_check(drill_dir, drill_db)

    assert result["checks"]["row_counts"] == "fail"
    assert result["checks"]["restore"] == "pass"
    assert result["outcome"] == "fail"
    assert "public.accounts_user" in result["failure"]


def test_the_tolerance_allows_a_small_difference(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    fetch_backup(backup, drill_dir)
    edit_metadata(drill_dir, lambda meta: meta["tables"].update({"public.accounts_user": 2}))

    result = run_check(drill_dir, drill_db, tolerance=1)

    assert result["checks"]["row_counts"] == "pass"


def test_a_table_missing_from_the_restore_fails(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    fetch_backup(backup, drill_dir)
    edit_metadata(drill_dir, lambda meta: meta["tables"].update({"public.ghost": 0}))

    result = run_check(drill_dir, drill_db)

    assert result["checks"]["row_counts"] == "fail"
    assert "missing public.ghost" in result["failure"]


def test_an_extra_table_in_the_restore_fails(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    fetch_backup(backup, drill_dir)
    edit_metadata(drill_dir, lambda meta: meta["tables"].pop("public.accounts_user"))

    result = run_check(drill_dir, drill_db)

    assert result["checks"]["row_counts"] == "fail"
    assert "extra public.accounts_user" in result["failure"]


def test_an_applied_migration_the_code_lacks_fails(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    with migration_rows(add=("accounts", "9999_from_the_future")):
        fetch_backup(backup, drill_dir)

    result = run_check(drill_dir, drill_db)

    assert result["checks"]["migrations"] == "fail"
    assert result["outcome"] == "fail"
    assert "accounts.9999_from_the_future" in result["failure"]


def test_a_pending_migration_fails(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    with migration_rows(drop_latest="accounts"):
        fetch_backup(backup, drill_dir)

    result = run_check(drill_dir, drill_db)

    assert result["checks"]["migrations"] == "fail"
    assert "pending" in result["failure"]


def test_a_failed_restore_fails_every_check(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    fetch_backup(backup, drill_dir)
    (drill_dir / restore_drill.DUMP_FILE).write_bytes(b"PGDMP not really a dump")

    result = run_check(drill_dir, drill_db)

    assert set(result) == RESULT_FIELDS
    assert result["checks"] == {
        "restore": "fail",
        "migrations": "fail",
        "row_counts": "fail",
        "invariants": {},
    }
    assert result["outcome"] == "fail"
    assert result["failure"].startswith("restore failed (exit ")


def test_failures_carry_no_secrets(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    fetch_backup(backup, drill_dir)
    (drill_dir / restore_drill.DUMP_FILE).write_bytes(b"garbage")
    bad_password = {**drill_db, "PASSWORD": "s3cret-drill-password"}

    result = run_check(drill_dir, bad_password)

    line = json.dumps(result)
    assert result["outcome"] == "fail"
    assert "s3cret-drill-password" not in line
    assert "postgres://" not in line
    assert "postgresql://" not in line
    assert len(result["failure"]) <= 300


def test_a_database_that_isnt_empty_is_never_restored_into(
    backup: Backup, drill_dir: Path, drill_db: dict[str, Any]
) -> None:
    fetch_backup(backup, drill_dir)
    database = backups.Database.from_settings(drill_db)
    with psycopg.connect(**database.connect_kwargs(), autocommit=True) as conn:
        conn.execute("CREATE TABLE precious (id int)")

    result = run_check(drill_dir, drill_db)

    assert result["checks"]["restore"] == "fail"
    assert result["failure"] == "restore refused: the target database isn't empty"


def test_fetch_clears_files_left_by_an_earlier_run(s3: Any, drill_dir: Path) -> None:
    for name in (restore_drill.DUMP_FILE, restore_drill.META_FILE):
        (drill_dir / name).write_text("stale")

    with pytest.raises(DrillError, match="no complete backup"):
        restore_drill.fetch(FETCH, drill_dir)

    assert list(drill_dir.iterdir()) == []


def test_check_needs_the_fetched_metadata(drill_dir: Path, drill_db: dict[str, Any]) -> None:
    with pytest.raises(DrillError, match="metadata"):
        run_check(drill_dir, drill_db)


# -- the management command ------------------------------------------------------------------------

DRILL_ENV = {
    "B2_S3_ENDPOINT": ENDPOINT,
    "B2_REGION": REGION,
    "B2_DAILY_BUCKET": DAILY,
    "B2_WEEKLY_BUCKET": WEEKLY,
    "BACKUP_PREFIX": "prod",
    "B2_DRILL_KEY_ID": "drill-key-id",
    "B2_DRILL_APP_KEY": "drill-app-key",
}


def test_the_fetch_command_reads_the_drill_key(
    monkeypatch: pytest.MonkeyPatch, drill_dir: Path
) -> None:
    for name, value in DRILL_ENV.items():
        monkeypatch.setenv(name, value)
    with mock.patch.object(restore_drill, "fetch", return_value={"dump": {"key": "k"}}) as fetch:
        call_command("restore_drill", "fetch", str(drill_dir), stdout=StringIO())

    config, directory = fetch.call_args.args
    assert directory == drill_dir
    assert config == dataclasses.replace(FETCH, key_id="drill-key-id", app_key="drill-app-key")


def test_the_fetch_command_needs_the_drill_key(
    monkeypatch: pytest.MonkeyPatch, drill_dir: Path
) -> None:
    for name, value in DRILL_ENV.items():
        monkeypatch.setenv(name, value)
    monkeypatch.setenv("B2_DRILL_APP_KEY", "")

    with pytest.raises(CommandError, match="B2_DRILL_APP_KEY is required"):
        call_command("restore_drill", "fetch", str(drill_dir))


def test_a_failed_fetch_is_a_short_command_error(
    monkeypatch: pytest.MonkeyPatch, drill_dir: Path
) -> None:
    for name, value in DRILL_ENV.items():
        monkeypatch.setenv(name, value)
    with (
        mock.patch.object(restore_drill, "fetch", side_effect=DrillError("sha256 mismatch")),
        pytest.raises(CommandError, match=r"^sha256 mismatch$"),
    ):
        call_command("restore_drill", "fetch", str(drill_dir))


def result_line(outcome: str) -> dict[str, Any]:
    return {field: None for field in RESULT_FIELDS} | {"outcome": outcome}


def test_the_check_command_prints_one_json_line(
    monkeypatch: pytest.MonkeyPatch, drill_dir: Path
) -> None:
    monkeypatch.setenv("DRILL_ROWCOUNT_TOLERANCE", "2")
    for name in DRILL_ENV:
        monkeypatch.delenv(name, raising=False)
    out = StringIO()
    with mock.patch.object(restore_drill, "check", return_value=result_line("pass")) as check:
        call_command("restore_drill", "check", str(drill_dir), stdout=out)

    assert check.call_args.args[0] == drill_dir
    assert check.call_args.kwargs["tolerance"] == 2
    lines = out.getvalue().splitlines()
    assert len(lines) == 1
    assert json.loads(lines[0]) == result_line("pass")


def test_a_failed_check_still_prints_its_line(drill_dir: Path) -> None:
    out = StringIO()
    with (
        mock.patch.object(restore_drill, "check", return_value=result_line("fail")),
        pytest.raises(CommandError),
    ):
        call_command("restore_drill", "check", str(drill_dir), stdout=out)

    assert json.loads(out.getvalue())["outcome"] == "fail"


def test_a_bad_tolerance_is_refused(monkeypatch: pytest.MonkeyPatch, drill_dir: Path) -> None:
    monkeypatch.setenv("DRILL_ROWCOUNT_TOLERANCE", "-1")

    with pytest.raises(CommandError, match="DRILL_ROWCOUNT_TOLERANCE is invalid"):
        call_command("restore_drill", "check", str(drill_dir))
