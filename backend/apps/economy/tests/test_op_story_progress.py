"""`story_progress` (B03 tasks.md T071, contracts/operations.md `story_progress`)."""

from __future__ import annotations

from typing import Any

import pytest

from apps.accounts.models import Player
from apps.content.models import PackRulesIndex
from apps.economy.tests.helpers import op, reasons, run, wallet_of
from apps.progress.models import StoryState

pytestmark = pytest.mark.django_db


def seen(version: int, chapter: str, scene: str) -> dict[str, Any]:
    return op(
        "story_progress", {"chapter_id": chapter, "scene_id": scene, "content_version": version}
    )


def test_a_scene_is_recorded_once(player: Player, published_pack: int) -> None:
    result = run(
        player,
        seen(published_pack, "ch1_first_job", "the_stand"),
        seen(published_pack, "ch1_first_job", "the_stand"),
    )
    assert reasons(result) == ["accepted", "accepted"]
    row = StoryState.objects.get(player=player)
    assert (row.chapter_id, row.status, row.scenes_seen) == ("ch1_first_job", "open", ["the_stand"])
    assert wallet_of(player).state_version == 1
    # A scene seen again changes nothing, so the state keeps its version.
    assert reasons(run(player, seen(published_pack, "ch1_first_job", "the_stand"))) == ["accepted"]
    assert wallet_of(player).state_version == 1


def test_an_unknown_chapter_or_scene_is_an_unknown_sku(player: Player, published_pack: int) -> None:
    result = run(
        player,
        seen(published_pack, "ch9_none", "the_stand"),
        seen(published_pack, "ch1_first_job", "the_end"),
    )
    assert reasons(result) == ["unknown_sku", "unknown_sku"]
    assert not StoryState.objects.filter(player=player).exists()


def test_a_scene_of_a_locked_chapter_is_not_unlocked(player: Player, published_pack: int) -> None:
    rules = PackRulesIndex.objects.get(version=published_pack)
    rules.rules["chapters"]["ch2_her_father"]["scenes"] = ["dinner"]
    rules.save()
    assert reasons(run(player, seen(published_pack, "ch2_her_father", "dinner"))) == [
        "not_unlocked"
    ]
    assert not StoryState.objects.filter(player=player).exists()


def test_a_completed_chapter_keeps_its_status(player: Player, published_pack: int) -> None:
    StoryState.objects.create(player=player, chapter_id="ch1_first_job", status="completed")
    assert reasons(run(player, seen(published_pack, "ch1_first_job", "the_stand"))) == ["accepted"]
    row = StoryState.objects.get(player=player)
    assert (row.status, row.scenes_seen) == ("completed", ["the_stand"])
