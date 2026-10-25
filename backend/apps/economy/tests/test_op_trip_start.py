"""`trip_start` (B03 tasks.md T032, contracts/operations.md `trip_start`).

The sample pack: `line_hay` is open from the start with the starter `tuktuk`, `line_gamaa` needs
`micro_old`, `line_hay.03` is chapter 1's story trip.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable

import pytest
from django.utils import timezone
from pytest_django import Settings

from apps.accounts.models import Player
from apps.content.models import PackTripIndex
from apps.content.services import lookups
from apps.economy.models import DayCounter, PlayerFlag
from apps.economy.services.gameday import game_date
from apps.economy.tests.helpers import reasons, run, trip_result, trip_start, txn_of, wallet_of
from apps.progress.models import TripProgress, TripRun, TripSession

pytestmark = pytest.mark.django_db


def test_a_trip_not_in_the_declared_pack_is_unknown(player: Player, published_pack: int) -> None:
    # The first failing check is the reason: an unknown trip in a mode it isn't eligible for.
    result = run(
        player,
        trip_start("line_hay.99", published_pack),
        trip_start("line_hay.99", published_pack, mode="unlimited"),
    )
    assert reasons(result) == ["unknown_trip", "unknown_trip"]


@pytest.mark.parametrize("mode", ["unlimited", "challenge"])
def test_a_mode_whose_condition_is_not_met_is_not_eligible(
    player: Player, published_pack: int, mode: str
) -> None:
    # Checked before the unlock rules: line_gamaa.01 is locked too.
    result = run(
        player,
        trip_start("line_hay.01", published_pack, mode=mode),
        trip_start("line_gamaa.01", published_pack, mode=mode),
    )
    assert reasons(result) == ["not_eligible", "not_eligible"]
    assert wallet_of(player).fuel == 5


def test_a_locked_trip_is_not_unlocked(player: Player, published_pack: int) -> None:
    result = run(
        player,
        trip_start("line_gamaa.01", published_pack),  # vehicle not owned
        trip_start("line_hay.02", published_pack),  # line_hay.01 not at a star
    )
    assert reasons(result) == ["not_unlocked", "not_unlocked"]
    assert not TripSession.objects.filter(player=player).exists()


def test_the_next_trip_opens_at_one_star_on_the_previous(
    player: Player, published_pack: int
) -> None:
    first = trip_start("line_hay.01", published_pack)
    result = run(
        player,
        first,
        trip_result(first, "line_hay.01", stars=1, earnings_jenehat=1),
        trip_start("line_hay.02", published_pack),
    )
    assert reasons(result) == ["accepted", "accepted", "accepted"]


def test_a_story_trip_needs_only_its_chapter(player: Player, published_pack: int) -> None:
    assert reasons(run(player, trip_start("line_hay.03", published_pack))) == ["accepted"]


def test_an_accepted_start_spends_a_liter_and_opens_the_trip(
    player: Player, published_pack: int
) -> None:
    start = trip_start("line_hay.01", published_pack)
    result = run(player, start)
    assert reasons(result) == ["accepted"]
    assert result.results[0].outcome.granted == ()
    wallet = wallet_of(player)
    assert wallet.fuel == 4
    assert wallet.fuel_updated_at == wallet.timeline_at  # the countdown starts at the start
    assert result.wallet["fuel"] == 4
    assert result.state_version == 1
    today = game_date(timezone.now())
    counter = DayCounter.objects.get(player=player, kind=DayCounter.Kind.TRIPS_STARTED)
    assert (counter.game_date, counter.count) == (today, 1)
    bounds = lookups.trip_bounds(published_pack)["line_hay.01"]
    session = TripSession.objects.get(player=player)
    assert session.open_start == uuid.UUID(txn_of(start))
    assert (session.open_trip_id, session.open_rev) == ("line_hay.01", bounds.rev)
    assert session.open_content_version == published_pack
    assert session.open_max_earnings == bounds.max_earnings_jenehat
    assert session.open_last_station_ms == bounds.last_station_at_s * 1000
    assert session.open_started_at == wallet.timeline_at
    assert (session.open_revived, session.open_traffic_jam_ads) == (False, 0)


def test_the_bounds_come_from_the_declared_version(
    player: Player, published_packs: Callable[[int], list[int]]
) -> None:
    first, second = published_packs(2)
    PackTripIndex.objects.filter(version=first, trip_id="line_hay.01").update(
        max_earnings_jenehat=7, last_station_at_s=30
    )
    run(player, trip_start("line_hay.01", first))
    session = TripSession.objects.get(player=player)
    assert (session.open_max_earnings, session.open_last_station_ms) == (7, 30_000)
    run(player, trip_start("line_hay.01", second))
    session.refresh_from_db()
    expected = lookups.trip_bounds(second)["line_hay.01"].max_earnings_jenehat
    assert session.open_content_version == second
    assert session.open_max_earnings == expected != 7


def test_a_start_while_another_is_open_abandons_the_older(
    player: Player, published_pack: int
) -> None:
    older, newer = (
        trip_start("line_hay.01", published_pack),
        trip_start("line_hay.03", published_pack),
    )
    result = run(player, older, newer)
    assert reasons(result) == ["accepted", "accepted"]
    run_row = TripRun.objects.get(player=player)
    assert run_row.start_op == uuid.UUID(txn_of(older))
    assert (run_row.trip_id, run_row.outcome) == ("line_hay.01", TripRun.Outcome.ABANDONED)
    assert (run_row.stars, run_row.earnings_jenehat, run_row.duration_ms) == (0, 0, 0)
    assert run_row.content_version == published_pack
    progress = TripProgress.objects.get(player=player, trip_id="line_hay.01")
    assert (progress.plays, progress.best_stars, progress.first_completed_at) == (1, 0, None)
    session = TripSession.objects.get(player=player)
    assert session.open_start == uuid.UUID(txn_of(newer))
    assert session.last_start is None
    assert wallet_of(player).fuel == 3


def test_an_empty_tank_overdrafts_twice_a_game_day(
    player: Player, published_pack: int, settings: Settings
) -> None:
    assert settings.ECONOMY_FUEL_OVERDRAFT_PER_DAY == 2
    starts = [trip_start("line_hay.01", published_pack) for _ in range(8)]
    result = run(player, *starts)
    assert reasons(result) == ["accepted"] * 7 + ["cap_reached"]
    assert wallet_of(player).fuel == 0
    flag = PlayerFlag.objects.get(player=player, kind=PlayerFlag.Kind.FUEL_OVERDRAFT)
    assert flag.details["count"] == 2
    counters = dict(DayCounter.objects.filter(player=player).values_list("kind", "count"))
    assert counters == {"overdraft": 2, "trips_started": 7}
