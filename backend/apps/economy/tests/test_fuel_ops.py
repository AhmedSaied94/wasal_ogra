"""Fuel through the operations (B03 tasks.md T063, spec US5 scenarios 1 to 8, contracts/fuel.md)."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

import pytest
import time_machine
from django.utils import timezone
from pytest_django import Settings

from apps.accounts.models import Player
from apps.economy.models import Currency, DayCounter, PlayerFlag
from apps.economy.services import entitlements
from apps.economy.services.gameday import game_date
from apps.economy.tests.helpers import (
    grant,
    op,
    reasons,
    run,
    spend,
    trip_result,
    trip_start,
    wallet_of,
)

pytestmark = pytest.mark.django_db


def refill(at: datetime | None = None) -> dict[str, Any]:
    return op("ad_reward", {"ad_placement": "fuel_refill"}, at=at)


def created_at(player: Player, at: datetime) -> datetime:
    with time_machine.travel(at, tick=False):
        run(player)
    return at


def test_an_empty_tank_overdrafts_and_the_third_is_refused(
    player: Player, published_pack: int
) -> None:
    starts = [trip_start("line_hay.01", published_pack) for _ in range(7)]
    third = trip_start("line_hay.01", published_pack)
    result = run(player, *starts, third, trip_result(third, "line_hay.01"))
    assert reasons(result) == ["accepted"] * 7 + ["cap_reached", "dependency_rejected"]
    wallet = wallet_of(player)
    assert wallet.fuel == 0
    today = game_date(timezone.now())
    assert DayCounter.objects.get(player=player, kind="overdraft").game_date == today
    assert PlayerFlag.objects.get(player=player, kind="fuel_overdraft").details["count"] == 2


def test_unlimited_mode_costs_nothing_inside_the_window_only(
    player: Player, published_pack: int
) -> None:
    grant(player, Currency.BONAT, 100)
    result = run(
        player,
        trip_start("line_hay.01", published_pack, mode="unlimited"),
        spend("fuel_unlimited", "fuel_unlimited_1h", 80, published_pack),
        trip_start("line_hay.01", published_pack, mode="unlimited"),
        trip_start("line_hay.01", published_pack, mode="unlimited"),
    )
    assert reasons(result) == ["not_eligible", "accepted", "accepted", "accepted"]
    assert wallet_of(player).fuel == 5


def test_a_refill_ad_fills_the_tank_and_is_capped_a_day(
    player: Player, published_pack: int, settings: Settings
) -> None:
    assert settings.ECONOMY_FUEL_REFILL_DAILY_CAP == 3
    ops = [refill()]  # a full tank
    for _ in range(4):
        ops += [trip_start("line_hay.01", published_pack), refill()]
    result = run(player, *ops)
    assert reasons(result) == ["tank_full"] + ["accepted"] * 7 + ["cap_reached"]
    assert wallet_of(player).fuel == 4
    counter = DayCounter.objects.get(player=player, kind="fuel_refill_ad")
    assert counter.count == 3


def test_refill_ads_are_counted_per_effective_game_day(player: Player, published_pack: int) -> None:
    """Three offline days with three ads each, synced at once: all nine are accepted."""
    first_day = (timezone.now() - timedelta(days=3)).replace(
        hour=8, minute=0, second=0, microsecond=0
    )
    created_at(player, first_day - timedelta(minutes=1))
    ops = []
    for day in range(3):
        for n in range(3):
            at = first_day + timedelta(days=day, minutes=2 * n)
            ops += [
                trip_start("line_hay.01", published_pack, at=at),
                refill(at + timedelta(minutes=1)),
            ]
    last = first_day + timedelta(days=2, minutes=10)
    ops += [trip_start("line_hay.01", published_pack, at=last), refill(last)]
    assert reasons(run(player, *ops)) == ["accepted"] * 18 + ["accepted", "cap_reached"]
    counts = DayCounter.objects.filter(player=player, kind="fuel_refill_ad")
    assert sorted(c.count for c in counts) == [3, 3, 3]


def test_bonat_buys_a_full_tank_or_an_hour(player: Player, published_pack: int) -> None:
    grant(player, Currency.BONAT, 200)
    result = run(
        player,
        spend("fuel", "refuel_full", 30, published_pack),  # full
        trip_start("line_hay.01", published_pack),
        trip_start("line_hay.01", published_pack),
        spend("fuel", "refuel_full", 30, published_pack),
        spend("fuel_unlimited", "fuel_unlimited_1h", 80, published_pack),
    )
    assert reasons(result) == ["tank_full", "accepted", "accepted", "accepted", "accepted"]
    wallet = wallet_of(player)
    assert (wallet.fuel, wallet.bonat) == (5, 90)
    assert wallet.fuel_unlimited_until is not None


def test_a_lowered_maximum_keeps_the_liters_and_regenerates_nothing_above_it(
    player: Player, published_pack: int, settings: Settings
) -> None:
    created_at(player, timezone.now() - timedelta(hours=2))
    settings.ECONOMY_FUEL_MAX = 3
    run(player, trip_start("line_hay.01", published_pack, at=timezone.now() - timedelta(hours=1)))
    wallet = run(player).wallet
    assert (wallet["fuel"], wallet["fuel_max"]) == (4, 3)


def test_a_subscriber_has_the_larger_tank(
    player: Player, published_pack: int, settings: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    flags = {"no_interstitials": False, "fuel_max_bonus": 2}
    monkeypatch.setattr(entitlements, "flags_for", lambda player, at: flags)
    created_at(player, timezone.now() - timedelta(hours=3))
    start_at = timezone.now() - timedelta(hours=2)
    run(player, trip_start("line_hay.01", published_pack, at=start_at))
    wallet = run(player).wallet
    assert wallet["fuel_max"] == settings.ECONOMY_FUEL_MAX_SUBSCRIBER == 7
    assert wallet["fuel"] == 7


def test_every_start_costs_a_liter_replays_included(player: Player, published_pack: int) -> None:
    ops = []
    for _ in range(3):
        start = trip_start("line_hay.01", published_pack)
        ops += [start, trip_result(start, "line_hay.01")]
    run(player, *ops)
    assert wallet_of(player).fuel == 2
