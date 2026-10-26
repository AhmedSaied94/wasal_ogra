"""`trip_result` (B03 tasks.md T033, contracts/operations.md `trip_result`)."""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from pytest_django import Settings

from apps.accounts.models import Player
from apps.content.services import lookups
from apps.economy.models import Currency, LedgerEntry, ProcessedOp
from apps.economy.tests.helpers import (
    ledger_sum,
    op,
    reasons,
    result_of,
    run,
    trip_result,
    trip_start,
    txn_of,
    wallet_of,
)
from apps.progress.models import TripProgress, TripRun, TripSession

pytestmark = pytest.mark.django_db

HAY = "line_hay.01"


def started(player: Player, version: int, trip_id: str = HAY) -> dict[str, Any]:
    start = trip_start(trip_id, version)
    assert reasons(run(player, start)) == ["accepted"]
    return start


def max_earnings(version: int, trip_id: str = HAY) -> int:
    return lookups.trip_bounds(version)[trip_id].max_earnings_jenehat


def last_station_ms(version: int, trip_id: str = HAY) -> int:
    return lookups.trip_bounds(version)[trip_id].last_station_at_s * 1000


# -- the checks, in order --------------------------------------------------------------------------


def test_a_result_of_a_rejected_start_is_dependency_rejected(
    player: Player, published_pack: int
) -> None:
    refused = trip_start("line_hay.99", published_pack)
    result = run(player, refused, trip_result(refused, "line_hay.99"))
    assert reasons(result) == ["unknown_trip", "dependency_rejected"]
    # Also when the start was refused in an earlier batch.
    assert reasons(run(player, trip_result(refused, "line_hay.99"))) == ["dependency_rejected"]


def test_a_second_result_for_one_start_exists(player: Player, published_pack: int) -> None:
    start = started(player, published_pack)
    first = run(player, trip_result(start, HAY))
    second = run(player, trip_result(start, HAY))
    assert reasons(first) == ["accepted"]
    assert reasons(second) == ["result_exists"]
    assert wallet_of(player).jenehat == 10


def test_a_result_for_a_start_a_later_start_abandoned_exists(
    player: Player, published_pack: int
) -> None:
    older = started(player, published_pack)
    started(player, published_pack, "line_hay.03")
    assert reasons(run(player, trip_result(older, HAY))) == ["result_exists"]


def test_a_result_for_an_unknown_start_has_no_trip_start(
    player: Player, published_pack: int
) -> None:
    unknown = str(uuid.uuid4())
    assert reasons(run(player, trip_result(unknown, HAY))) == ["no_trip_start"]


def test_a_result_for_another_trip_is_a_mismatch(player: Player, published_pack: int) -> None:
    start = started(player, published_pack)
    assert reasons(run(player, trip_result(start, "line_hay.03"))) == ["trip_mismatch"]


@pytest.mark.parametrize(
    "overrides",
    [
        {"stars": 4},
        {"stars": -1},
        {"outcome": "failed", "stars": 1, "earnings_jenehat": 0},
        # Checked before the earnings.
        {"stars": 5, "earnings_jenehat": 100_000},
    ],
)
def test_stars_out_of_their_bounds(
    player: Player, published_pack: int, overrides: dict[str, Any]
) -> None:
    start = started(player, published_pack)
    assert reasons(run(player, trip_result(start, HAY, **overrides))) == ["stars_out_of_bounds"]


def test_earnings_out_of_their_bounds(player: Player, published_pack: int) -> None:
    ceiling = max_earnings(published_pack)
    cases: list[dict[str, Any]] = [
        {"earnings_jenehat": ceiling + 1},
        {"earnings_jenehat": -1},
        {"outcome": "failed", "stars": 0, "earnings_jenehat": 1},
    ]
    for overrides in cases:
        start = started(player, published_pack)
        assert reasons(run(player, trip_result(start, HAY, **overrides))) == [
            "earnings_out_of_bounds"
        ], overrides
    start = started(player, published_pack)
    assert reasons(run(player, trip_result(start, HAY, earnings_jenehat=ceiling))) == ["accepted"]


def test_a_finished_trip_faster_than_the_bound_is_refused(
    player: Player, published_pack: int, settings: Settings
) -> None:
    floor = settings.SYNC_MIN_DURATION_PERCENT * last_station_ms(published_pack) // 100
    start = started(player, published_pack)
    assert reasons(run(player, trip_result(start, HAY, duration_ms=floor - 1))) == [
        "duration_out_of_bounds"
    ]
    assert reasons(run(player, trip_result(start, HAY, duration_ms=floor))) == ["accepted"]
    # Failed trips can end at any time.
    failed = started(player, published_pack)
    short: dict[str, Any] = {
        "outcome": "failed",
        "stars": 0,
        "earnings_jenehat": 0,
        "duration_ms": 1,
    }
    assert reasons(run(player, trip_result(failed, HAY, **short))) == ["accepted"]


# -- the shape -------------------------------------------------------------------------------------


def test_unknown_keys_inside_the_result_are_ignored(player: Player, published_pack: int) -> None:
    start = started(player, published_pack)
    result = run(player, trip_result(start, HAY, new_engine_field={"a": 1}))
    assert reasons(result) == ["accepted"]


def test_a_result_over_8_kb_is_a_validation_error(player: Player, published_pack: int) -> None:
    start = started(player, published_pack)
    result = run(player, trip_result(start, HAY, padding="x" * 8200))
    assert reasons(result) == ["validation_error"]
    assert result.results[0].outcome.details == {"field": "result"}


@pytest.mark.parametrize(
    ("change", "field"),
    [
        ({"stars": 2.0}, "result.stars"),
        ({"stars": True}, "result.stars"),
        ({"earnings_jenehat": "10"}, "result.earnings_jenehat"),
        ({"outcome": "won"}, "result.outcome"),
        ({"duration_ms": -1}, "result.duration_ms"),
        ({"revived": 0}, "result.revived"),
        ({"mistakes": 2}, "result.mistakes"),
        ({"boosters_used": ["wake_all", 3]}, "result.boosters_used"),
        ({"command_log_hash": "a" * 65}, "result.command_log_hash"),
    ],
)
def test_a_read_key_of_the_wrong_type_is_a_validation_error(
    player: Player, published_pack: int, change: dict[str, Any], field: str
) -> None:
    start = started(player, published_pack)
    result = run(player, trip_result(start, HAY, **change))
    assert reasons(result) == ["validation_error"]
    assert result.results[0].outcome.details == {"field": field}


def test_a_missing_read_key_is_a_validation_error(player: Player, published_pack: int) -> None:
    start = started(player, published_pack)
    body = result_of(HAY)
    del body["stars"]
    envelope = op("trip_result", {"trip_start_txn": txn_of(start), "result": body})
    result = run(player, envelope)
    assert reasons(result) == ["validation_error"]
    assert result.results[0].outcome.details == {"field": "result.stars"}


# -- the effects -----------------------------------------------------------------------------------


def test_an_accepted_result_pays_records_and_closes_the_trip(
    player: Player, published_pack: int
) -> None:
    start = started(player, published_pack)
    result = run(
        player,
        trip_result(
            start,
            HAY,
            stars=2,
            earnings_jenehat=8,
            fights=1,
            mistakes=[{"kind": "wrong_change"}, {"kind": "missed_stop"}],
            duration_ms=90_000,
            boosters_used=["wake_all"],
            revived=True,
        ),
    )
    assert reasons(result) == ["accepted"]
    assert result.wallet["jenehat"] == 8
    assert wallet_of(player).jenehat == 8 == ledger_sum(player, Currency.JENEHAT)
    entry = LedgerEntry.objects.get(player=player)
    assert (entry.reason, entry.ref_type, entry.ref_id) == ("trip_earnings", "trip", txn_of(start))
    assert entry.op_id == result.results[0].client_txn_id
    run_row = TripRun.objects.get(player=player)
    assert run_row.start_op == uuid.UUID(txn_of(start))
    assert (run_row.outcome, run_row.stars, run_row.fights, run_row.mistakes_count) == (
        "finished",
        2,
        1,
        2,
    )
    assert (run_row.earnings_jenehat, run_row.duration_ms, run_row.revived) == (8, 90_000, True)
    assert run_row.boosters_used == ["wake_all"]
    assert run_row.command_log_hash == "a" * 64
    assert (run_row.content_version, run_row.client_version) == (published_pack, "1.0.0+1")
    progress = TripProgress.objects.get(player=player, trip_id=HAY)
    assert (progress.plays, progress.best_stars, progress.best_time_ms) == (1, 2, 90_000)
    assert progress.first_completed_at is not None
    session = TripSession.objects.get(player=player)
    assert session.open_start is None
    assert session.open_trip_id == ""
    assert session.last_start == uuid.UUID(txn_of(start))
    assert (session.last_outcome, session.last_earnings, session.last_doubled) == (
        "finished",
        8,
        False,
    )


def test_progress_keeps_the_bests_and_counts_every_play(
    player: Player, published_pack: int
) -> None:
    plays: list[dict[str, Any]] = [
        {"stars": 2, "duration_ms": 80_000},
        {"stars": 3, "duration_ms": 95_000},
        {"stars": 1, "duration_ms": 70_000},
        {"outcome": "failed", "stars": 0, "earnings_jenehat": 0, "duration_ms": 10_000},
    ]
    firsts = []
    for overrides in plays:
        start = started(player, published_pack)
        assert reasons(run(player, trip_result(start, HAY, **overrides))) == ["accepted"]
        firsts.append(TripProgress.objects.get(player=player, trip_id=HAY).first_completed_at)
    progress = TripProgress.objects.get(player=player, trip_id=HAY)
    assert (progress.plays, progress.best_stars, progress.best_time_ms) == (4, 3, 70_000)
    assert len(set(firsts)) == 1


def test_a_failed_first_play_completes_nothing(player: Player, published_pack: int) -> None:
    start = started(player, published_pack)
    failed: dict[str, Any] = {"outcome": "failed", "stars": 0, "earnings_jenehat": 0}
    run(player, trip_result(start, HAY, **failed))
    progress = TripProgress.objects.get(player=player, trip_id=HAY)
    assert (progress.plays, progress.best_stars, progress.best_time_ms) == (1, 0, None)
    assert progress.first_completed_at is None
    assert not LedgerEntry.objects.filter(player=player).exists()
    assert ProcessedOp.objects.filter(player=player, status="accepted").count() == 2
