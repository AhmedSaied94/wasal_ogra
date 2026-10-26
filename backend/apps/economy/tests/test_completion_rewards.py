"""Room and chapter rewards (B03 tasks.md T070, operations.md "Completion rewards", FR-028).

They are paid by the server when the thing happens, in the batch of the operation that completed
it, once each.
"""

from __future__ import annotations

import pytest

from apps.accounts.models import Player
from apps.economy.models import Currency, GrantRecord, LedgerEntry
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
    trip_result,
    trip_start,
    wallet_of,
)
from apps.progress.models import StoryState

pytestmark = pytest.mark.django_db


def story_rewards(player: Player) -> list[tuple[str, str, int]]:
    entries = LedgerEntry.objects.filter(player=player, reason="story_reward").order_by("id")
    return [(e.ref_type, e.ref_id, e.delta) for e in entries]


def test_the_last_item_of_a_room_pays_the_room_once(player: Player, published_pack: int) -> None:
    grant(player, Currency.JENEHAT, 1_000)
    ready_for_the_salon(player)
    give(player, ("item", "salon.nish"), variant="classic")
    StoryState.objects.create(player=player, chapter_id="ch4_salon", scenes_seen=["salon_done"])
    result = run(player, spend("item", "salon.sitara", 150, published_pack, variant="plain"))
    assert [(g["kind"], g["id"], g["amount"]) for g in granted_of(result)] == [
        ("room", "salon", 20),
        ("chapter", "ch4_salon", 15),
    ]
    assert story_rewards(player) == [("room", "salon", 20), ("chapter", "ch4_salon", 15)]
    chapter = StoryState.objects.get(player=player, chapter_id="ch4_salon")
    assert chapter.status == "completed"
    assert chapter.completed_at is not None
    assert chapter.scenes_seen == ["salon_done"]
    records = GrantRecord.objects.filter(player=player, kind__in=("room", "chapter"))
    assert {(r.kind, r.key, r.op_id) for r in records if r.key in ("salon", "ch4_salon")} == {
        ("room", "salon", result.results[0].client_txn_id),
        ("chapter", "ch4_salon", result.results[0].client_txn_id),
    }


def test_several_completions_in_one_batch_pay_in_order(player: Player, published_pack: int) -> None:
    grant(player, Currency.JENEHAT, 5_000)
    give_stars(player, HAY_DONE)
    result = run(
        player,
        spend("vehicle", "micro_old", 1500, published_pack),
        spend("chapter", "ch3_shabka", 900, published_pack),
        spend("item", "salon.nish", 400, published_pack, variant="classic"),
        spend("item", "salon.sitara", 150, published_pack, variant="plain"),
    )
    assert reasons(result) == ["accepted"] * 4
    assert [[g["id"] for g in granted_of(result, i)] for i in range(4)] == [
        ["ch1_first_job", "ch2_her_father"],
        ["ch3_shabka"],
        [],
        ["salon", "ch4_salon"],
    ]
    assert wallet_of(player).bonat == 5 + 10 + 10 + 20 + 15
    statuses = dict(StoryState.objects.filter(player=player).values_list("chapter_id", "status"))
    assert statuses == dict.fromkeys(
        ["ch1_first_job", "ch2_her_father", "ch3_shabka", "ch4_salon"], "completed"
    )


def test_nothing_is_paid_twice(player: Player, published_pack: int) -> None:
    grant(player, Currency.JENEHAT, 5_000)
    give_stars(player, HAY_DONE)
    run(player, spend("vehicle", "micro_old", 1500, published_pack))
    start = trip_start("line_hay.01", published_pack)
    later = run(player, start, trip_result(start, "line_hay.01"))
    assert granted_of(later, 1) == []
    assert len(story_rewards(player)) == 2


def test_a_trip_result_that_completes_a_line_pays_its_chapter(
    player: Player, published_pack: int
) -> None:
    first, second = (
        trip_start("line_hay.01", published_pack),
        trip_start("line_hay.02", published_pack),
    )
    result = run(
        player,
        first,
        trip_result(first, "line_hay.01", stars=1, earnings_jenehat=1),
        second,
        trip_result(second, "line_hay.02", duration_ms=80_000),
    )
    assert reasons(result) == ["accepted"] * 4
    assert granted_of(result, 1) == []
    assert granted_of(result, 3) == [
        {"kind": "chapter", "id": "ch1_first_job", "currency": "BONAT", "amount": 5}
    ]
    entry = LedgerEntry.objects.get(player=player, reason="story_reward")
    assert entry.source == "system"
    assert entry.op_id == result.results[3].client_txn_id


def test_a_failed_result_completes_nothing(player: Player, published_pack: int) -> None:
    give_stars(player, {"line_hay.01": 1})
    start = trip_start("line_hay.02", published_pack)
    failed = trip_result(start, "line_hay.02", outcome="failed", stars=0, earnings_jenehat=0)
    result = run(player, start, failed)
    assert granted_of(result, 1) == []
    assert story_rewards(player) == []
