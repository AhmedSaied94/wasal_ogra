"""One player's batches never interleave (B03 tasks.md T036, SC-004, FR-012).

Real threads, each on its own database connection, released together by a barrier. The wallet's
row lock makes the second batch wait for the first and then see everything it stored.
"""

from __future__ import annotations

import threading
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import pytest
from django.db import connection

from apps.accounts.models import Player
from apps.economy.models import Currency, LedgerEntry, ProcessedOp
from apps.economy.services.sync import BatchResult
from apps.economy.tests.helpers import ledger_sum, run, trip_result, trip_start, wallet_of
from apps.progress.models import TripRun

pytestmark = pytest.mark.django_db(transaction=True)


def together(*calls: Callable[[], BatchResult]) -> list[BatchResult]:
    barrier = threading.Barrier(len(calls))

    def worker(call: Callable[[], BatchResult]) -> BatchResult:
        try:
            barrier.wait(timeout=10)
            return call()
        finally:
            connection.close()

    with ThreadPoolExecutor(max_workers=len(calls)) as pool:
        return list(pool.map(worker, calls))


def outcomes(result: BatchResult) -> list[Any]:
    return [(r.client_txn_id, r.outcome) for r in result.results]


def test_the_same_batch_sent_twice_at_once_is_applied_once(
    player: Player, published_pack: int
) -> None:
    start = trip_start("line_hay.01", published_pack)
    envelopes = (start, trip_result(start, "line_hay.01"))
    first, second = together(lambda: run(player, *envelopes), lambda: run(player, *envelopes))
    assert outcomes(first) == outcomes(second)
    assert [r.outcome.status for r in first.results] == ["accepted", "accepted"]
    assert wallet_of(player).jenehat == 10 == ledger_sum(player, Currency.JENEHAT)
    assert LedgerEntry.objects.filter(player=player).count() == 1
    assert ProcessedOp.objects.filter(player=player).count() == 2
    assert TripRun.objects.filter(player=player).count() == 1
    assert sorted([first.state_version, second.state_version]) == [1, 1]


def test_two_batches_at_once_apply_one_after_the_other(player: Player, published_pack: int) -> None:
    def play(earnings: int) -> Callable[[], BatchResult]:
        start = trip_start("line_hay.01", published_pack)
        envelopes = (start, trip_result(start, "line_hay.01", earnings_jenehat=earnings))
        return lambda: run(player, *envelopes)

    first, second = together(play(4), play(6))
    assert [r.outcome.status for r in first.results + second.results] == ["accepted"] * 4
    wallet = wallet_of(player)
    assert wallet.jenehat == 10 == ledger_sum(player, Currency.JENEHAT)
    assert wallet.fuel == 3
    assert wallet.state_version == 2
    assert sorted([first.state_version, second.state_version]) == [1, 2]
    assert TripRun.objects.filter(player=player).count() == 2
