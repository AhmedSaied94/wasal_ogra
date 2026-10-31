"""`tutorial_gift` and `claim_request` (B03 tasks.md T068, contracts/operations.md, research R9).

`comeback_gift` is with the session rules in test_comeback.py.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

import pytest

from apps.accounts.models import Player
from apps.content.models import PackRulesIndex
from apps.economy.models import GrantRecord, LedgerEntry
from apps.economy.tests.helpers import give, granted_of, op, reasons, run, trip_start, wallet_of

pytestmark = pytest.mark.django_db

REQUEST = "req_nish_crystal"  # salon.nish in its crystal variant, 5 BONAT


def tutorial() -> dict[str, Any]:
    return op("tutorial_gift", {})


def claim(version: int, request_id: str = REQUEST) -> dict[str, Any]:
    return op("claim_request", {"request_id": request_id, "content_version": version})


# -- tutorial_gift ---------------------------------------------------------------------------------


def test_the_tutorial_gift_fills_the_tank_once(player: Player, published_pack: int) -> None:
    result = run(
        player,
        trip_start("line_hay.01", published_pack),
        trip_start("line_hay.01", published_pack),
        tutorial(),
        tutorial(),
    )
    assert reasons(result) == ["accepted", "accepted", "accepted", "already_granted"]
    assert granted_of(result, 2) == [{"kind": "gift", "id": "tutorial", "fuel": "max"}]
    assert wallet_of(player).fuel == 5
    assert GrantRecord.objects.filter(player=player, kind="tutorial").count() == 1
    assert not LedgerEntry.objects.filter(player=player).exists()


def test_a_full_tank_takes_the_gift_unchanged(player: Player) -> None:
    result = run(player, tutorial())
    assert reasons(result) == ["accepted"]
    wallet = wallet_of(player)
    assert wallet.fuel == 5
    assert GrantRecord.objects.filter(player=player, kind="tutorial").exists()


def test_the_tutorial_gift_takes_no_payload(player: Player) -> None:
    result = run(player, op("tutorial_gift", {"liters": 5}))
    assert reasons(result) == ["validation_error"]


# -- claim_request ---------------------------------------------------------------------------------


def test_the_checks_run_in_order(player: Player, published_pack: int) -> None:
    give(player, ("item", "salon.nish"), variant="crystal")
    result = run(
        player,
        claim(published_pack, "req_none"),
        claim(published_pack),
        claim(published_pack),
    )
    assert reasons(result) == ["unknown_sku", "accepted", "already_granted"]


def test_the_longest_id_the_content_schema_allows_is_not_a_payload_error(
    player: Player, published_pack: int
) -> None:
    # `req_` and 40 more is valid content: a shorter payload bound would make the
    # server refuse a claim the phone accepted, and roll it back (M10 T145).
    longest = "req_" + "a" * 40
    assert reasons(run(player, claim(published_pack, longest))) == ["unknown_sku"]
    assert reasons(run(player, claim(published_pack, longest + "a"))) == ["validation_error"]


def test_the_item_must_be_owned_in_the_variant_asked(player: Player, published_pack: int) -> None:
    assert reasons(run(player, claim(published_pack))) == ["not_eligible"]
    give(player, ("item", "salon.nish"), variant="classic")
    assert reasons(run(player, claim(published_pack))) == ["not_eligible"]


def test_a_request_without_a_variant_needs_the_item_only(
    player: Player, published_pack: int
) -> None:
    rules = PackRulesIndex.objects.get(version=published_pack)
    rules.rules["requests"][REQUEST]["variant_id"] = ""
    rules.save()
    give(player, ("item", "salon.nish"), variant="classic")
    assert reasons(run(player, claim(published_pack))) == ["accepted"]


def test_an_accepted_claim_pays_the_reward(player: Player, published_pack: int) -> None:
    give(player, ("item", "salon.nish"), variant="crystal")
    result = run(player, claim(published_pack))
    assert granted_of(result) == [
        {"kind": "request", "id": REQUEST, "currency": "BONAT", "amount": 5}
    ]
    assert wallet_of(player).bonat == 5
    entry = LedgerEntry.objects.get(player=player)
    assert (entry.reason, entry.ref_type, entry.ref_id, entry.delta) == (
        "request_reward",
        "request",
        REQUEST,
        5,
    )
    assert entry.source == "system"  # the amount is the pack's, not the phone's
    record = GrantRecord.objects.get(player=player)
    assert (record.kind, record.key, record.op_id) == ("request", REQUEST, entry.op_id)


def test_the_reward_comes_from_the_declared_version(
    player: Player, published_packs: Callable[[int], list[int]]
) -> None:
    previous, current = published_packs(2)
    rules = PackRulesIndex.objects.get(version=current)
    rules.rules["requests"][REQUEST]["reward_bonat"] = 9
    rules.save()
    give(player, ("item", "salon.nish"), variant="crystal")
    run(player, claim(previous))
    assert wallet_of(player).bonat == 5
