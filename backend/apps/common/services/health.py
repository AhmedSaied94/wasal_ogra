"""Liveness and readiness (FR-010, FR-011, contracts/api.md "Health endpoints").

Readiness runs the cache check in a worker thread while the database check runs in the request
thread, so their bounds (3 s connect, 2 s socket) overlap and the whole check stays under 5 s.
Failure reasons go to the log only.
"""

from __future__ import annotations

import logging
from collections.abc import Callable, Iterator
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import dataclass

from django.conf import settings
from django.core.cache import DEFAULT_CACHE_ALIAS, caches
from django.db import DEFAULT_DB_ALIAS, connections, transaction
from django.db.migrations.executor import MigrationExecutor

logger = logging.getLogger("wassal.health")

PASSED = "pass"
FAILED = "fail"
PROBE_KEY = "readyz:probe"

# Module attributes so the tests can point a check at an unreachable host.
DATABASE_ALIAS = DEFAULT_DB_ALIAS
CACHE_ALIAS = DEFAULT_CACHE_ALIAS

# Once the code's migrations are all applied they stay applied for this process.
_migrations_passed = False


@dataclass(frozen=True)
class Readiness:
    checks: dict[str, str]

    @property
    def ready(self) -> bool:
        return all(result == PASSED for result in self.checks.values())


def liveness() -> dict[str, str]:
    return {"status": "ok", "release": settings.RELEASE}


def readiness() -> Readiness:
    with ThreadPoolExecutor(max_workers=1, thread_name_prefix="readyz") as pool:
        cache = pool.submit(_run, "cache", _check_cache)
        database = _run("database", _check_database)
        migrations = database and _run("migrations", _check_migrations)
        checks = {
            "database": _result(database),
            "cache": _result(cache.result()),
            "migrations": _result(migrations),
        }
    return Readiness(checks)


def _run(name: str, check: Callable[[], None]) -> bool:
    try:
        check()
    except Exception:  # any failure means not ready; the reason is logged only
        logger.warning("readiness check failed: %s", name, exc_info=True)
        return False
    return True


def _result(passed: bool) -> str:
    return PASSED if passed else FAILED


@contextmanager
def _statement_timeout() -> Iterator[None]:
    """The connect timeout bounds a dead host. This bounds a server that accepts, then stalls."""
    with transaction.atomic(using=DATABASE_ALIAS), connections[DATABASE_ALIAS].cursor() as cursor:
        cursor.execute("SET LOCAL statement_timeout = '1s'")
        yield


def _check_database() -> None:
    with _statement_timeout(), connections[DATABASE_ALIAS].cursor() as cursor:
        cursor.execute("SELECT 1")


def _check_cache() -> None:
    caches[CACHE_ALIAS].get(PROBE_KEY)


def _check_migrations() -> None:
    global _migrations_passed
    if _migrations_passed:
        return
    with _statement_timeout():
        executor = MigrationExecutor(connections[DATABASE_ALIAS])
        if executor.migration_plan(executor.loader.graph.leaf_nodes()):
            raise RuntimeError("unapplied migrations")
    _migrations_passed = True
