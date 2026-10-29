"""The rules the content models enforce themselves (tasks.md T042, data-model.md)."""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

import pytest
from django.apps import apps
from django.core.exceptions import ValidationError
from django.db import DatabaseError, IntegrityError, connection, transaction
from django.utils import timezone

from apps.common.checks import check_uuid7_primary_keys
from apps.content.errors import ImmutableError, PermanenceError
from apps.content.models import (
    ContentAuditRecord,
    ContentChannel,
    ContentPack,
    Line,
    Seat,
    SpeechLine,
    Station,
    Trip,
)
from apps.content.models.packs import Status
from apps.content.services import audit, permanence
from apps.content.tests import factories as make

pytestmark = pytest.mark.django_db


@contextmanager
def checked_at_commit() -> Iterator[None]:
    """Run the deferred checks now, as a commit would, inside a savepoint the failure undoes."""
    with transaction.atomic():
        yield
        with connection.cursor() as cursor:
            cursor.execute("SET CONSTRAINTS ALL IMMEDIATE")
            cursor.execute("SET CONSTRAINTS ALL DEFERRED")


# -- permanence (FR-016) --------------------------------------------------------------------------


def test_a_published_identifier_cant_be_renamed() -> None:
    hay = make.line()
    make.published("line", "line_hay", version=4)

    hay.line_id = "line_gamaa"
    with pytest.raises(PermanenceError, match="line line_hay is in published pack version 4"):
        hay.save()

    assert Line.objects.get().line_id == "line_hay"


def test_an_identifier_no_pack_contained_can_be_renamed() -> None:
    hay = make.line()
    make.published("line", "line_gamaa")

    hay.line_id = "line_souq"
    hay.save()

    assert Line.objects.get().line_id == "line_souq"


def test_other_fields_of_a_published_row_still_change() -> None:
    hay = make.line()
    make.published("line", "line_hay")

    hay.name_ar = "other name"
    hay.save()

    assert Line.objects.get().name_ar == "other name"


def test_a_published_row_cant_be_deleted_through_the_instance() -> None:
    hay = make.line()
    make.published("line", "line_hay")

    with pytest.raises(PermanenceError, match="can't be deleted"), transaction.atomic():
        hay.delete()

    assert Line.objects.count() == 1


def test_a_published_row_cant_be_deleted_through_a_queryset() -> None:
    make.line()
    make.line("line_gamaa", order=2)
    make.published("line", "line_hay")

    with pytest.raises(PermanenceError), transaction.atomic():
        Line.objects.all().delete()

    assert Line.objects.count() == 2


def test_a_published_station_cant_be_renamed_or_deleted() -> None:
    kobri = make.station(make.line())
    make.published("station", "line_hay/kobri")

    kobri.station_id = "mahatta"
    with pytest.raises(PermanenceError, match="station line_hay/kobri"):
        kobri.save()
    with pytest.raises(PermanenceError), transaction.atomic():
        Station.objects.filter(pk=kobri.pk).delete()


def test_moving_a_station_to_another_line_renames_it() -> None:
    kobri = make.station(make.line())
    make.published("station", "line_hay/kobri")

    kobri.line = make.line("line_gamaa", order=2)
    with pytest.raises(PermanenceError):
        kobri.save()


def test_a_cascade_stops_at_a_published_nested_row() -> None:
    hay = make.line()
    make.station(hay)
    make.published("station", "line_hay/kobri")

    with pytest.raises(PermanenceError, match="station line_hay/kobri"), transaction.atomic():
        hay.delete()

    assert Station.objects.count() == 1


def test_a_published_seat_stops_its_vehicle_being_deleted() -> None:
    micro = make.vehicle()
    make.seat(micro)
    make.published("seat", "micro_old/A_l")

    with pytest.raises(PermanenceError, match="seat micro_old/A_l"), transaction.atomic():
        micro.delete()

    assert Seat.objects.count() == 1


def test_a_published_variant_is_qualified_by_its_item() -> None:
    crystal = make.variant(make.item(make.room()))
    make.published("variant", "salon.nish/crystal")

    assert crystal.permanent_identifier() == "salon.nish/crystal"
    crystal.variant_id = "wood"
    with pytest.raises(PermanenceError, match=r"variant salon\.nish/crystal"):
        crystal.save()
    with pytest.raises(PermanenceError), transaction.atomic():
        crystal.item.delete()


def test_a_trip_identifier_is_its_line_and_number() -> None:
    first = make.trip(make.line(), make.vehicle(), number=7)
    make.published("trip", "line_hay.07")

    assert first.trip_id == "line_hay.07"
    first.number = 8
    with pytest.raises(PermanenceError, match=r"trip line_hay\.07"):
        first.save()
    assert Trip.objects.get().number == 7


def test_publishing_records_every_identifier_once() -> None:
    pack = {
        "lines": [{"line_id": "line_hay", "stations": [{"station_id": "kobri"}]}],
        "vehicles": [{"vehicle_id": "micro_old", "seats": [{"seat_id": "A_l"}]}],
        "trips": [{"trip_id": "line_hay.01"}],
        "chapters": [{"chapter_id": "ch1_first_job", "scenes": [{"scene_id": "intro"}]}],
        "rooms": [{"room_id": "salon"}],
        "items": [{"item_id": "salon.nish", "variants": [{"variant_id": "crystal"}]}],
        "family_requests": [{"request_id": "req_nish"}],
        "speech_pools": [{"speech_key": "wants.change"}],
        "tasks": [{"task_id": "task_trips"}],
    }

    assert permanence.record_published(pack, 3) == 13
    permanence.record_published(pack, 5)

    assert permanence.published_version("station", "line_hay/kobri") == 3
    assert permanence.published_version("scene", "ch1_first_job/intro") == 3
    assert permanence.published_version("variant", "salon.nish/crystal") == 3
    assert permanence.published_version("line", "line_gamaa") is None


# -- speech reviews (FR-017) ----------------------------------------------------------------------


def reviewed(line: SpeechLine) -> SpeechLine:
    line.reviewed_by, line.reviewed_at = "author1", timezone.now()
    line.save()
    return line


@pytest.mark.parametrize("field", ["text_ar_eg", "text_ar"])
def test_a_text_change_clears_the_review(field: str) -> None:
    line = reviewed(make.speech_line())

    setattr(line, field, "changed text")
    line.save()

    stored = SpeechLine.objects.get()
    assert (stored.reviewed_by, stored.reviewed_at) == ("", None)


def test_a_text_change_clears_the_review_with_update_fields() -> None:
    line = reviewed(make.speech_line())

    line.text_ar_eg = "changed text"
    line.save(update_fields=["text_ar_eg"])

    assert SpeechLine.objects.get().reviewed_by == ""


def test_an_unchanged_text_keeps_its_review() -> None:
    line = reviewed(make.speech_line())

    line.order = 2
    line.save()

    assert SpeechLine.objects.get().reviewed_by == "author1"


def test_a_review_needs_both_its_name_and_time() -> None:
    line = make.speech_line()

    line.reviewed_by = "author1"
    with pytest.raises(IntegrityError), transaction.atomic():
        line.save()


# -- a line's display fare (M09 FR-043) ------------------------------------------------------------


@pytest.mark.parametrize("fare", [475, 0])
def test_a_display_fare_off_the_coins_is_refused(fare: int) -> None:
    line = make.line()
    line.display_fare_piasters = fare

    with pytest.raises(ValidationError) as caught:
        line.full_clean()
    assert "display_fare_piasters" in caught.value.message_dict
    with (
        pytest.raises(IntegrityError, match="content_line_display_fare_coins"),
        transaction.atomic(),
    ):
        Line.objects.filter(pk=line.pk).update(display_fare_piasters=fare)
    assert Line.objects.get().display_fare_piasters == 700


def test_a_display_fare_of_coins_is_kept() -> None:
    line = make.line(display_fare_piasters=850)

    line.full_clean()
    assert Line.objects.get().display_fare_piasters == 850


# -- packs (FR-027) -------------------------------------------------------------------------------


@pytest.mark.parametrize("field", ["file", "sha256", "validation_report"])
def test_a_validated_pack_keeps_its_file_hash_and_report(field: str) -> None:
    pack = make.pack(4, Status.VALIDATED)

    setattr(pack, field, {"file": b"other", "sha256": "0" * 64, "validation_report": {}}[field])
    with pytest.raises(ImmutableError, match=f"core-4 is validated, so {field} can't change"):
        pack.save()


def test_a_draft_pack_can_change() -> None:
    pack = make.pack(4)

    pack.validation_report = {"outcome": "failed"}
    pack.save()

    assert ContentPack.objects.get().validation_report == {"outcome": "failed"}


@pytest.mark.parametrize("status", [Status.PUBLISHED, Status.RETIRED])
def test_a_stored_pack_changes_only_its_minimum_app_version(status: str) -> None:
    pack = make.pack(4, status)

    pack.min_client_version = "1.3.0"
    pack.save()
    pack.built_by = "someone"
    with pytest.raises(ImmutableError, match="built_by can't change"):
        pack.save()

    assert ContentPack.objects.get().min_client_version == "1.3.0"


@pytest.mark.parametrize(
    ("start", "target"),
    [
        (Status.DRAFT, Status.PUBLISHED),
        (Status.VALIDATED, Status.DRAFT),
        (Status.PUBLISHED, Status.VALIDATED),
        (Status.RETIRED, Status.PUBLISHED),
    ],
)
def test_only_the_documented_transitions_happen(start: str, target: str) -> None:
    pack = make.pack(4, start)

    pack.status = target
    with pytest.raises(ImmutableError, match=f"can't go from {start} to {target}"):
        pack.save()


def test_a_pack_is_validated_only_after_its_build_finished() -> None:
    pack = make.pack(4, build_state="running")

    pack.status = Status.VALIDATED
    with pytest.raises(ImmutableError, match="after its build finished"):
        pack.save()


def test_a_new_pack_starts_as_its_origin_says() -> None:
    with pytest.raises(ImmutableError, match="a built pack starts as draft"):
        ContentPack.objects.create(
            pack_id="core",
            version=1,
            origin="built",
            status=Status.PUBLISHED,
            build_state="finished",
        )


@pytest.mark.parametrize("status", [Status.PUBLISHED, Status.RETIRED])
def test_a_stored_pack_record_is_never_deleted(status: str) -> None:
    pack = make.pack(4, status)
    make.pack(5, Status.PUBLISHED)  # so pack 4 isn't current, which a foreign key also protects

    with pytest.raises(ImmutableError, match="its record is kept"), transaction.atomic():
        ContentPack.objects.filter(pk=pack.pk).delete()


def test_a_draft_pack_can_be_pruned() -> None:
    make.pack(4)

    ContentPack.objects.all().delete()

    assert not ContentPack.objects.exists()


# -- the audit log (FR-038) -----------------------------------------------------------------------


def test_the_audit_log_refuses_updates_and_deletes() -> None:
    record = audit.record("publish", "succeeded", "publisher1", make.pack(4), {"why": "test"})

    record.outcome = "failed"
    with pytest.raises(ImmutableError, match="append-only"):
        record.save()
    with pytest.raises(ImmutableError, match="append-only"):
        record.delete()
    with pytest.raises(ImmutableError, match="append-only"), transaction.atomic():
        ContentAuditRecord.objects.all().delete()

    stored = ContentAuditRecord.objects.get()
    assert (stored.outcome, stored.version, stored.actor) == ("succeeded", 4, "publisher1")


def test_the_database_refuses_audit_updates_and_deletes_too() -> None:
    audit.record("publish", "succeeded", "publisher1", make.pack(4))

    with pytest.raises(DatabaseError, match="append-only"), transaction.atomic():
        ContentAuditRecord.objects.update(outcome="failed")
    with (
        pytest.raises(DatabaseError, match="append-only"),
        transaction.atomic(),
        connection.cursor() as cursor,
    ):
        cursor.execute("DELETE FROM content_contentauditrecord")

    assert ContentAuditRecord.objects.get().outcome == "succeeded"


# -- one current pack (data-model "Invariants") ---------------------------------------------------


def make_current(channel: ContentChannel, pack: ContentPack) -> None:
    with checked_at_commit():
        channel.current = pack
        channel.save()


def test_the_current_pack_is_the_highest_published(channel: ContentChannel) -> None:
    first = make.pack(1, Status.PUBLISHED)
    second = make.pack(2, Status.PUBLISHED)

    make_current(channel, second)
    with pytest.raises(IntegrityError, match="current must be the highest"):
        make_current(channel, first)


def test_the_current_pack_must_be_published(channel: ContentChannel) -> None:
    validated = make.pack(1, Status.VALIDATED)

    with pytest.raises(IntegrityError, match="current must be the highest"):
        make_current(channel, validated)


def test_publishing_without_moving_current_is_refused(channel: ContentChannel) -> None:
    make_current(channel, make.pack(1, Status.PUBLISHED))

    with pytest.raises(IntegrityError, match="current must be the highest"), checked_at_commit():
        make.pack(2, Status.PUBLISHED, current=False)
    with checked_at_commit():
        channel.current = make.pack(3, Status.PUBLISHED)
        channel.save()

    assert ContentChannel.objects.get().current.version == 3  # type: ignore[union-attr]


def test_a_published_pack_with_no_current_is_refused(channel: ContentChannel) -> None:
    with pytest.raises(IntegrityError, match="current must be the highest"), checked_at_commit():
        make.promoted(1, current=False)


# -- keys -----------------------------------------------------------------------------------------


def test_every_content_model_has_a_uuid7_key() -> None:
    assert check_uuid7_primary_keys([apps.get_app_config("content")]) == []
