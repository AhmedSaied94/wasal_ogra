"""The drill's invariant registry (data-model "Invariant check")."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import psycopg
import pytest
from django.db import connection

from apps.common.services import invariants
from apps.common.services.backups import Database

pytestmark = pytest.mark.django_db(transaction=True)


@pytest.fixture
def conn() -> Iterator[psycopg.Connection[Any]]:
    with psycopg.connect(**Database.from_settings(connection.settings_dict).connect_kwargs()) as c:
        yield c


@pytest.fixture
def registry() -> Iterator[None]:
    before = set(invariants.registered())
    yield
    for name in set(invariants.registered()) - before:
        invariants.unregister(name)


def test_the_registered_invariants() -> None:
    # B01 registers none. B04 adds the content one; B03 will add economy.wallet_equals_ledger.
    assert set(invariants.registered()) == {"content.published_packs_intact"}


def test_a_name_can_be_registered_once(registry: None) -> None:
    invariants.register("test.once")(lambda conn: (True, "ok"))

    with pytest.raises(ValueError, match="registered twice"):
        invariants.register("test.once")(lambda conn: (True, "ok"))


def test_a_check_that_raises_fails_without_hiding_the_others(
    registry: None, conn: psycopg.Connection[Any], caplog: pytest.LogCaptureFixture
) -> None:
    def broken(c: psycopg.Connection[Any]) -> tuple[bool, str]:
        c.execute("SELECT * FROM no_such_table")
        return True, "unreachable"

    def after(c: psycopg.Connection[Any]) -> tuple[bool, str]:
        # The connection is usable again: the failed transaction was rolled back.
        row = c.execute("SELECT 1").fetchone()
        return row == (1,), "ok"

    invariants.register("test.broken")(broken)
    invariants.register("test.after")(after)

    results = invariants.run_all(conn)

    assert results["test.broken"] == (False, "raised UndefinedTable")
    assert results["test.after"] == (True, "ok")
    # The traceback is logged, so a failing drill can be debugged from the journal.
    [record] = [r for r in caplog.records if r.getMessage() == "invariant raised"]
    assert record.exc_info is not None
