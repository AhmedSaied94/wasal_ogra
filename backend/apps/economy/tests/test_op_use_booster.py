"""`use_booster` (B03 tasks.md T045, contracts/operations.md `use_booster`)."""

from __future__ import annotations

import uuid
from typing import Any

import pytest

from apps.accounts.models import Player
from apps.economy.models import Currency, Inventory, LedgerEntry
from apps.economy.tests.helpers import grant, op, reasons, run, spend, trip_start, txn_of

pytestmark = pytest.mark.django_db


def use(booster: str, ref: dict[str, Any] | str) -> dict[str, Any]:
    return op(
        "use_booster", {"booster_id": booster, "ref": ref if isinstance(ref, str) else txn_of(ref)}
    )


def test_the_checks_run_in_order(player: Player, published_pack: int) -> None:
    grant(player, Currency.BONAT, 100)
    refused = trip_start("line_hay.99", published_pack)
    start = trip_start("line_hay.01", published_pack)
    result = run(
        player,
        refused,
        use("rocket", refused),  # a rejected start comes first
        use("wake_all", str(uuid.uuid4())),
        start,
        use("rocket", start),
        use("wake_all", start),
        spend("booster", "wake_all", 8, published_pack),
        use("wake_all", start),
        use("wake_all", start),
    )
    assert reasons(result) == [
        "unknown_trip",
        "dependency_rejected",
        "no_trip",
        "accepted",
        "unknown_sku",
        "none_left",
        "accepted",
        "accepted",
        "none_left",
    ]
    assert Inventory.objects.get(player=player, booster_id="wake_all").count == 0
    # A use moves no currency.
    reasons_left = LedgerEntry.objects.filter(player=player).values_list("reason", flat=True)
    assert sorted(reasons_left) == ["admin_adjustment", "booster_purchase"]


def test_a_booster_is_used_only_in_the_open_trip(player: Player, published_pack: int) -> None:
    grant(player, Currency.BONAT, 100)
    first, second = (
        trip_start("line_hay.01", published_pack),
        trip_start("line_hay.03", published_pack),
    )
    result = run(
        player,
        spend("booster", "change_bag", 10, published_pack),
        first,
        second,
        use("change_bag", first),
        use("change_bag", second),
    )
    assert reasons(result) == ["accepted", "accepted", "accepted", "no_trip", "accepted"]
