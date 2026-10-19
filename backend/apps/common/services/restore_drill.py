"""The monthly restore drill (FR-040, FR-040a, contracts/operations.md "Restore drill").

Two steps, run in two containers so that no single one holds both the storage key and a database:

- `fetch` (drill key, no database): download the newest *complete* backup and its metadata into a
  directory, checking its size and sha256;
- `check` (database only, no outside access): restore it into a fresh database and check the
  restore, the migrations, the row counts and the registered invariants. It returns the result line
  (data-model "Restore drill result").

Failure reasons name the check and the error type, never a key, password or connection string.
"""

from __future__ import annotations

import hashlib
import json
import logging
import subprocess
import time
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import psycopg
from django.db.migrations.loader import MigrationLoader

from apps.common.services import backups, invariants

logger = logging.getLogger(__name__)

DUMP_FILE = "backup.dump"
META_FILE = "backup.json"
RESTORE_TIMEOUT_S = 60 * 60
MAX_LISTED = 3
PASS, FAIL = "pass", "fail"


class DrillError(Exception):
    """The drill couldn't produce a result. The message is a short reason with no secrets."""


@dataclass(frozen=True)
class FetchConfig:
    s3_endpoint: str
    s3_region: str
    daily_bucket: str
    weekly_bucket: str
    key_id: str
    app_key: str = field(repr=False)
    prefix: str


def utc_stamp(moment: datetime) -> str:
    return moment.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


# -- fetch -----------------------------------------------------------------------------------------


def fetch(config: FetchConfig, directory: Path) -> dict[str, Any]:
    """Download the newest complete backup into `directory` and return its metadata."""
    # Files from an earlier, failed fetch must never pair with this one's.
    for name in (DUMP_FILE, META_FILE):
        (directory / name).unlink(missing_ok=True)
    client = backups.b2_client(config.s3_endpoint, config.s3_region, config.key_id, config.app_key)
    try:
        bucket, base = newest_complete(client, config)
        meta = json.loads(_get(client, bucket, f"{base}.json").read())
    except DrillError:
        raise
    except Exception as exc:
        logger.exception("drill fetch failed")
        raise DrillError(f"listing failed: {type(exc).__name__}") from exc
    dump = meta.get("dump") if isinstance(meta, dict) else None
    if (
        not isinstance(dump, dict)
        or meta.get("schema_version") != backups.SCHEMA_VERSION
        or dump.get("key") != f"{base}.dump"
    ):
        raise DrillError("metadata invalid")
    try:
        size, digest = _download(client, bucket, dump["key"], directory / DUMP_FILE)
    except Exception as exc:
        logger.exception("drill download failed")
        raise DrillError(f"download failed: {type(exc).__name__}") from exc
    if size != dump.get("size_bytes"):
        raise DrillError("size mismatch")
    if digest != dump.get("sha256"):
        raise DrillError("sha256 mismatch")
    (directory / META_FILE).write_text(json.dumps(meta, indent=2) + "\n")
    return meta  # type: ignore[no-any-return]


def newest_complete(client: Any, config: FetchConfig) -> tuple[str, str]:
    """The bucket and key base of the newest backup that has both its dump and its metadata."""
    candidates: list[tuple[str, int, str, str]] = []
    for rank, bucket in enumerate((config.daily_bucket, config.weekly_bucket)):
        names: set[str] = set()
        for page in client.get_paginator("list_objects_v2").paginate(
            Bucket=bucket, Prefix=f"{config.prefix}/"
        ):
            names.update(item["Key"] for item in page.get("Contents", []))
        for name in names:
            base = name.removesuffix(".json")
            if name.endswith(".json") and f"{base}.dump" in names:
                # The file name ends in a UTC timestamp, so it sorts by time. On a tie (the same
                # backup in both buckets) the daily copy wins.
                candidates.append((base.rsplit("/", 1)[-1], -rank, bucket, base))
    if not candidates:
        raise DrillError("no complete backup")
    _, _, bucket, base = max(candidates)
    return bucket, base


def _get(client: Any, bucket: str, key: str) -> Any:
    return client.get_object(Bucket=bucket, Key=key)["Body"]


def _download(client: Any, bucket: str, key: str, path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    with path.open("wb") as handle:
        for chunk in _get(client, bucket, key).iter_chunks(backups.CHUNK):
            handle.write(chunk)
            digest.update(chunk)
            size += len(chunk)
    return size, digest.hexdigest()


# -- check -----------------------------------------------------------------------------------------


def check(
    directory: Path, settings_dict: Mapping[str, Any], *, tolerance: int, release: str
) -> dict[str, Any]:
    """Restore the fetched backup into the (fresh) database and return the result line."""
    started_at = datetime.now(UTC)
    started = time.monotonic()
    try:
        meta = json.loads((directory / META_FILE).read_text())
        backup_key = str(meta["dump"]["key"])
        backup_created_at = str(meta["created_at"])
        expected = {str(name): int(count) for name, count in meta["tables"].items()}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        raise DrillError("metadata missing or invalid") from None

    database = backups.Database.from_settings(settings_dict)
    checks: dict[str, Any] = {
        "restore": FAIL,
        "migrations": FAIL,
        "row_counts": FAIL,
        "invariants": {},
    }
    failures: list[str] = []

    restore_started = time.monotonic()
    restored = _run_check(failures, "restore", lambda: restore(database, directory / DUMP_FILE))
    restore_duration = round(time.monotonic() - restore_started, 3)
    if restored:
        checks["restore"] = PASS
        try:
            with psycopg.connect(**database.connect_kwargs()) as conn:
                if _run_check(failures, "migrations", lambda: migration_problems(conn)):
                    checks["migrations"] = PASS
                conn.rollback()
                if _run_check(
                    failures, "row counts", lambda: count_problems(conn, expected, tolerance)
                ):
                    checks["row_counts"] = PASS
                conn.rollback()
                results = invariants.run_all(conn)
        except psycopg.Error as exc:
            logger.exception("drill database connection failed")
            failures.append(f"database raised {type(exc).__name__}")
            results = {name: (False, "not run") for name in invariants.registered()}
        checks["invariants"] = {name: PASS if ok else FAIL for name, (ok, _) in results.items()}
        failed = [name for name, (ok, _) in results.items() if not ok]
        if failed:
            failures.append(f"invariants failed: {', '.join(failed[:MAX_LISTED])}")

    return {
        "started_at": utc_stamp(started_at),
        "finished_at": utc_stamp(datetime.now(UTC)),
        "backup_key": backup_key,
        "backup_created_at": backup_created_at,
        "release": release,
        "checks": checks,
        "restore_duration_s": restore_duration,
        "total_duration_s": round(time.monotonic() - started, 3),
        "outcome": FAIL if failures else PASS,
        "failure": "; ".join(failures) or None,
    }


def _run_check(failures: list[str], name: str, run: Callable[[], str | None]) -> bool:
    """Run one check, which returns its problem or `None`. A raised error is a failed check."""
    try:
        problem = run()
    except Exception as exc:
        logger.exception("drill check failed", extra={"check": name})
        problem = f"{name} raised {type(exc).__name__}"
    if problem:
        failures.append(problem)
        return False
    return True


def restore(database: backups.Database, dump: Path) -> str | None:
    """Restore into the drill's database, which must be empty: never load a dump on top of data."""
    with psycopg.connect(**database.connect_kwargs()) as conn:
        if backups.count_tables_only(conn):
            return "restore refused: the target database isn't empty"
    env = database.libpq_env()
    result = subprocess.run(  # noqa: S603 - fixed arguments, no shell
        [
            backups.tool("pg_restore", env),
            "--no-owner",
            "--no-privileges",
            "--exit-on-error",
            "--no-password",
            f"--dbname={database.name}",
            str(dump),
        ],
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=RESTORE_TIMEOUT_S,
    )
    if result.returncode != 0:
        # pg_restore's message can quote SQL and data from the dump, so only its exit code is kept.
        logger.error("pg_restore failed", extra={"exit_code": result.returncode})
        return f"restore failed (exit {result.returncode})"
    return None


def migration_problems(conn: psycopg.Connection[Any]) -> str | None:
    """Migrations this code would still apply, or applied migrations this code doesn't have.

    The graph comes from the code on disk; what's applied comes from the restored database.
    """
    if conn.execute("SELECT to_regclass('django_migrations')").fetchone() == (None,):
        return "migrations: django_migrations is missing"
    applied = {
        (str(app), str(name))
        for app, name in conn.execute("SELECT app, name FROM django_migrations").fetchall()
    }
    loader = MigrationLoader(None, ignore_no_migrations=True)
    # A squashed migration counts as applied once everything it replaces is (as Django does), and
    # the names it replaces stay known after their files are deleted.
    known = set(loader.disk_migrations)
    for migration in loader.disk_migrations.values():
        known.update(migration.replaces)

    def is_applied(key: tuple[str, str]) -> bool:
        replaces = loader.graph.nodes[key].replaces
        return key in applied or (bool(replaces) and all(r in applied for r in replaces))

    pending = sorted(
        f"{app}.{name}" for app, name in loader.graph.nodes if not is_applied((app, name))
    )
    unknown = sorted(f"{app}.{name}" for app, name in applied - known)
    problems = []
    if pending:
        problems.append(f"{len(pending)} pending ({', '.join(pending[:MAX_LISTED])})")
    if unknown:
        problems.append(f"{len(unknown)} unknown ({', '.join(unknown[:MAX_LISTED])})")
    return f"migrations: {', '.join(problems)}" if problems else None


def count_problems(
    conn: psycopg.Connection[Any], expected: Mapping[str, int], tolerance: int
) -> str | None:
    actual = backups.count_tables(conn)
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    off = sorted(
        f"{name} {actual[name]} != {expected[name]}"
        for name in set(expected) & set(actual)
        if abs(actual[name] - expected[name]) > tolerance
    )
    problems = [f"missing {name}" for name in missing] + [f"extra {name}" for name in extra] + off
    if not problems:
        return None
    more = f" and {len(problems) - MAX_LISTED} more" if len(problems) > MAX_LISTED else ""
    return f"row counts: {', '.join(problems[:MAX_LISTED])}{more}"
