"""The unlock and completion rules (B03 tasks.md T012, research R6).

They run over the sample pack's rules document: assembled from `content/examples/sample` without a
database, and checked once against the document a real publish writes.

The phone ports every test here, one Dart test each named after it
(`apps/mobile/test/core/progress/unlocks_test.dart`, M08). When a test changes, is added or is
removed, change the port in the same PR.
"""

from __future__ import annotations

import copy
from pathlib import Path
from typing import Any

import pytest
from django.conf import settings
from wassal_content.source import assemble_pack, read_layout

from apps.accounts.models import User
from apps.content.services import lookups
from apps.progress.services import unlocks
from apps.progress.services.unlocks import Completion, PlayerView

SAMPLE = settings.BASE_DIR.parent / "content" / "examples" / "sample"


@pytest.fixture(scope="module")
def rules() -> dict[str, Any]:
    tree, findings = read_layout(SAMPLE)
    assert not findings
    return lookups.rules_document(assemble_pack(tree, 1))


def view(
    stars: dict[str, int] | None = None, owned: set[tuple[str, str]] | None = None
) -> PlayerView:
    return PlayerView(best_stars=stars or {}, owned=frozenset(owned or set()))


HAY_DONE = {"line_hay.01": 1, "line_hay.02": 3}
SALON = {("item", "salon.nish"), ("item", "salon.sitara")}


@pytest.mark.django_db
def test_the_published_rules_are_the_assembled_ones(
    rules: dict[str, Any], sample_reviewed: User, publisher: User, packs_dir: Path
) -> None:
    from apps.content.tests.test_build import built
    from apps.content.tests.test_publish import published

    stored = published(built(sample_reviewed), publisher)
    assert lookups.rules(stored.version or 0) == rules


# -- vehicles and lines ---------------------------------------------------------------------------


def test_a_vehicle_is_owned_by_its_starter_flag_or_by_ownership(rules: dict[str, Any]) -> None:
    assert unlocks.vehicle_owned(rules, view(), "tuktuk")
    assert not unlocks.vehicle_owned(rules, view(), "micro_old")
    assert unlocks.vehicle_owned(rules, view(owned={("vehicle", "micro_old")}), "micro_old")
    assert not unlocks.vehicle_owned(rules, view(), "no_such_vehicle")


def test_a_line_unlocks_at_start_or_with_its_vehicle(rules: dict[str, Any]) -> None:
    assert unlocks.line_unlocked(rules, view(), "line_hay")
    assert not unlocks.line_unlocked(rules, view(), "line_gamaa")
    assert unlocks.line_unlocked(rules, view(owned={("vehicle", "micro_old")}), "line_gamaa")
    assert not unlocks.line_unlocked(rules, view(), "line_souq")


def test_a_line_can_unlock_when_another_line_is_complete(rules: dict[str, Any]) -> None:
    changed = copy.deepcopy(rules)
    changed["lines"]["line_gamaa"]["unlock"] = {"kind": "line_complete", "line_id": "line_hay"}
    assert not unlocks.line_unlocked(changed, view({"line_hay.01": 1}), "line_gamaa")
    assert unlocks.line_unlocked(changed, view(HAY_DONE), "line_gamaa")
    changed["lines"]["line_gamaa"]["unlock"] = {"kind": "unknown"}
    assert not unlocks.line_unlocked(changed, view(HAY_DONE), "line_gamaa")


def test_a_line_is_complete_when_every_regular_trip_has_a_star(rules: dict[str, Any]) -> None:
    assert not unlocks.line_complete(rules, view(), "line_hay")
    assert not unlocks.line_complete(rules, view({"line_hay.01": 3}), "line_hay")
    # The story trip line_hay.03 doesn't count.
    assert unlocks.line_complete(rules, view(HAY_DONE), "line_hay")
    assert not unlocks.line_complete(rules, view({"line_hay.01": 1, "line_hay.02": 0}), "line_hay")
    assert not unlocks.line_complete(rules, view(HAY_DONE), "no_such_line")


def test_a_line_without_regular_trips_is_never_complete(rules: dict[str, Any]) -> None:
    changed = copy.deepcopy(rules)
    for trip in changed["lines"]["line_hay"]["trips"]:
        changed["trips"][trip]["kind"] = "story"
    assert not unlocks.line_complete(changed, view(HAY_DONE), "line_hay")


# -- trips ----------------------------------------------------------------------------------------


def test_the_first_trip_of_a_line_is_free(rules: dict[str, Any]) -> None:
    assert unlocks.trip_unlocked(rules, view(), "line_hay.01")


def test_a_later_trip_needs_the_previous_regular_one_at_a_star(rules: dict[str, Any]) -> None:
    assert not unlocks.trip_unlocked(rules, view(), "line_hay.02")
    assert not unlocks.trip_unlocked(rules, view({"line_hay.01": 0}), "line_hay.02")
    assert unlocks.trip_unlocked(rules, view({"line_hay.01": 1}), "line_hay.02")


def test_a_trip_needs_its_line_and_its_vehicle(rules: dict[str, Any]) -> None:
    assert not unlocks.trip_unlocked(rules, view(), "line_gamaa.01")
    owner = view(owned={("vehicle", "micro_old")})
    assert unlocks.trip_unlocked(rules, owner, "line_gamaa.01")
    assert not unlocks.trip_unlocked(rules, owner, "line_gamaa.02")
    assert unlocks.trip_unlocked(
        rules, view({"line_gamaa.01": 2}, {("vehicle", "micro_old")}), "line_gamaa.02"
    )
    # Its own vehicle: a line unlocked another way doesn't lend it.
    changed = copy.deepcopy(rules)
    changed["lines"]["line_gamaa"]["unlock"] = {"kind": "start"}
    assert not unlocks.trip_unlocked(changed, view(), "line_gamaa.01")


def test_a_story_trip_needs_only_its_chapter(rules: dict[str, Any]) -> None:
    # ch1 is the first chapter, so line_hay.03 is open before line_hay.02 is played.
    assert unlocks.trip_unlocked(rules, view(), "line_hay.03")
    changed = copy.deepcopy(rules)
    changed["chapters"]["ch2_her_father"]["story_trip_id"] = "line_hay.03"
    changed["chapters"]["ch1_first_job"]["story_trip_id"] = ""
    assert not unlocks.trip_unlocked(changed, view(), "line_hay.03")
    assert unlocks.trip_unlocked(changed, view(HAY_DONE), "line_hay.03")


def test_a_story_trip_no_chapter_names_follows_the_line(rules: dict[str, Any]) -> None:
    changed = copy.deepcopy(rules)
    changed["chapters"]["ch1_first_job"]["story_trip_id"] = ""
    assert unlocks.trip_unlocked(changed, view(), "line_hay.03") is False
    assert unlocks.trip_unlocked(changed, view({"line_hay.02": 1}), "line_hay.03")


def test_an_unknown_trip_is_locked(rules: dict[str, Any]) -> None:
    assert not unlocks.trip_unlocked(rules, view(HAY_DONE), "line_hay.99")


# -- chapters, rooms, items -----------------------------------------------------------------------


def test_the_first_chapter_is_always_unlocked(rules: dict[str, Any]) -> None:
    assert unlocks.chapter_unlocked(rules, view(), "ch1_first_job")
    assert not unlocks.chapter_unlocked(rules, view(), "ch2_her_father")
    assert not unlocks.chapter_unlocked(rules, view(), "ch9_none")


def test_chapters_complete_in_order_for_each_goal_kind(rules: dict[str, Any]) -> None:
    micro = ("vehicle", "micro_old")
    shabka = ("chapter", "ch3_shabka")
    # complete_line
    assert not unlocks.chapter_complete(rules, view(), "ch1_first_job")
    assert unlocks.chapter_complete(rules, view(HAY_DONE), "ch1_first_job")
    assert unlocks.chapter_unlocked(rules, view(HAY_DONE), "ch2_her_father")
    # own_vehicle: met, but ch1 isn't complete, so ch2 isn't either.
    assert not unlocks.chapter_complete(rules, view(owned={micro}), "ch2_her_father")
    assert unlocks.chapter_complete(rules, view(HAY_DONE, {micro}), "ch2_her_father")
    # purchase
    assert not unlocks.chapter_complete(rules, view(HAY_DONE, {micro}), "ch3_shabka")
    assert unlocks.chapter_complete(rules, view(HAY_DONE, {micro, shabka}), "ch3_shabka")
    assert unlocks.chapter_unlocked(rules, view(HAY_DONE, {micro, shabka}), "ch4_salon")
    # complete_room
    all_owned = {micro, shabka, *SALON}
    assert not unlocks.chapter_complete(
        rules, view(HAY_DONE, {micro, shabka, ("item", "salon.nish")}), "ch4_salon"
    )
    assert unlocks.chapter_complete(rules, view(HAY_DONE, all_owned), "ch4_salon")
    assert not unlocks.chapter_complete(rules, view(HAY_DONE, all_owned), "ch9_none")


def test_an_unknown_goal_kind_is_never_met(rules: dict[str, Any]) -> None:
    changed = copy.deepcopy(rules)
    changed["chapters"]["ch1_first_job"]["goal"] = {"kind": "unknown"}
    assert not unlocks.chapter_complete(changed, view(HAY_DONE), "ch1_first_job")


def test_a_room_is_complete_when_every_item_is_owned(rules: dict[str, Any]) -> None:
    assert not unlocks.room_complete(rules, view(), "salon")
    assert not unlocks.room_complete(rules, view(owned={("item", "salon.nish")}), "salon")
    assert unlocks.room_complete(rules, view(owned=SALON), "salon")
    assert not unlocks.room_complete(rules, view(owned=SALON), "kitchen")
    changed = copy.deepcopy(rules)
    changed["rooms"]["salon"]["items"] = []
    assert not unlocks.room_complete(changed, view(owned=SALON), "salon")


def test_an_item_is_purchasable_when_its_rooms_chapter_is_unlocked(rules: dict[str, Any]) -> None:
    assert not unlocks.item_purchasable(rules, view(), "salon.nish")
    ready = view(HAY_DONE, {("vehicle", "micro_old"), ("chapter", "ch3_shabka")})
    assert unlocks.item_purchasable(rules, ready, "salon.nish")
    assert not unlocks.item_purchasable(rules, ready, "kitchen.oven")
    changed = copy.deepcopy(rules)
    changed["items"]["salon.nish"]["room_id"] = "kitchen"
    assert not unlocks.item_purchasable(changed, ready, "salon.nish")


def test_newly_completed_lists_rooms_before_chapters_and_skips_granted(
    rules: dict[str, Any],
) -> None:
    everything = view(HAY_DONE, {("vehicle", "micro_old"), ("chapter", "ch3_shabka"), *SALON})
    assert unlocks.newly_completed(rules, everything, frozenset()) == [
        Completion("room", "salon", 20),
        Completion("chapter", "ch1_first_job", 5),
        Completion("chapter", "ch2_her_father", 10),
        Completion("chapter", "ch3_shabka", 10),
        Completion("chapter", "ch4_salon", 15),
    ]
    granted = frozenset({("room", "salon"), ("chapter", "ch1_first_job")})
    assert [c.id for c in unlocks.newly_completed(rules, everything, granted)] == [
        "ch2_her_father",
        "ch3_shabka",
        "ch4_salon",
    ]
    assert unlocks.newly_completed(rules, view(), frozenset()) == []


def test_the_current_chapter_is_the_open_one_else_the_last_done(rules: dict[str, Any]) -> None:
    assert unlocks.current_chapter(rules, view()) == "ch1_first_job"
    assert unlocks.current_chapter(rules, view(HAY_DONE)) == "ch2_her_father"
    micro = ("vehicle", "micro_old")
    assert unlocks.current_chapter(rules, view(HAY_DONE, {micro})) == "ch3_shabka"
    done = view(HAY_DONE, {micro, ("chapter", "ch3_shabka"), *SALON})
    assert unlocks.current_chapter(rules, done) == "ch4_salon"
    assert unlocks.current_chapter({**rules, "chapters": {}}, done) is None
