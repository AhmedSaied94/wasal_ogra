"""The authoring pages (tasks.md T058, contracts/admin.md "Authoring pages")."""

from __future__ import annotations

import re
from typing import Any

import pytest
from django.test import Client
from pytest_django import Settings

from apps.accounts.models import User
from apps.accounts.tests.test_admin_csp import (
    InlineScripts,
    admin_csp,
    csp_hash,
    script_sources,
)
from apps.content.models import (
    Chapter,
    FamilyRequest,
    Item,
    Line,
    Room,
    Seat,
    StoryRider,
    Trip,
    Vehicle,
)
from apps.content.tests import factories as make
from apps.content.tests.conftest import admin_client

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

TRIP_ADD = "/admin/content/trip/add/"


@pytest.fixture
def author_client(author: User) -> Client:
    return admin_client(author)


@pytest.fixture
def world() -> dict[str, Any]:
    """A line with three stations, a microbus and a tuktuk, each with seats."""
    hay = make.line()
    stations = [make.station(hay, sid, order) for order, sid in enumerate(("a1", "b2", "c3"), 1)]
    micro = make.vehicle()
    tuktuk = make.vehicle("tuktuk", order=2, starter=True)
    return {
        "line": hay,
        "stations": stations,
        "micro": micro,
        "micro_seat": make.seat(micro, "A_l"),
        "tuktuk_seat": make.seat(tuktuk, "A_r"),
        "other_station": make.station(make.line("line_gamaa", order=2), "zz"),
    }


def management(prefix: str, total: int, initial: int = 0) -> dict[str, str]:
    return {
        f"{prefix}-TOTAL_FORMS": str(total),
        f"{prefix}-INITIAL_FORMS": str(initial),
        f"{prefix}-MIN_NUM_FORMS": "0",
        f"{prefix}-MAX_NUM_FORMS": "1000",
    }


def trip_post(
    world: dict[str, Any], *, fare: int = 450, dest: Any = None, seat: Any = None
) -> dict[str, str]:
    first, second, _ = world["stations"]
    tray = {f"tray_{d}": "0" for d in (50, 100, 500, 1000, 2000, 5000, 10000, 20000)}
    return {
        "line": str(world["line"].pk),
        "number": "1",
        "vehicle": str(world["micro"].pk),
        "kind": "regular",
        "seed": "12345",
        "max_earnings_jenehat": "60",
        "star_two": "no_fights",
        "star_three": "no_fights_no_mistakes",
        "student_discount_pct": "0",
        "bag_fare_piasters": "0",
        "child_free_age": "6",
        "max_break_requests": "2",
        "author_notes": "",
        **tray,
        **management("trip_stations", 2),
        "trip_stations-0-station": str(first.pk),
        "trip_stations-0-at_seconds": "30",
        "trip_stations-0-fare_piasters": str(fare),
        "trip_stations-1-station": str(second.pk),
        "trip_stations-1-at_seconds": "60",
        "trip_stations-1-fare_piasters": "700",
        **management("passengers", 1),
        "passengers-0-order": "1",
        "passengers-0-passenger_id": "p1",
        "passengers-0-archetype": "regular",
        "passengers-0-skin": "student_cap",
        "passengers-0-seat": str((seat or world["micro_seat"]).pk),
        "passengers-0-board_station": "",
        "passengers-0-dest_station": str((dest or second).pk),
        "passengers-0-pays_at_seconds": "",
        "passengers-0-payment": "1000",
        "passengers-0-group_id": "",
        "passengers-0-group_size": "",
        "passengers-0-speech_keys": "",
        **management("events", 0),
    }


def inline_errors(response: Any, prefix: str) -> list[dict[str, Any]]:
    for inline in response.context["inline_admin_formsets"]:
        if inline.formset.prefix == prefix:
            return [form.errors for form in inline.formset.forms]
    raise AssertionError(prefix)


# -- saving: errors on their field, nothing saved (US2-1) -----------------------------------------


def test_a_valid_trip_saves(author_client: Client, world: dict[str, Any]) -> None:
    response = author_client.post(TRIP_ADD, trip_post(world))

    assert response.status_code == 302, response.context and response.context["errors"]
    trip = Trip.objects.get()
    assert trip.trip_id == "line_hay.01"
    assert trip.trip_stations.count() == 2
    assert trip.passengers.get().dest_station == world["stations"][1]


@pytest.mark.parametrize("required", [True, False])
def test_the_rules_show_and_save_no_fights_required(
    author_client: Client, world: dict[str, Any], required: bool
) -> None:
    page = author_client.get(TRIP_ADD)
    assert "no_fights_required" in dict(page.context["adminform"].fieldsets)["Rules"]["fields"]
    assert 'name="no_fights_required"' in page.content.decode()
    checkbox = {"no_fights_required": "on"} if required else {}

    response = author_client.post(TRIP_ADD, {**trip_post(world), **checkbox})

    assert response.status_code == 302, response.context and response.context["errors"]
    assert Trip.objects.get().no_fights_required is required


def test_a_fare_of_475_is_an_error_on_its_field(
    author_client: Client, world: dict[str, Any]
) -> None:
    response = author_client.post(TRIP_ADD, trip_post(world, fare=475))

    assert response.status_code == 200
    assert "fare_piasters" in inline_errors(response, "trip_stations")[0]
    assert not Trip.objects.exists()


def test_a_destination_off_the_trip_is_an_error_on_its_field(
    author_client: Client, world: dict[str, Any]
) -> None:
    response = author_client.post(TRIP_ADD, trip_post(world, dest=world["stations"][2]))

    assert response.status_code == 200
    assert inline_errors(response, "passengers")[0]["dest_station"] == [
        "Choose one of the trip's stations."
    ]
    assert not Trip.objects.exists()


def test_a_seat_of_another_vehicle_is_an_error_on_its_field(
    author_client: Client, world: dict[str, Any]
) -> None:
    response = author_client.post(TRIP_ADD, trip_post(world, seat=world["tuktuk_seat"]))

    assert response.status_code == 200
    assert inline_errors(response, "passengers")[0]["seat"] == [
        "Choose a seat of the trip's vehicle."
    ]
    assert not Trip.objects.exists()


def test_stations_follow_the_line(author_client: Client, world: dict[str, Any]) -> None:
    data = trip_post(world)
    data["trip_stations-1-at_seconds"] = "20"  # before the first station

    response = author_client.post(TRIP_ADD, data)

    assert "at_seconds" in inline_errors(response, "trip_stations")[1]
    assert not Trip.objects.exists()


def test_a_station_of_another_line_is_refused(author_client: Client, world: dict[str, Any]) -> None:
    data = trip_post(world)
    data["trip_stations-1-station"] = str(world["other_station"].pk)

    response = author_client.post(TRIP_ADD, data)

    assert inline_errors(response, "trip_stations")[1]["station"] == [
        "Choose a station on the trip's line."
    ]


def test_unlock_fields_follow_the_kind(author_client: Client, world: dict[str, Any]) -> None:
    response = author_client.post(
        "/admin/content/line/add/",
        {
            "line_id": "line_souq",
            "name_ar_eg": "name",
            "name_ar": "",
            "whats_new_ar_eg": "news",
            "whats_new_ar": "",
            "display_fare_piasters": "700",
            "order": "5",
            "unlock_kind": "vehicle",
            "unlock_vehicle": "",
            "unlock_after_line": "",
            "difficulty_min": "0",
            "difficulty_max": "10",
            **management("stations", 0),
        },
    )

    assert response.context["adminform"].form.errors["unlock_vehicle"] == [
        "Choose the vehicle that unlocks this line."
    ]
    assert not Line.objects.filter(line_id="line_souq").exists()


# -- right to left (US2-2) ------------------------------------------------------------------------


def test_arabic_fields_run_right_to_left(author_client: Client, world: dict[str, Any]) -> None:
    html = author_client.get(f"/admin/content/line/{world['line'].pk}/change/").content.decode()

    names = ("name_ar_eg", "name_ar", "whats_new_ar_eg", "whats_new_ar", "stations-0-name_ar_eg")
    for name in (*names, "stations-0-name_ar"):
        tag = re.search(rf'<input[^>]*name="{name}"[^>]*>', html)
        assert tag, name
        assert 'dir="rtl"' in tag[0]
        assert 'lang="ar"' in tag[0]


# -- read-only access (US2-6) ---------------------------------------------------------------------


def test_staff_without_the_author_role_read_only(plain_staff: User, world: dict[str, Any]) -> None:
    client = admin_client(plain_staff)
    page = f"/admin/content/line/{world['line'].pk}/change/"

    response = client.get(page)

    assert response.status_code == 200
    assert 'name="_save"' not in response.content.decode()
    assert client.post(page, {"line_id": "line_gamaa"}).status_code == 403
    assert client.get("/admin/content/line/add/").status_code == 403


def test_everyone_reads_only_on_the_target(
    author_client: Client, world: dict[str, Any], settings: Settings
) -> None:
    settings.CONTENT_ROLE = "target"
    page = f"/admin/content/line/{world['line'].pk}/change/"

    assert 'name="_save"' not in author_client.get(page).content.decode()
    assert author_client.get("/admin/content/line/add/").status_code == 403
    assert author_client.get(f"/admin/content/line/{world['line'].pk}/delete/").status_code == 403


# -- permanence (FR-016) --------------------------------------------------------------------------


def test_a_published_identifier_field_is_read_only(
    author_client: Client, world: dict[str, Any]
) -> None:
    make.published("line", "line_hay", version=4)
    page = f"/admin/content/line/{world['line'].pk}/change/"

    form = author_client.get(page).context["adminform"].form

    assert form.fields["line_id"].disabled
    assert "version 4" in form.fields["line_id"].help_text


def test_a_refused_delete_names_the_version(author_client: Client, world: dict[str, Any]) -> None:
    make.published("station", "line_hay/b2", version=4)
    page = f"/admin/content/line/{world['line'].pk}/delete/"

    shown = author_client.get(page).content.decode()
    response = author_client.post(page, {"post": "yes"})

    assert "station line_hay/b2 is in published pack version 4" in shown
    assert response.status_code == 200
    assert Line.objects.filter(pk=world["line"].pk).exists()


def test_a_refused_inline_delete_names_the_version(
    author_client: Client, world: dict[str, Any]
) -> None:
    micro = world["micro"]
    make.published("seat", "micro_old/A_l", version=2)
    data = {
        "vehicle_id": "micro_old",
        "name_ar_eg": "name",
        "name_ar": "",
        "short_name_ar_eg": "short",
        "short_name_ar": "",
        "starter": "",
        "order": "1",
        **management("seats", 1, initial=1),
        "seats-0-id": str(world["micro_seat"].pk),
        "seats-0-vehicle": str(micro.pk),
        "seats-0-seat_id": "A_l",
        "seats-0-DELETE": "on",
    }

    response = author_client.post(f"/admin/content/vehicle/{micro.pk}/change/", data)

    assert response.status_code == 200
    assert "seat micro_old/A_l is in published pack version 2" in response.content.decode()
    assert Seat.objects.filter(vehicle=micro).count() == 1


def test_an_unpublished_row_can_be_deleted(author_client: Client) -> None:
    unused = make.vehicle("micro_new", order=5)

    response = author_client.post(f"/admin/content/vehicle/{unused.pk}/delete/", {"post": "yes"})

    assert response.status_code == 302
    assert not Vehicle.objects.filter(pk=unused.pk).exists()


# -- the admin CSP (FR-019 of B01) ----------------------------------------------------------------


def test_the_content_pages_add_no_inline_script(
    author_client: Client, sample_imported: User
) -> None:
    allowed = {s for s in script_sources(admin_csp("Caddyfile")) if s.startswith("'sha256-")}
    trip = Trip.objects.get(line__line_id="line_gamaa", number=2)
    pages = [
        "/admin/content/",
        *(f"/admin/content/{m}/" for m in MODELS),
        *(f"/admin/content/{m}/add/" for m in MODELS if m not in READ_ONLY),
        f"/admin/content/trip/{trip.pk}/change/",
        f"/admin/content/line/{trip.line.pk}/change/",
        "/admin/content/contentpack/import/",
    ]
    for page in pages:
        response = author_client.get(page)
        assert response.status_code == 200, page
        parser = InlineScripts()
        parser.feed(response.content.decode())
        assert parser.handlers == [], page
        assert {csp_hash(script) for script in parser.scripts} <= allowed, page


MODELS = (
    "line",
    "vehicle",
    "trip",
    "chapter",
    "scene",
    "room",
    "item",
    "familyrequest",
    "speechpool",
    "speechline",
    "catalogprice",
    "dailyrewardday",
    "tasktemplate",
    "contentpack",
    "contentauditrecord",
)
READ_ONLY = ("contentpack", "contentauditrecord")


def test_trips_are_found_by_trip_id(author_client: Client, sample_imported: User) -> None:
    response = author_client.get("/admin/content/trip/", {"q": "line_gamaa.02"})

    assert [str(trip) for trip in response.context["cl"].result_list] == ["line_gamaa.02"]


def test_the_review_columns_are_read_only(author_client: Client, sample_imported: User) -> None:
    line = author_client.get("/admin/content/speechline/").context["cl"].result_list[0]
    page = f"/admin/content/speechline/{line.pk}/change/"

    form = author_client.get(page).context["adminform"].form

    assert "reviewed_by" not in form.fields
    assert "reviewed_at" not in form.fields


# -- M10's story fields (specs/015-m10-apartment-story, contracts/content-fields.md "B04") ---------


def story_chapter_post(world: dict[str, Any]) -> dict[str, str]:
    story = Trip.objects.create(
        line=world["line"],
        number=3,
        vehicle=world["micro"],
        kind="story",
        seed=12345,
        max_earnings_jenehat=60,
        star_two="no_fights",
        star_three="no_fights_no_mistakes",
        student_discount_pct=0,
        bag_fare_piasters=0,
        child_free_age=6,
        max_break_requests=2,
        no_fights_required=True,
    )
    return {
        "chapter_id": "ch5_kitchen",
        "order": "5",
        "title_ar_eg": "المطبخ",
        "title_ar": "",
        "goal_kind": "purchase",
        "story_trip": str(story.pk),
        "completion_bonat": "5",
        "goal_art": "goal_shabka",
        "goal_line_speaker": "moallem",
        "goal_line_ar_eg": "لمّ قرشين",
        "goal_line_ar": "",
        "ready_line_ar_eg": "جاهزة",
        "ready_line_ar": "",
        "tagline_ar_eg": "شقة العمر",
        "tagline_ar": "",
        "story_title_ar_eg": "مشوار المعلم",
        "story_title_ar": "",
        "story_condition_ar_eg": "خليك هادي",
        "story_condition_ar": "",
        "story_fail_reason_ar_eg": "زعل ونزل",
        "story_fail_reason_ar": "",
        **management("scenes", 0),
        **management("riders", 2),
        "riders-0-order": "1",
        "riders-0-character": "moallem",
        "riders-0-seat_id": "A_l",
        "riders-0-comment_short_change": "story.moallem.short_change",
        "riders-0-comment_false_accusation": "",
        "riders-0-comment_fight": "story.moallem.fight",
        "riders-0-comment_missed_stop": "",
        "riders-0-comment_impatient": "",
        "riders-1-order": "2",
        "riders-1-character": "salma",
        "riders-1-seat_id": "A_m",
        **{
            f"riders-1-comment_{slot}": ""
            for slot in (
                "short_change",
                "false_accusation",
                "fight",
                "missed_stop",
                "impatient",
            )
        },
    }


def test_a_chapter_saves_every_story_field_and_its_riders(
    author_client: Client, world: dict[str, Any]
) -> None:
    response = author_client.post("/admin/content/chapter/add/", story_chapter_post(world))

    assert response.status_code == 302, response.context and response.context["errors"]
    [chapter] = Chapter.objects.filter(chapter_id="ch5_kitchen")
    assert chapter.goal_art == "goal_shabka"
    assert (chapter.goal_line_speaker, chapter.goal_line_ar_eg) == ("moallem", "لمّ قرشين")
    assert chapter.ready_line_ar_eg == "جاهزة"
    assert chapter.tagline_ar_eg == "شقة العمر"
    assert chapter.story_title_ar_eg == "مشوار المعلم"
    assert chapter.story_condition_ar_eg == "خليك هادي"
    assert chapter.story_fail_reason_ar_eg == "زعل ونزل"
    assert [
        (
            rider.order,
            rider.character,
            rider.seat_id,
            rider.comment_short_change,
            rider.comment_fight,
        )
        for rider in chapter.riders.order_by("order")
    ] == [
        (1, "moallem", "A_l", "story.moallem.short_change", "story.moallem.fight"),
        (2, "salma", "A_m", "", ""),
    ]


def test_the_rider_inline_allows_two(author_client: Client, world: dict[str, Any]) -> None:
    formset = author_client.get("/admin/content/chapter/add/").context["inline_admin_formsets"]
    riders = next(f for f in formset if f.formset.model is StoryRider)
    assert riders.formset.max_num == 2


def test_the_room_item_and_request_save_their_new_fields(
    author_client: Client, sample_imported: User
) -> None:
    chapter = Chapter.objects.get(chapter_id="ch4_salon")
    room = author_client.post(
        "/admin/content/room/add/",
        {
            "room_id": "kitchen",
            "name_ar_eg": "المطبخ",
            "name_ar": "",
            "chapter": str(chapter.pk),
            "order": "2",
            "completion_bonat": "20",
            "art": "kitchen_01",
            "done_line_ar_eg": "المطبخ خلص",
            "done_line_ar": "",
        },
    )
    assert room.status_code == 302, room.context and room.context["errors"]
    stored_room = Room.objects.get(room_id="kitchen")
    assert (stored_room.art, stored_room.done_line_ar_eg) == ("kitchen_01", "المطبخ خلص")

    item = author_client.post(
        "/admin/content/item/add/",
        {
            "room": str(stored_room.pk),
            "slug": "table",
            "name_ar_eg": "الترابيزة",
            "name_ar": "",
            "order": "1",
            "slot_x": "40",
            "slot_y": "120",
            "slot_w": "160",
            "slot_h": "100",
            "comment_ar_eg": "الترابيزة بتلم العيلة",
            "comment_ar": "",
            **management("variants", 1),
            "variants-0-variant_id": "wood",
            "variants-0-name_ar_eg": "خشب",
            "variants-0-name_ar": "",
            "variants-0-art": "table_wood",
            "variants-0-order": "1",
            "variants-0-comment_ar_eg": "الخشب دافي",
            "variants-0-comment_ar": "",
        },
    )
    assert item.status_code == 302, item.context and item.context["errors"]
    stored_item = Item.objects.get(room=stored_room, slug="table")
    assert (stored_item.slot_x, stored_item.slot_y, stored_item.slot_w, stored_item.slot_h) == (
        40,
        120,
        160,
        100,
    )
    assert stored_item.comment_ar_eg == "الترابيزة بتلم العيلة"
    assert stored_item.variants.get(variant_id="wood").comment_ar_eg == "الخشب دافي"

    request = author_client.post(
        "/admin/content/familyrequest/add/",
        {
            "request_id": "req_table_wood",
            "room": str(stored_room.pk),
            "item": str(stored_item.pk),
            "character": "bride_father",
            "text_ar_eg": "أبو العروسة عايز ترابيزة خشب",
            "text_ar": "",
            "reward_bonat": "6",
        },
    )
    assert request.status_code == 302, request.context and request.context["errors"]
    assert FamilyRequest.objects.get(request_id="req_table_wood").character == "bride_father"
