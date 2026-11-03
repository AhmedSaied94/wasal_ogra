"""Every placement of glossary §3.4, one past its cap, on the server (B07 US4, FR-020-FR-022, R15).

The four the phone applies go through sync (B03's handlers); `morning_piggy` goes through the
callback. Each cap is driven at its default and at a changed value. `interstitial_between_trips`
grants nothing and is accepted by neither path.
"""

from __future__ import annotations

from typing import Any

import pytest

from apps.accounts.models import Player
from apps.ads.tests.conftest import Callback
from apps.economy.tests.helpers import op, reasons, run, trip_result, trip_start, txn_of
from apps.liveops import settings as live

pytestmark = pytest.mark.django_db

TRIP = "line_hay.01"


def ad(placement: str, ref: dict[str, Any] | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"ad_placement": placement}
    if ref is not None:
        payload["ref"] = txn_of(ref)
    return op("ad_reward", payload)


def test_result_double_once_per_result(player: Player, published_pack: int) -> None:
    start = trip_start(TRIP, published_pack)
    result = run(
        player,
        start,
        trip_result(start, TRIP),
        ad("result_double", start),
        ad("result_double", start),
    )
    assert reasons(result)[2:] == ["accepted", "already_doubled"]


def test_trip_revive_once_per_trip(player: Player, published_pack: int) -> None:
    start = trip_start(TRIP, published_pack)
    result = run(player, start, ad("trip_revive", start), ad("trip_revive", start))
    assert reasons(result)[1:] == ["accepted", "already_revived"]


@pytest.mark.parametrize("cap", [None, 2])
def test_traffic_jam_one_past_its_cap(
    player: Player, published_pack: int, live_settings: Any, cap: int | None
) -> None:
    if cap is not None:
        live_settings(traffic_jam_ads_per_trip=cap)
    limit = live.current()["traffic_jam_ads_per_trip"]
    start = trip_start(TRIP, published_pack)
    result = run(player, start, *[ad("traffic_jam", start) for _ in range(limit + 1)])
    assert reasons(result)[1:] == ["accepted"] * limit + ["cap_reached"]


@pytest.mark.parametrize("cap", [None, 1])
def test_fuel_refill_one_past_its_daily_cap(
    player: Player, published_pack: int, live_settings: Any, cap: int | None
) -> None:
    if cap is not None:
        live_settings(ads_fuel_refill_daily_cap=cap)
    limit = live.current()["ads_fuel_refill_daily_cap"]
    ops: list[dict[str, Any]] = []
    for _ in range(limit + 1):  # a litre spent, then a refill
        ops += [trip_start(TRIP, published_pack), ad("fuel_refill")]
    refills = reasons(run(player, *ops))[1::2]
    assert refills == ["accepted"] * limit + ["cap_reached"]


@pytest.mark.parametrize("cap", [None, 2])
def test_morning_piggy_one_past_its_daily_cap(
    player: Player, callback: Callback, live_settings: Any, cap: int | None
) -> None:
    from apps.ads.models import AdReward

    if cap is not None:
        live_settings(ads_morning_piggy_daily_cap=cap)
    limit = live.current()["ads_morning_piggy_daily_cap"]
    for _ in range(limit + 1):
        assert callback(user_id=str(player.pk)).status_code == 200
    outcomes = list(AdReward.objects.order_by("created_at").values_list("outcome", flat=True))
    assert outcomes == ["granted"] * limit + ["cap_reached"]


def test_the_piggy_is_never_granted_through_sync(player: Player) -> None:
    assert reasons(run(player, ad("morning_piggy"))) == ["server_only"]


def test_no_path_accepts_an_interstitial(player: Player, callback: Callback) -> None:
    from apps.ads.models import AdReward

    assert reasons(run(player, ad("interstitial_between_trips"))) == ["unknown_sku"]
    callback(user_id=str(player.pk), placement="interstitial_between_trips")
    assert AdReward.objects.get().outcome == "not_server_placement"
