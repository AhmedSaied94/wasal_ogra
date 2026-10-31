"""The story's content fields (specs/015-m10-apartment-story, T010).

Every new invalid example is refused with the kit's own code and path. The riders and the new
fields survive a round trip, and the riders' order and seat are unique per chapter.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction

from apps.accounts.models import User
from apps.content.models import Chapter, FamilyRequest, Item, Room, Scene, StoryRider
from apps.content.models.packs import Status
from apps.content.services import exporter, importer
from apps.content.services.snapshot import chapter_part
from apps.content.tests.conftest import SAMPLE
from apps.content.tests.test_build import built
from apps.content.tests.test_import_export import (
    codes,
    edited,
    sample_files,
    unzipped,
    zipped,
)

pytestmark = pytest.mark.django_db

EXAMPLES = SAMPLE.parent
# The new refusals of T007, by the part whose sample file they replace.
NEW_REFUSALS = {
    "chapter": (
        "scene_no_title.json",
        "story_info_without_trip.json",
        "rider_seat_taken.json",
        "rider_comment_no_pool.json",
        "two_goal_scenes.json",
        "duplicate_scene_id.json",
        "three_speakers.json",
    ),
    "item": ("no_slot.json", "slot_w_10.json", "slot_overflows.json"),
    "family_request": ("no_character.json", "unknown_character.json"),
}
EXPECTED: dict[str, Any] = json.loads(
    (EXAMPLES / "invalid" / "expected.json").read_text(encoding="utf-8")
)


def sample_file_for(part: str, document: dict[str, Any]) -> str:
    """The sample file whose identifier the refused document replaces."""
    folder = {"chapter": "chapters", "item": "items", "family_request": "family_requests"}[part]
    for path in sorted((SAMPLE / folder).glob("*.json")):
        stored = json.loads(path.read_text(encoding="utf-8"))
        if stored.get(f"{part}_id") == document.get(f"{part}_id"):
            return f"{folder}/{path.name}"
    raise AssertionError(f"no sample {part} named {document.get(f'{part}_id')}")


@pytest.mark.parametrize(
    ("part", "name"),
    [(part, name) for part, names in NEW_REFUSALS.items() for name in names],
)
def test_each_new_invalid_example_is_refused(author: User, part: str, name: str) -> None:
    document = json.loads((EXAMPLES / "invalid" / part / name).read_text(encoding="utf-8"))
    target = sample_file_for(part, document)
    files = {
        **sample_files(),
        target: (json.dumps(document, ensure_ascii=False) + "\n").encode(),
    }

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(zipped(files), author)

    expected = EXPECTED[f"{part}/{name}"]
    if isinstance(expected, str):
        code, path = "V-SC", expected
    else:
        code, path = expected["code"], expected["path"]
    assert [(f.file, f.code, f.path) for f in refused.value.findings] == [(target, code, path)]
    assert not Chapter.objects.exists()
    assert not Item.objects.exists()


def test_the_riders_and_the_new_fields_round_trip(author: User) -> None:
    result = importer.import_zip(zipped(sample_files()), author)
    exported = unzipped(exporter.export_current(author))

    list_name = "chapters/ch1_first_job.json"
    assert exported[list_name] == sample_files()[list_name]
    chapter = Chapter.objects.get(chapter_id="ch1_first_job")
    info = json.loads(sample_files()[list_name])["story_trip_info"]
    assert chapter.story_title_ar_eg == info["title"]["ar-EG"]
    assert chapter.story_condition_ar_eg == info["condition"]["ar-EG"]
    assert chapter.story_fail_reason_ar_eg == info["fail_reason"]["ar-EG"]
    [rider] = list(StoryRider.objects.filter(chapter=chapter))
    assert (rider.order, rider.character, rider.seat_id) == (1, "moallem", "A_l")
    assert rider.comment_short_change == "story.moallem.short_change"
    assert rider.comment_fight == "story.moallem.fight"
    assert rider.comment_impatient == ""

    # The goal card's line, the scene titles, the room's art and the item's slot.
    assert chapter.goal_art == "goal_shabka"
    assert chapter.goal_line_speaker == "moallem"
    assert Scene.objects.get(chapter=chapter, scene_id="opening").title_ar_eg != ""
    room = Room.objects.get(room_id="salon")
    assert room.art == "salon"
    assert room.done_line_ar_eg != ""
    nish = Item.objects.get(room=room, slug="nish")
    assert (nish.slot_x, nish.slot_y, nish.slot_w, nish.slot_h) == (89, 40, 180, 150)
    assert nish.variants.get(variant_id="crystal").comment_ar_eg != ""
    assert FamilyRequest.objects.get(request_id="req_nish_crystal").character == "bride_mother"
    # The sample's original entities, plus M10's two speech pools.
    assert len(result.added) == 63


def test_a_riders_order_and_seat_are_unique(author: User) -> None:
    importer.import_zip(zipped(sample_files()), author)
    chapter = Chapter.objects.get(chapter_id="ch1_first_job")
    [rider] = StoryRider.objects.filter(chapter=chapter)

    with pytest.raises(IntegrityError), transaction.atomic():
        StoryRider.objects.create(
            chapter=chapter, order=rider.order, character="salma", seat_id="A_m"
        )
    with pytest.raises(IntegrityError), transaction.atomic():
        StoryRider.objects.create(
            chapter=chapter, order=2, character="salma", seat_id=rider.seat_id
        )


def test_the_chapter_refuses_a_line_without_a_speaker(author: User) -> None:
    importer.import_zip(zipped(sample_files()), author)
    chapter = Chapter.objects.get(chapter_id="ch1_first_job")
    chapter.goal_line_speaker = ""
    with pytest.raises(ValidationError, match="speaker"):
        chapter.full_clean()


def test_the_item_refuses_a_slot_past_the_room(author: User) -> None:
    importer.import_zip(zipped(sample_files()), author)
    item = Item.objects.get(room__room_id="salon", slug="nish")
    item.slot_x = 300
    with pytest.raises(ValidationError, match="x \\+ w"):
        item.full_clean()


def test_the_story_fields_need_a_story_trip(sample_imported: User) -> None:
    chapter = Chapter.objects.get(chapter_id="ch1_first_job")
    chapter.story_trip = None
    with pytest.raises(ValidationError, match="story trip"):
        chapter.full_clean()


def test_a_story_trip_needs_its_title_for_its_fields(sample_imported: User) -> None:
    # FR-056: the title presents the trip, so a condition, a fail reason or a rider without one
    # is a chapter nobody may save (R1-6).
    chapter = Chapter.objects.get(chapter_id="ch1_first_job")
    chapter.story_title_ar_eg = ""
    with pytest.raises(ValidationError, match="title"):
        chapter.full_clean()

    # With no condition and no fail reason left, the rider alone still needs the title.
    chapter.story_condition_ar_eg = ""
    chapter.story_fail_reason_ar_eg = ""
    assert chapter.riders.exists()
    with pytest.raises(ValidationError, match="title"):
        chapter.full_clean()


def test_the_built_pack_keeps_a_story_trip_whose_title_is_missing(
    sample_reviewed: User,
) -> None:
    # A chapter saved before the rule existed, or through the riders' inline: the snapshot emits
    # the shape it holds so the schema refuses it, never dropping the riders (R1-6).
    Chapter.objects.filter(chapter_id="ch1_first_job").update(story_title_ar_eg="")
    part = chapter_part(Chapter.objects.get(chapter_id="ch1_first_job"))
    assert part["story_trip_info"]["title"] == {"ar-EG": ""}
    assert part["story_trip_info"]["riders"]
    assert part["story_trip_info"]["condition"]["ar-EG"]

    pack = built(sample_reviewed)

    assert pack.status == Status.DRAFT
    [refused] = [f for f in pack.validation_report["findings"] if f["code"] == "V-SC"]
    assert refused["entity"] == "chapter"
    assert refused["id"] == "ch1_first_job"
    assert refused["path"] == "$.story_trip_info.title.ar-EG"


def test_a_refused_pack_names_only_the_kit_s_code(author: User) -> None:
    files = edited(
        sample_files(),
        "chapters/ch1_first_job.json",
        lambda c: c["scenes"][0].pop("title"),
    )
    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(zipped(files), author)
    assert codes(refused.value) == ["V-SC"]
    assert refused.value.findings[0].path == "$.scenes[0].title"


def test_the_sample_has_no_riders_on_a_chapter_without_a_story(sample_imported: User) -> None:
    for chapter in Chapter.objects.all():
        if chapter.story_trip_id is None:
            assert not chapter.riders.exists(), chapter.chapter_id
    assert Path(SAMPLE).is_dir()
