"""`ad_reward` but `fuel_refill` (B03 tasks.md T045, contracts/operations.md `ad_reward`).

`fuel_refill` is tested with the fuel rules (test_fuel_ops.py).
"""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from pytest_django import Settings

from apps.accounts.models import Player
from apps.economy.models import Currency, LedgerEntry
from apps.economy.tests.helpers import ledger_sum, op, reasons, run, trip_result, trip_start, txn_of
from apps.progress.models import TripSession

pytestmark = pytest.mark.django_db


def ad(placement: str, ref: dict[str, Any] | str | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"ad_placement": placement}
    if ref is not None:
        payload["ref"] = ref if isinstance(ref, str) else txn_of(ref)
    return op("ad_reward", payload)


# -- result_double ---------------------------------------------------------------------------------


def test_a_finished_result_is_doubled_once(player: Player, published_pack: int) -> None:
    start = trip_start("line_hay.01", published_pack)
    result = run(
        player,
        start,
        ad("result_double", start),  # no result yet
        trip_result(start, "line_hay.01", earnings_jenehat=12),
        ad("result_double", str(uuid.uuid4())),
        ad("result_double"),
        ad("result_double", start),
        ad("result_double", start),
    )
    assert reasons(result) == [
        "accepted",
        "no_result",
        "accepted",
        "no_result",
        "no_result",
        "accepted",
        "already_doubled",
    ]
    assert ledger_sum(player, Currency.JENEHAT) == 24
    doubled = LedgerEntry.objects.get(player=player, reason="ad_result_double")
    assert (doubled.delta, doubled.ref_type, doubled.ref_id) == (12, "trip", txn_of(start))
    assert TripSession.objects.get(player=player).last_doubled is True


@pytest.mark.parametrize(
    "overrides",
    [
        {"outcome": "failed", "stars": 0, "earnings_jenehat": 0},
        {"earnings_jenehat": 0},
    ],
)
def test_a_failed_or_empty_result_is_not_doublable(
    player: Player, published_pack: int, overrides: dict[str, Any]
) -> None:
    start = trip_start("line_hay.01", published_pack)
    result = run(
        player, start, trip_result(start, "line_hay.01", **overrides), ad("result_double", start)
    )
    assert reasons(result) == ["accepted", "accepted", "not_doublable"]


def test_only_the_last_result_is_doubled(player: Player, published_pack: int) -> None:
    first, second = (
        trip_start("line_hay.01", published_pack),
        trip_start("line_hay.01", published_pack),
    )
    result = run(
        player,
        first,
        trip_result(first, "line_hay.01"),
        second,
        trip_result(second, "line_hay.01"),
        ad("result_double", first),
    )
    assert reasons(result)[-1] == "no_result"


# -- in-trip placements ----------------------------------------------------------------------------


@pytest.mark.parametrize("placement", ["trip_revive", "traffic_jam"])
def test_an_in_trip_ad_needs_the_open_start(
    player: Player, published_pack: int, placement: str
) -> None:
    refused = trip_start("line_hay.99", published_pack)
    start = trip_start("line_hay.01", published_pack)
    result = run(
        player,
        refused,
        ad(placement, refused),
        ad(placement),
        ad(placement, str(uuid.uuid4())),
        start,
        ad(placement, start),
        trip_result(start, "line_hay.01"),
        ad(placement, start),  # the trip is over
    )
    assert reasons(result) == [
        "unknown_trip",
        "dependency_rejected",
        "no_trip",
        "no_trip",
        "accepted",
        "accepted",
        "accepted",
        "no_trip",
    ]


def test_a_trip_is_revived_once(player: Player, published_pack: int) -> None:
    start = trip_start("line_hay.01", published_pack)
    result = run(player, start, ad("trip_revive", start), ad("trip_revive", start))
    assert reasons(result) == ["accepted", "accepted", "already_revived"]
    assert TripSession.objects.get(player=player).open_revived is True
    assert not LedgerEntry.objects.filter(player=player).exists()


def test_traffic_jam_ads_are_capped_per_trip(
    player: Player, published_pack: int, settings: Settings
) -> None:
    assert settings.ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP == 1
    first, second = (
        trip_start("line_hay.01", published_pack),
        trip_start("line_hay.01", published_pack),
    )
    result = run(
        player,
        first,
        ad("traffic_jam", first),
        ad("traffic_jam", first),
        second,  # a new trip has its own count
        ad("traffic_jam", second),
    )
    assert reasons(result) == ["accepted", "accepted", "cap_reached", "accepted", "accepted"]
    settings.ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP = 2
    assert reasons(run(player, ad("traffic_jam", second))) == ["accepted"]
    assert TripSession.objects.get(player=player).open_traffic_jam_ads == 2


# -- the rest --------------------------------------------------------------------------------------


def test_the_morning_piggy_is_the_servers(player: Player) -> None:
    assert reasons(run(player, ad("morning_piggy"), ad("morning_piggy", str(uuid.uuid4())))) == [
        "server_only",
        "server_only",
    ]


def test_an_unknown_placement_is_an_unknown_sku(player: Player) -> None:
    assert reasons(run(player, ad("banner"))) == ["unknown_sku"]
