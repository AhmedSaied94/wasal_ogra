"""The nightly backup (FR-039, FR-039a, contracts/operations.md "Backup job", research R9).

One run, inside a single exported snapshot:

1. a `REPEATABLE READ, READ ONLY` transaction exports its snapshot;
2. every app table is counted in that snapshot;
3. `pg_dump --snapshot` dumps the same snapshot, so the counts match the dump exactly;
4. `pg_restore --list` checks the file, then its sha256 is taken;
5. the dump, then its metadata (the completion marker), go to the daily bucket, and on the weekly
   day to the weekly bucket too;
6. the metadata is kept on the host for the storage check;
7. Healthchecks.io is pinged, or `/fail` with a short reason.

The reasons and logs name the failing step and the error type only, never a key, URL or password.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import os
import shutil
import subprocess
import tempfile
import time
from collections.abc import Iterator, Mapping
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import boto3
import psycopg
import requests
from botocore.config import Config
from psycopg import sql

from apps.common.services import monitoring

logger = logging.getLogger(__name__)

SCHEMA_VERSION = 1
CONNECT_TIMEOUT_S = 10
DUMP_TIMEOUT_S = 30 * 60
LIST_TIMEOUT_S = 5 * 60
CHUNK = 1024 * 1024
# Connection options from DATABASE_URL that libpq tools must keep (env.database() puts them in
# OPTIONS), with the environment variable each tool reads.
LIBPQ_OPTIONS = {
    "sslmode": "PGSSLMODE",
    "sslrootcert": "PGSSLROOTCERT",
    "sslcert": "PGSSLCERT",
    "sslkey": "PGSSLKEY",
    "sslcrl": "PGSSLCRL",
}

APP_TABLES = """
    SELECT n.nspname, c.relname
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 'p')
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname NOT LIKE 'pg\\_toast%'
      AND n.nspname NOT LIKE 'pg\\_temp\\_%'
    ORDER BY n.nspname, c.relname
"""


class BackupError(Exception):
    """A step failed. The message is the short reason sent with the `/fail` ping."""


@dataclass(frozen=True)
class BackupConfig:
    environment: str
    release: str
    s3_endpoint: str
    s3_region: str
    daily_bucket: str
    weekly_bucket: str
    key_id: str
    app_key: str = field(repr=False)
    prefix: str
    weekly_weekday: int
    ping_url: str = field(repr=False)
    state_file: Path


@dataclass(frozen=True)
class Database:
    """libpq parameters for one database, from a Django `settings_dict`."""

    name: str
    user: str
    password: str = field(repr=False)
    # Empty means libpq's default, as in Django: the local socket and port 5432.
    host: str = ""
    port: str = ""
    # The TLS options of LIBPQ_OPTIONS, as (name, value) pairs.
    options: tuple[tuple[str, str], ...] = ()

    @classmethod
    def from_settings(cls, settings_dict: Mapping[str, Any]) -> Database:
        given = settings_dict.get("OPTIONS") or {}
        return cls(
            name=str(settings_dict["NAME"]),
            user=str(settings_dict["USER"]),
            password=str(settings_dict["PASSWORD"]),
            host=str(settings_dict.get("HOST") or ""),
            port=str(settings_dict.get("PORT") or ""),
            options=tuple((k, str(given[k])) for k in LIBPQ_OPTIONS if given.get(k)),
        )

    def connect_kwargs(self) -> dict[str, Any]:
        kwargs: dict[str, Any] = {
            "dbname": self.name,
            "user": self.user,
            "password": self.password,
            "connect_timeout": CONNECT_TIMEOUT_S,
            **dict(self.options),
        }
        if self.host:
            kwargs["host"] = self.host
        if self.port:
            kwargs["port"] = self.port
        return kwargs

    def libpq_env(self) -> dict[str, str]:
        """The environment for `pg_dump` and `pg_restore`: the password never goes in argv."""
        env = {
            "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
            "PGUSER": self.user,
            "PGPASSWORD": self.password,
            "PGDATABASE": self.name,
            "PGCONNECT_TIMEOUT": str(CONNECT_TIMEOUT_S),
            **{LIBPQ_OPTIONS[name]: value for name, value in self.options},
        }
        if self.host:
            env["PGHOST"] = self.host
        if self.port:
            env["PGPORT"] = self.port
        return env


def b2_client(endpoint: str, region: str, key_id: str, app_key: str) -> Any:
    """A B2 S3 client. B2 rejects the checksum headers newer boto3 sends by default (R9)."""
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        region_name=region,
        aws_access_key_id=key_id,
        aws_secret_access_key=app_key,
        config=Config(
            signature_version="s3v4",
            request_checksum_calculation="when_required",
            response_checksum_validation="when_required",
            retries={"mode": "standard", "max_attempts": 5},
            connect_timeout=10,
            read_timeout=120,
        ),
    )


def s3_client(config: BackupConfig) -> Any:
    return b2_client(config.s3_endpoint, config.s3_region, config.key_id, config.app_key)


def upload(client: Any, bucket: str, key: str, body: Path | bytes) -> None:
    """One PutObject with `Content-MD5`, so storage refuses an upload that arrived damaged.

    The backup key can't read, so this is how the job knows what was stored is what it sent.
    """
    if isinstance(body, Path):
        with body.open("rb") as handle:
            client.put_object(Bucket=bucket, Key=key, Body=handle, ContentMD5=_md5_b64(body))
    else:
        client.put_object(
            Bucket=bucket,
            Key=key,
            Body=body,
            ContentType="application/json",
            ContentMD5=base64.b64encode(hashlib.md5(body, usedforsecurity=False).digest()).decode(),
        )


def _md5_b64(path: Path) -> str:
    digest = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as handle:
        while chunk := handle.read(CHUNK):
            digest.update(chunk)
    return base64.b64encode(digest.digest()).decode()


def tool(name: str, env: Mapping[str, str]) -> str:
    """The absolute path of a PostgreSQL client program, from the job's `PATH`."""
    found = shutil.which(name, path=env.get("PATH"))
    if found is None:
        raise BackupError(f"{name} not found")
    return found


def run_pg_dump(database: Database, snapshot: str, path: Path) -> None:
    """Dump `snapshot` to `path`. Tests patch this to write between the export and the dump."""
    env = database.libpq_env()
    result = subprocess.run(  # noqa: S603 - fixed arguments, no shell
        [
            tool("pg_dump", env),
            "--format=custom",
            f"--snapshot={snapshot}",
            "--no-password",
            f"--file={path}",
        ],
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=DUMP_TIMEOUT_S,
    )
    if result.returncode != 0:
        logger.error("pg_dump failed", extra={"exit_code": result.returncode})
        raise BackupError(f"pg_dump failed (exit {result.returncode})")


def check_dump(database: Database, path: Path) -> None:
    env = {"PATH": database.libpq_env()["PATH"]}
    result = subprocess.run(  # noqa: S603 - fixed arguments, no shell
        [tool("pg_restore", env), "--list", str(path)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=LIST_TIMEOUT_S,
    )
    if result.returncode != 0:
        raise BackupError(f"pg_restore --list failed (exit {result.returncode})")


def count_tables_only(conn: psycopg.Connection[Any]) -> int:
    """How many app tables exist, without counting their rows."""
    return len(conn.execute(APP_TABLES).fetchall())


def count_tables(conn: psycopg.Connection[Any]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for schema, table in conn.execute(APP_TABLES).fetchall():
        query = sql.SQL("SELECT count(*) FROM {}.{}").format(
            sql.Identifier(schema), sql.Identifier(table)
        )
        row = conn.execute(query).fetchone()
        counts[f"{schema}.{table}"] = int(row[0]) if row else 0
    return counts


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(CHUNK):
            digest.update(chunk)
    return digest.hexdigest()


def object_key(prefix: str, created: datetime, suffix: str) -> str:
    return f"{prefix}/{created:%Y/%m/%d}/{prefix}-{created:%Y%m%dT%H%M%SZ}.{suffix}"


@contextmanager
def step(name: str) -> Iterator[None]:
    """Turn any failure inside into a `BackupError` naming the step and the error type."""
    try:
        yield
    except BackupError:
        raise
    except Exception as exc:
        logger.exception("backup step failed", extra={"step": name})
        raise BackupError(f"{name} failed: {type(exc).__name__}") from exc


def run_backup(
    config: BackupConfig, database: Database, *, now: datetime | None = None
) -> dict[str, Any]:
    """Take one backup and return its daily metadata. Raises `BackupError` after pinging `/fail`."""
    try:
        meta = _backup(config, database, now)
    except BackupError as exc:
        notify(config.ping_url, kind="fail", body=str(exc))
        raise
    except Exception as exc:
        # Outside any step, for example the scratch directory. Still a /fail, never a silent one.
        logger.exception("backup failed")
        reason = f"backup failed: {type(exc).__name__}"
        notify(config.ping_url, kind="fail", body=reason)
        raise BackupError(reason) from exc
    notify(
        config.ping_url,
        body=f"size_bytes={meta['dump']['size_bytes']} duration_s={meta['duration_s']}",
    )
    return meta


def _backup(config: BackupConfig, database: Database, now: datetime | None) -> dict[str, Any]:
    started = time.monotonic()
    created = (now or datetime.now(UTC)).astimezone(UTC).replace(microsecond=0)
    dump_key = object_key(config.prefix, created, "dump")
    meta_key = object_key(config.prefix, created, "json")
    buckets = [("daily", config.daily_bucket)]
    if created.weekday() == config.weekly_weekday:
        buckets.append(("weekly", config.weekly_bucket))

    with tempfile.TemporaryDirectory(prefix="wassal-backup-") as scratch:
        path = Path(scratch) / "backup.dump"
        with step("snapshot"):
            conn = psycopg.connect(**database.connect_kwargs())
        try:
            with step("snapshot"):
                conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
                conn.read_only = True
                snapshot = _scalar(conn, "SELECT pg_export_snapshot()")
                version = _scalar(conn, "SHOW server_version").split()[0]
            with step("count"):
                tables = count_tables(conn)
            with step("pg_dump"):
                run_pg_dump(database, snapshot, path)
        finally:
            conn.close()
        with step("pg_restore --list"):
            check_dump(database, path)
        with step("checksum"):
            size = path.stat().st_size
            digest = sha256_of(path)

        with step("upload"):
            client = s3_client(config)
            for _, bucket in buckets:
                upload(client, bucket, dump_key, path)

    duration = round(time.monotonic() - started, 3)
    metas = {
        retention: {
            "schema_version": SCHEMA_VERSION,
            "environment": config.environment,
            "created_at": created.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "release": config.release,
            "postgres_version": version,
            "retention_class": retention,
            "dump": {"key": dump_key, "size_bytes": size, "sha256": digest, "format": "custom"},
            "tables": tables,
            "duration_s": duration,
        }
        for retention, _ in buckets
    }
    with step("upload"):
        for retention, bucket in buckets:
            upload(client, bucket, meta_key, json.dumps(metas[retention], indent=2).encode())
    with step("state file"):
        write_state(config.state_file, metas["daily"])
    logger.info(
        "backup complete", extra={"key": dump_key, "size_bytes": size, "duration_s": duration}
    )
    return metas["daily"]


def _scalar(conn: psycopg.Connection[Any], query: str) -> str:
    row = conn.execute(query).fetchone()
    if row is None:
        raise BackupError("snapshot failed: no result")
    return str(row[0])


def write_state(path: Path, meta: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(f"{path.name}.new")
    partial.write_text(json.dumps(meta, indent=2) + "\n")
    partial.replace(path)


def notify(url: str, *, kind: monitoring.PingKind = "success", body: str) -> None:
    """Ping Healthchecks.io. A failed ping is logged: the check then alerts after its grace."""
    try:
        if kind == "success":
            monitoring.ping(url, body=body)
        else:
            monitoring.ping(url, kind=kind, body=body)
    except requests.RequestException as exc:
        logger.error("backup ping failed", extra={"error": str(exc)})
