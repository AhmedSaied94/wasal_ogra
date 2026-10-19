"""Liveness and readiness (FR-010 - FR-012, contracts/api.md "Health endpoints")."""

import json
import time
from collections.abc import Iterator
from typing import Any

import pytest
from django.conf import settings
from django.db import connections
from django.db.migrations.executor import MigrationExecutor
from django.test import Client, override_settings
from django.test.utils import CaptureQueriesContext
from pytest_django import Settings

from apps.common.services import health

pytestmark = pytest.mark.django_db

UNROUTABLE = "10.255.255.1"
BOUND_S = 5.0


@pytest.fixture(autouse=True)
def _fresh_migration_check(monkeypatch: pytest.MonkeyPatch) -> None:
    """The migration pass is cached per process, so every test starts without it."""
    monkeypatch.setattr(health, "_migrations_passed", False)


@pytest.fixture
def unreachable_database(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    alias = "unreachable"
    connections.settings[alias] = {
        **connections.settings["default"],
        "HOST": UNROUTABLE,
        "PORT": "5432",
    }
    monkeypatch.setattr(health, "DATABASE_ALIAS", alias)
    yield
    connections[alias].close()
    del connections[alias]
    del connections.settings[alias]


@pytest.fixture
def unreachable_cache(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    caches = {
        **settings.CACHES,
        "unreachable": {**settings.CACHES["default"], "LOCATION": f"redis://{UNROUTABLE}:6379/0"},
    }
    monkeypatch.setattr(health, "CACHE_ALIAS", "unreachable")
    with override_settings(CACHES=caches):
        yield


def readyz(client: Client) -> tuple[int, dict[str, Any], str, float]:
    started = time.monotonic()
    response = client.get("/readyz")
    elapsed = time.monotonic() - started
    return response.status_code, json.loads(response.content), response.content.decode(), elapsed


def assert_not_ready(body: dict[str, Any], text: str, **checks: str) -> None:
    assert body["error"]["code"] == "not_ready"
    assert body["error"]["details"] == {"checks": checks}
    for leak in (UNROUTABLE, "5432", "6379", "timeout", "Timeout", "Error", "connect"):
        assert leak not in text


def test_healthz(client: Client) -> None:
    response = client.get("/healthz")
    assert response.status_code == 200
    assert json.loads(response.content) == {"status": "ok", "release": settings.RELEASE}
    assert response["Cache-Control"] == "no-store"


def test_readyz_when_everything_is_up(client: Client) -> None:
    status, body, _, _ = readyz(client)
    assert status == 200
    assert body == {
        "status": "ready",
        "checks": {"database": "pass", "cache": "pass", "migrations": "pass"},
    }


@pytest.mark.usefixtures("unreachable_database")
def test_readyz_database_unreachable(client: Client) -> None:
    status, body, text, elapsed = readyz(client)
    assert status == 503
    assert_not_ready(body, text, database="fail", cache="pass", migrations="fail")
    assert elapsed < BOUND_S


@pytest.mark.usefixtures("unreachable_cache")
def test_readyz_cache_unreachable(client: Client) -> None:
    status, body, text, elapsed = readyz(client)
    assert status == 503
    assert_not_ready(body, text, database="pass", cache="fail", migrations="pass")
    assert elapsed < BOUND_S


@pytest.mark.usefixtures("unreachable_database", "unreachable_cache")
def test_readyz_both_unreachable_stays_within_bound(client: Client) -> None:
    status, body, text, elapsed = readyz(client)
    assert status == 503
    assert_not_ready(body, text, database="fail", cache="fail", migrations="fail")
    assert elapsed < BOUND_S


def test_readyz_unapplied_migration(client: Client, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(MigrationExecutor, "migration_plan", lambda self, targets: [object()])
    status, body, text, _ = readyz(client)
    assert status == 503
    assert_not_ready(body, text, database="pass", cache="pass", migrations="fail")


@pytest.mark.usefixtures("unreachable_database")
def test_migration_check_skipped_when_database_fails(
    client: Client, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[object] = []

    def plan(self: MigrationExecutor, targets: object) -> list[object]:
        calls.append(targets)
        return []

    monkeypatch.setattr(MigrationExecutor, "migration_plan", plan)
    readyz(client)
    assert calls == []


def test_migration_pass_is_cached(client: Client, monkeypatch: pytest.MonkeyPatch) -> None:
    assert readyz(client)[0] == 200
    monkeypatch.setattr(MigrationExecutor, "migration_plan", lambda self, targets: [object()])
    assert readyz(client)[0] == 200


@pytest.mark.parametrize("urlconf", ["config.urls", "config.urls_admin"])
def test_both_roles_serve_both_endpoints(client: Client, settings: Settings, urlconf: str) -> None:
    settings.ROOT_URLCONF = urlconf
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_database_queries_have_a_statement_timeout() -> None:
    """A server that accepts the connection but stalls the query is cut off, too."""
    with CaptureQueriesContext(connections["default"]) as queries:
        assert health.readiness().ready
    statements = [query["sql"] for query in queries.captured_queries]
    timeout = "SET LOCAL statement_timeout = '1s'"
    assert statements.index(timeout) < statements.index("SELECT 1")
    assert statements.count(timeout) == 2  # the SELECT 1 and the migration check
