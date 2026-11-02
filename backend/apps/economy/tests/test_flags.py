"""Soft anomalies are accepted and flagged (B03 tasks.md T078, research R8, FR-040, spec US7).

line_hay.01's last station is at 55 s: the hard bound (85 %) is 46,750 ms and the plausibility
threshold (95 %) is 52,250 ms.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

import pytest
from django.utils import timezone

from apps.accounts.models import Player
from apps.economy.models import DayCounter, PlayerFlag
from apps.economy.services.gameday import game_date
from apps.economy.tests.helpers import reasons, run, trip_result, trip_start, txn_of, wallet_of
from apps.liveops import settings as live

pytestmark = pytest.mark.django_db

HARD_MS = 46_750
FAST_MS = 52_250


def played(version: int, **result: Any) -> list[dict[str, Any]]:
    start = trip_start("line_hay.01", version)
    return [start, trip_result(start, "line_hay.01", **result)]


def flags(player: Player, kind: str) -> list[PlayerFlag]:
    return list(PlayerFlag.objects.filter(player=player, kind=kind))


def test_the_thresholds_are_the_settings() -> None:
    assert (live.current()["min_duration_percent"], live.current()["fast_run_percent"]) == (85, 95)


def test_a_fast_three_star_run_is_accepted_and_flagged(player: Player, published_pack: int) -> None:
    ops = played(published_pack, duration_ms=FAST_MS - 1)
    assert reasons(run(player, *ops)) == ["accepted", "accepted"]
    assert wallet_of(player).jenehat == 10  # paid as any other run
    (flag,) = flags(player, "fast_three_star")
    assert flag.game_date == game_date(timezone.now())
    assert flag.details == {
        "count": 1,
        "start": txn_of(ops[0]),
        "duration_ms": FAST_MS - 1,
        "last_station_ms": 55_000,
    }


@pytest.mark.parametrize(
    "result",
    [
        {"duration_ms": FAST_MS},  # at the threshold
        {"duration_ms": HARD_MS, "stars": 2},  # fast, but not 3 stars
        {"outcome": "failed", "stars": 0, "earnings_jenehat": 0, "duration_ms": 1},
    ],
)
def test_other_runs_are_not_flagged(
    player: Player, published_pack: int, result: dict[str, Any]
) -> None:
    assert reasons(run(player, *played(published_pack, **result))) == ["accepted", "accepted"]
    assert flags(player, "fast_three_star") == []


def test_below_the_hard_bound_the_run_is_rejected_unflagged(
    player: Player, published_pack: int
) -> None:
    result = run(player, *played(published_pack, duration_ms=HARD_MS - 1))
    assert reasons(result) == ["accepted", "duration_out_of_bounds"]
    assert flags(player, "fast_three_star") == []
    assert wallet_of(player).jenehat == 0


def test_flags_of_a_day_are_one_row_with_a_count(player: Player, published_pack: int) -> None:
    first = played(published_pack, duration_ms=FAST_MS - 1)
    second = played(published_pack, duration_ms=HARD_MS)
    run(player, *first)
    run(player, *second)
    (flag,) = flags(player, "fast_three_star")
    assert flag.details["count"] == 2
    assert flag.details["start"] == txn_of(second[0])  # the latest occurrence


def test_too_many_starts_in_a_game_day_raise_trip_rate(
    player: Player, published_pack: int, live_settings: Callable[..., None]
) -> None:
    assert live.current()["trips_per_day_flag"] == 400
    live_settings(trips_per_day_flag=10)
    DayCounter.objects.create(
        player=player,
        game_date=game_date(timezone.now()),
        kind=DayCounter.Kind.TRIPS_STARTED,
        count=9,
    )
    starts = [trip_start("line_hay.01", published_pack) for _ in range(3)]
    assert reasons(run(player, *starts)) == ["accepted"] * 3
    (flag,) = flags(player, "trip_rate")
    assert flag.details == {"count": 2, "started_today": 12}
    assert wallet_of(player).fuel == 2  # the starts were charged as usual


def test_flag_details_hold_ids_and_numbers_only(player: Player, published_pack: int) -> None:
    run(player, *played(published_pack, duration_ms=FAST_MS - 1))
    for flag in PlayerFlag.objects.filter(player=player):
        for value in flag.details.values():
            assert isinstance(value, int | str)
            assert not isinstance(value, str) or len(value) <= 36
