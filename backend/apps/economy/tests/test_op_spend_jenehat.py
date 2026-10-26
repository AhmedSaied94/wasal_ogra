"""`spend_jenehat` (B03 tasks.md T043, contracts/operations.md `spend_jenehat`).

Sample prices: `micro_old` 1500, `ch3_shabka` 900, `salon.nish` 400, `salon.sitara` 150 JENEHAT.
"""

from __future__ import annotations

from typing import Any

import pytest

from apps.accounts.models import Player
from apps.content.models import ContentPack, PackPriceIndex
from apps.economy.models import Currency, LedgerEntry
from apps.economy.tests.helpers import (
    HAY_DONE,
    give,
    give_stars,
    grant,
    granted_of,
    ready_for_the_salon,
    reasons,
    run,
    spend,
    wallet_of,
)
from apps.progress.models import Ownership

pytestmark = pytest.mark.django_db


@pytest.fixture
def rich(player: Player) -> Player:
    grant(player, Currency.JENEHAT, 10_000)
    return player


def check(player: Player, *envelopes: dict[str, Any]) -> list[str]:
    before = wallet_of(player).jenehat
    result = reasons(run(player, *envelopes))
    if "accepted" not in result:
        assert wallet_of(player).jenehat == before
    return result


# -- the checks, in order --------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("kind", "sku"),
    [
        ("item", "salon.nope"),
        ("vehicle", "bus_x"),
        ("chapter", "ch9_none"),
        ("upgrade", "turbo"),
        ("sticker", "x"),
    ],
)
def test_an_id_the_pack_does_not_know_is_unknown(
    rich: Player, published_pack: int, kind: str, sku: str
) -> None:
    extra = {"variant": "classic"} if kind == "item" else {}
    assert check(rich, spend(kind, sku, 100, published_pack, **extra)) == ["unknown_sku"]


def test_a_known_id_without_a_jenehat_price_is_not_for_sale(
    rich: Player, published_pack: int
) -> None:
    # The starter vehicle has no price; an item priced in BONAT isn't sold for JENEHAT.
    PackPriceIndex.objects.filter(version=published_pack, sku_id="salon.sitara").update(
        currency="BONAT"
    )
    ready_for_the_salon(rich)
    assert check(
        rich,
        spend("vehicle", "tuktuk", 0, published_pack),
        spend("item", "salon.sitara", 150, published_pack, variant="plain"),
    ) == ["not_for_sale", "not_for_sale"]


def test_a_price_other_than_the_catalog_is_a_mismatch(rich: Player, published_pack: int) -> None:
    ready_for_the_salon(rich)
    assert (
        check(
            rich,
            spend("item", "salon.nish", 401, published_pack, variant="gold"),
            spend("item", "salon.nish", 399, published_pack, variant="classic"),
            spend("vehicle", "micro_old", 0, published_pack),
        )
        == ["price_mismatch"] * 3
    )


def test_a_variant_the_item_lacks_is_unknown(rich: Player, published_pack: int) -> None:
    ready_for_the_salon(rich)
    assert check(rich, spend("item", "salon.nish", 400, published_pack, variant="gold")) == [
        "unknown_variant"
    ]


def test_what_the_player_owns_is_already_owned(rich: Player, published_pack: int) -> None:
    ready_for_the_salon(rich)  # owns micro_old and ch3_shabka
    give(rich, ("item", "salon.nish"), variant="classic")
    assert (
        check(
            rich,
            spend("item", "salon.nish", 400, published_pack, variant="modern"),
            spend("vehicle", "micro_old", 1500, published_pack),
            spend("chapter", "ch3_shabka", 900, published_pack),
        )
        == ["already_owned"] * 3
    )


def test_a_locked_item_or_chapter_is_not_unlocked(rich: Player, published_pack: int) -> None:
    # The salon belongs to chapter 4; chapter 3 needs chapter 2 complete (own micro_old).
    give_stars(rich, HAY_DONE)
    assert check(
        rich,
        spend("item", "salon.nish", 400, published_pack, variant="classic"),
        spend("chapter", "ch3_shabka", 900, published_pack),
    ) == ["not_unlocked", "not_unlocked"]


def test_the_balance_is_checked_last(player: Player, published_pack: int) -> None:
    ready_for_the_salon(player)
    grant(player, Currency.JENEHAT, 399)
    assert check(
        player,
        spend("item", "salon.nish", 401, published_pack, variant="classic"),
        spend("item", "salon.nish", 400, published_pack, variant="classic"),
    ) == ["price_mismatch", "insufficient_funds"]
    assert wallet_of(player).jenehat == 399


@pytest.mark.parametrize(
    "envelope",
    [
        {"kind": "item", "sku": "salon.nish", "price": 400},  # no variant
        {"kind": "vehicle", "sku": "micro_old", "price": 1500, "variant": "red"},
    ],
)
def test_a_variant_is_required_for_an_item_and_refused_otherwise(
    rich: Player, published_pack: int, envelope: dict[str, Any]
) -> None:
    ready_for_the_salon(rich)
    extra = {"variant": envelope["variant"]} if "variant" in envelope else {}
    result = run(
        rich, spend(envelope["kind"], envelope["sku"], envelope["price"], published_pack, **extra)
    )
    assert reasons(result) == ["validation_error"]
    assert result.results[0].outcome.details == {"field": "variant"}


# -- accepted --------------------------------------------------------------------------------------


def test_an_item_is_bought_with_its_variant(rich: Player, published_pack: int) -> None:
    ready_for_the_salon(rich)
    result = run(rich, spend("item", "salon.nish", 400, published_pack, variant="crystal"))
    assert reasons(result) == ["accepted"]
    assert granted_of(result) == []
    assert wallet_of(rich).jenehat == 9_600
    entry = LedgerEntry.objects.get(player=rich, reason="item_purchase")
    assert (entry.delta, entry.ref_type, entry.ref_id) == (-400, "sku", "item:salon.nish")
    owned = Ownership.objects.get(player=rich, kind="item", sku_id="salon.nish")
    assert owned.variant == "crystal"
    assert owned.acquired_by == result.results[0].client_txn_id


def test_a_vehicle_completes_the_chapters_it_meets(rich: Player, published_pack: int) -> None:
    give_stars(rich, HAY_DONE)
    result = run(rich, spend("vehicle", "micro_old", 1500, published_pack))
    assert reasons(result) == ["accepted"]
    # Chapter 1 (line_hay complete) and chapter 2 (own micro_old) pay now.
    assert granted_of(result) == [
        {"kind": "chapter", "id": "ch1_first_job", "currency": "BONAT", "amount": 5},
        {"kind": "chapter", "id": "ch2_her_father", "currency": "BONAT", "amount": 10},
    ]
    wallet = wallet_of(rich)
    assert (wallet.jenehat, wallet.bonat) == (8_500, 15)
    assert LedgerEntry.objects.get(player=rich, reason="vehicle_purchase").delta == -1500


def test_a_chapter_is_bought_once_its_predecessor_is_complete(
    rich: Player, published_pack: int
) -> None:
    give_stars(rich, HAY_DONE)
    give(rich, ("vehicle", "micro_old"))
    result = run(rich, spend("chapter", "ch3_shabka", 900, published_pack))
    assert reasons(result) == ["accepted"]
    assert [g["id"] for g in granted_of(result)] == [
        "ch1_first_job",
        "ch2_her_father",
        "ch3_shabka",
    ]
    assert LedgerEntry.objects.get(player=rich, reason="chapter_purchase").delta == -900
    assert Ownership.objects.filter(player=rich, kind="chapter", sku_id="ch3_shabka").exists()


def test_an_upgrade_the_catalog_sells_is_bought(rich: Player, published_pack: int) -> None:
    PackPriceIndex.objects.create(
        pack=ContentPack.objects.get(version=published_pack),
        version=published_pack,
        sku_kind="upgrade",
        sku_id="seat_covers",
        currency="JENEHAT",
        amount=200,
    )
    result = run(rich, spend("upgrade", "seat_covers", 200, published_pack))
    assert reasons(result) == ["accepted"]
    assert LedgerEntry.objects.get(player=rich, reason="upgrade_purchase").delta == -200
    assert Ownership.objects.filter(player=rich, kind="upgrade", sku_id="seat_covers").exists()


def test_buying_the_last_item_of_a_room_pays_the_room_and_its_chapter(
    rich: Player, published_pack: int
) -> None:
    ready_for_the_salon(rich)
    give(rich, ("item", "salon.nish"), variant="classic")
    result = run(rich, spend("item", "salon.sitara", 150, published_pack, variant="plain"))
    assert reasons(result) == ["accepted"]
    assert granted_of(result) == [
        {"kind": "room", "id": "salon", "currency": "BONAT", "amount": 20},
        {"kind": "chapter", "id": "ch4_salon", "currency": "BONAT", "amount": 15},
    ]
    assert wallet_of(rich).bonat == 35
    rewards = LedgerEntry.objects.filter(player=rich, reason="story_reward").order_by("ref_type")
    assert [(e.ref_type, e.ref_id, e.source) for e in rewards] == [
        ("chapter", "ch4_salon", "system"),
        ("room", "salon", "system"),
    ]
