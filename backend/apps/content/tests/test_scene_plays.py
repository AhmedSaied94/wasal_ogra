"""A scene's `plays` in B04 (specs/012-m07-onboarding T011, contracts/scenes.md "Backend B04").

The sample's chapter 1 opens with the `opening` scene and plays `the_stand` after `line_hay.03`.
Every invalid `plays` and `narrator` case of the example set is refused at import with its rule's
code, and the database refuses a trip on a scene that isn't `after_trip`, and the reverse.
"""

from __future__ import annotations

import json
from typing import Any

import pytest
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.test import Client

from apps.accounts.models import User
from apps.content.models import Chapter, Scene, Trip
from apps.content.services import exporter, importer
from apps.content.tests.conftest import SAMPLE, admin_client
from apps.content.tests.test_import_export import edited, sample_files, unzipped, zipped

pytestmark = pytest.mark.django_db

INVALID = SAMPLE.parent / "invalid"
EXPECTED: dict[str, Any] = json.loads((INVALID / "expected.json").read_text())
# The cases a rule beyond shape refuses: V-C3 to V-C5 (contracts/scenes.md "Validator rules").
RULE_CASES = sorted(
    name
    for name, entry in EXPECTED.items()
    if name.startswith("chapter/") and isinstance(entry, dict)
)
CH1 = "chapters/ch1_first_job.json"


def scenes(chapter_id: str = "ch1_first_job") -> list[Scene]:
    return list(
        Scene.objects.filter(chapter__chapter_id=chapter_id)
        .select_related("plays_trip__line")
        .order_by("order")
    )


def test_the_rule_cases_are_the_plays_narrator_and_story_rules() -> None:
    assert {EXPECTED[name]["code"] for name in RULE_CASES} == {
        "V-C3",
        "V-C4",
        "V-C5",
        "V-C6",
        "V-C7",
        "V-C8",
        "V-C10",
        "V-C11",
        "V-C12",
    }
    assert len(RULE_CASES) == 14


# -- import and export ----------------------------------------------------------------------------


def test_the_sample_stores_each_scenes_plays(sample_imported: User) -> None:
    opening, stand = scenes()

    assert (opening.scene_id, opening.plays_kind, opening.plays_trip) == (
        "opening",
        "opening",
        None,
    )
    assert stand.plays_trip is not None
    assert (stand.scene_id, stand.plays_kind, stand.plays_trip.trip_id) == (
        "the_stand",
        "after_trip",
        "line_hay.03",
    )
    caption = opening.lines.get(panel=1, order=1)
    assert caption.speaker == "narrator"


def test_the_export_writes_plays_and_the_narrator_line(sample_imported: User) -> None:
    exported = unzipped(exporter.export_current(sample_imported))[CH1]

    assert exported == (SAMPLE / CH1).read_bytes()
    chapter = json.loads(exported)
    assert [scene.get("plays") for scene in chapter["scenes"]] == [
        {"kind": "opening"},
        {"kind": "after_trip", "trip_id": "line_hay.03"},
    ]
    assert chapter["scenes"][0]["panels"][0]["lines"][0]["speaker"] == "narrator"


def test_a_changed_plays_changes_the_chapter(sample_imported: User) -> None:
    files = edited(sample_files(), CH1, lambda chapter: chapter["scenes"][1].pop("plays"))

    result = importer.import_zip(zipped(files), sample_imported)

    assert result.changed == ["chapter ch1_first_job"]
    stand = scenes()[1]
    assert (stand.plays_kind, stand.plays_trip) == ("", None)

    result = importer.import_dir(SAMPLE, sample_imported)

    assert result.changed == ["chapter ch1_first_job"]
    stand = scenes()[1]
    assert stand.plays_trip is not None
    assert (stand.plays_kind, stand.plays_trip.trip_id) == ("after_trip", "line_hay.03")


def test_an_after_trip_scene_can_move_to_another_trip(sample_imported: User) -> None:
    files = edited(
        sample_files(),
        CH1,
        lambda chapter: chapter["scenes"][1]["plays"].update(trip_id="line_hay.02"),
    )

    importer.import_zip(zipped(files), sample_imported)

    stand = scenes()[1]
    assert stand.plays_trip is not None
    assert stand.plays_trip.trip_id == "line_hay.02"


@pytest.mark.parametrize("name", RULE_CASES)
def test_each_invalid_case_is_refused_at_import_with_its_code(author: User, name: str) -> None:
    document = (INVALID / name).read_bytes()
    target = f"chapters/{json.loads(document)['chapter_id']}.json"
    expected = EXPECTED[name]

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(zipped({**sample_files(), target: document}), author)

    found = {(f.file, f.code, f.path) for f in refused.value.findings}
    assert (target, expected["code"], expected["path"]) in found, sorted(found)
    assert {f.code for f in refused.value.findings} == {expected["code"]}
    assert not Chapter.objects.exists()


# -- the model ------------------------------------------------------------------------------------


def test_the_database_refuses_a_trip_without_after_trip(sample_imported: User) -> None:
    opening, stand = scenes()
    trip = Trip.objects.get(line__line_id="line_hay", number=1)

    with pytest.raises(IntegrityError, match="content_scene_plays_trip"), transaction.atomic():
        Scene.objects.filter(pk=opening.pk).update(plays_trip=trip)
    with pytest.raises(IntegrityError, match="content_scene_plays_trip"), transaction.atomic():
        Scene.objects.filter(pk=stand.pk).update(plays_kind="")


def test_the_database_refuses_after_trip_without_a_trip(sample_imported: User) -> None:
    opening, stand = scenes()

    with pytest.raises(IntegrityError, match="content_scene_plays_trip"), transaction.atomic():
        Scene.objects.filter(pk=opening.pk).update(plays_kind="after_trip")
    with pytest.raises(IntegrityError, match="content_scene_plays_trip"), transaction.atomic():
        Scene.objects.filter(pk=stand.pk).update(plays_trip=None)


def test_clean_names_the_field_at_fault(sample_imported: User) -> None:
    opening, stand = scenes()

    stand.plays_trip = None
    with pytest.raises(ValidationError) as caught:
        stand.clean()
    assert set(caught.value.message_dict) == {"plays_trip"}

    opening.plays_trip = Trip.objects.get(line__line_id="line_hay", number=1)
    with pytest.raises(ValidationError) as caught:
        opening.clean()
    assert set(caught.value.message_dict) == {"plays_trip"}


# -- the admin ------------------------------------------------------------------------------------


@pytest.mark.urls("config.urls_admin")
def test_the_scene_inline_shows_plays_kind_and_plays_trip(sample_imported: User) -> None:
    client: Client = admin_client(sample_imported)
    chapter = Chapter.objects.get(chapter_id="ch1_first_job")
    stand_trip = Trip.objects.get(line__line_id="line_hay", number=3)

    response = client.get(f"/admin/content/chapter/{chapter.pk}/change/")

    assert response.status_code == 200
    [inline] = [
        inline
        for inline in response.context["inline_admin_formsets"]
        if inline.formset.model is Scene
    ]
    rows = [
        (form.instance.scene_id, form["plays_kind"].value(), form["plays_trip"].value())
        for form in inline.formset.forms
    ]
    assert rows == [("opening", "opening", None), ("the_stand", "after_trip", stand_trip.pk)]
    page = response.content.decode()
    assert 'name="scenes-0-plays_kind"' in page
    assert 'name="scenes-1-plays_trip"' in page
