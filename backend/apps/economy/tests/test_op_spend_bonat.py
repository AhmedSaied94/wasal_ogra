"""`spend_bonat` (B03 tasks.md T044, contracts/operations.md `spend_bonat`).

Sample prices in BONAT: `change_bag` 10, `ledger_peek` 12, `traffic_jam` and `wake_all` 8,
`refuel_full` 30, `fuel_unlimited_1h` 80, `revive` 20.
"""

from __future__ import annotations

from datetime import timedelta
from typing import Any

import pytest
import time_machine
from django.utils import timezone

from apps.accounts.models import Player
from apps.content.models import ContentPack, PackPriceIndex
from apps.economy.models import Currency, Inventory, LedgerEntry
from apps.economy.services.timeline import to_ms
from apps.economy.tests.helpers import (
    grant,
    op,
    reasons,
    run,
    spend,
    trip_start,
    txn_of,
    wallet_of,
)
from apps.progress.models import Ownership, TripSession

pytestmark = pytest.mark.django_db

PRICES = {"change_bag": 10, "ledger_peek": 12, "traffic_jam": 8, "wake_all": 8}


@pytest.fixture
def rich(player: Player) -> Player:
    grant(player, Currency.BONAT, 1_000)
    return player


def bonat_spent(player: Player) -> int:
    return 1_000 - wallet_of(player).bonat


def entry(player: Player, reason: str) -> LedgerEntry:
    return LedgerEntry.objects.get(player=player, reason=reason)


# -- the kinds -------------------------------------------------------------------------------------


def test_each_booster_adds_one_to_the_stock(rich: Player, published_pack: int) -> None:
    envelopes = [spend("booster", b, price, published_pack) for b, price in PRICES.items()]
    assert (
        reasons(run(rich, *envelopes, spend("booster", "wake_all", 8, published_pack)))
        == ["accepted"] * 5
    )
    stock = dict(Inventory.objects.filter(player=rich).values_list("booster_id", "count"))
    assert stock == {"change_bag": 1, "ledger_peek": 1, "traffic_jam": 1, "wake_all": 2}
    assert bonat_spent(rich) == 46
    purchases = LedgerEntry.objects.filter(player=rich, reason="booster_purchase")
    assert sorted(e.ref_id for e in purchases)[0] == "booster:change_bag"


def test_a_refuel_fills_the_tank_and_a_full_tank_refuses(rich: Player, published_pack: int) -> None:
    run(rich, trip_start("line_hay.01", published_pack), trip_start("line_hay.01", published_pack))
    assert wallet_of(rich).fuel == 3
    result = run(
        rich,
        spend("fuel", "refuel_full", 30, published_pack),
        spend("fuel", "refuel_full", 30, published_pack),
    )
    assert reasons(result) == ["accepted", "tank_full"]
    assert wallet_of(rich).fuel == 5
    assert entry(rich, "fuel_purchase").delta == -30


def test_an_unlimited_hour_runs_from_now_or_from_the_end_of_the_running_one(
    rich: Player, published_pack: int
) -> None:
    run(rich, spend("fuel_unlimited", "fuel_unlimited_1h", 80, published_pack))
    first = wallet_of(rich)
    assert first.fuel_unlimited_until is not None
    assert to_ms(first.fuel_unlimited_until) - to_ms(first.timeline_at) == 3_600_000
    run(rich, spend("fuel_unlimited", "fuel_unlimited_1h", 80, published_pack))
    second = wallet_of(rich).fuel_unlimited_until
    assert second is not None
    assert to_ms(second) - to_ms(first.fuel_unlimited_until) == 3_600_000
    assert bonat_spent(rich) == 160
    # Inside the window a start costs no liter.
    assert reasons(run(rich, trip_start("line_hay.01", published_pack, mode="unlimited"))) == [
        "accepted"
    ]
    assert wallet_of(rich).fuel == 5


def test_an_ended_window_restarts_from_now(player: Player, published_pack: int) -> None:
    now = timezone.now()
    with time_machine.travel(now - timedelta(hours=3), tick=False):
        grant(player, Currency.BONAT, 1_000)  # the wallet, and its timeline, start then
        run(player, spend("fuel_unlimited", "fuel_unlimited_1h", 80, published_pack))
    run(player, spend("fuel_unlimited", "fuel_unlimited_1h", 80, published_pack))
    wallet = wallet_of(player)
    assert wallet.fuel_unlimited_until is not None
    assert to_ms(wallet.fuel_unlimited_until) - to_ms(wallet.timeline_at) == 3_600_000


def test_a_revive_needs_the_open_start(rich: Player, published_pack: int) -> None:
    refused = trip_start("line_hay.99", published_pack)
    start = trip_start("line_hay.01", published_pack)

    def revive_of(ref: str | None) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "sku_kind": "revive",
            "sku_id": "revive",
            "price": 20,
            "content_version": published_pack,
        }
        return op("spend_bonat", {**payload, **({"ref": ref} if ref else {})})

    result = run(
        rich,
        refused,
        revive_of(txn_of(refused)),
        revive_of(None),
        revive_of(txn_of(start)),  # not started yet
        start,
        revive_of(txn_of(start)),
        revive_of(txn_of(start)),
    )
    assert reasons(result) == [
        "unknown_trip",
        "dependency_rejected",
        "no_trip",
        "no_trip",
        "accepted",
        "accepted",
        "already_revived",
    ]
    assert TripSession.objects.get(player=rich).open_revived is True
    paid = entry(rich, "revive_purchase")
    assert (paid.delta, paid.ref_type, paid.ref_id) == (-20, "trip", txn_of(start))


def test_a_cosmetic_is_owned_once(rich: Player, published_pack: int) -> None:
    PackPriceIndex.objects.create(
        pack=ContentPack.objects.get(version=published_pack),
        version=published_pack,
        sku_kind="cosmetic",
        sku_id="dice_mirror",
        currency="BONAT",
        amount=15,
    )
    result = run(
        rich,
        spend("cosmetic", "dice_mirror", 15, published_pack),
        spend("cosmetic", "dice_mirror", 15, published_pack),
    )
    assert reasons(result) == ["accepted", "already_owned"]
    assert Ownership.objects.filter(player=rich, kind="cosmetic", sku_id="dice_mirror").exists()
    assert entry(rich, "cosmetic_purchase").delta == -15


# -- the common order ------------------------------------------------------------------------------


def test_the_checks_run_in_order(player: Player, published_pack: int) -> None:
    PackPriceIndex.objects.filter(version=published_pack, sku_id="wake_all").update(
        currency="JENEHAT"
    )
    result = run(
        player,
        spend("booster", "rocket", 10, published_pack),  # not one of the four
        spend("cosmetic", "dice_mirror", 15, published_pack),  # not in the catalog
        spend("sticker", "x", 1, published_pack),  # not a kind
        spend("booster", "wake_all", 8, published_pack),  # priced in JENEHAT
        spend("booster", "change_bag", 9, published_pack),
        spend("fuel", "refuel_full", 30, published_pack),  # full, and no BONAT either
        spend("booster", "change_bag", 10, published_pack),
    )
    assert reasons(result) == [
        "unknown_sku",
        "unknown_sku",
        "unknown_sku",
        "not_for_sale",
        "price_mismatch",
        "tank_full",
        "insufficient_funds",
    ]
    assert not LedgerEntry.objects.filter(player=player).exists()


def test_the_balance_is_the_servers(player: Player, published_pack: int) -> None:
    grant(player, Currency.BONAT, 15)
    result = run(
        player,
        spend("booster", "change_bag", 10, published_pack),
        spend("booster", "change_bag", 10, published_pack),
    )
    assert reasons(result) == ["accepted", "insufficient_funds"]
    assert wallet_of(player).bonat == 5


def test_a_booster_whose_purchase_was_refused_is_none_left(
    player: Player, published_pack: int
) -> None:
    start = trip_start("line_hay.01", published_pack)
    result = run(
        player,
        spend("booster", "wake_all", 8, published_pack),
        start,
        op("use_booster", {"booster_id": "wake_all", "ref": txn_of(start)}),
    )
    assert reasons(result) == ["insufficient_funds", "accepted", "none_left"]
