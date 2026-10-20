"""The change history of authored content (tasks.md T060, FR-018): `django_admin_log`."""

from __future__ import annotations

import pytest
from django.contrib.admin.models import ADDITION, CHANGE, LogEntry
from django.contrib.contenttypes.models import ContentType

from apps.accounts.models import User
from apps.content.models import Line, SpeechLine, SpeechPool
from apps.content.services import importer, review
from apps.content.tests import factories as make
from apps.content.tests.conftest import SAMPLE, admin_client
from apps.content.tests.test_admin_authoring import management

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]


def entries(model: type, user: User) -> list[LogEntry]:
    return list(
        LogEntry.objects.filter(
            content_type=ContentType.objects.get_for_model(model), user=user
        ).order_by("action_time")
    )


def line_post(line: Line, **changes: str) -> dict[str, str]:
    station = line.stations.get()
    return {
        "line_id": line.line_id,
        "name_ar_eg": line.name_ar_eg,
        "name_ar": "",
        "order": str(line.order),
        "unlock_kind": "start",
        "unlock_vehicle": "",
        "unlock_after_line": "",
        "difficulty_min": "0",
        "difficulty_max": "30",
        **management("stations", 1, initial=1),
        "stations-0-id": str(station.pk),
        "stations-0-line": str(line.pk),
        "stations-0-station_id": station.station_id,
        "stations-0-name_ar_eg": station.name_ar_eg,
        "stations-0-name_ar": "",
        "stations-0-order": "1",
        **changes,
    }


def test_an_admin_save_is_logged(author: User) -> None:
    line = make.line()
    make.station(line)

    response = admin_client(author).post(
        f"/admin/content/line/{line.pk}/change/", line_post(line, name_ar_eg="new name")
    )

    assert response.status_code == 302
    (entry,) = entries(Line, author)
    assert (entry.action_flag, entry.object_repr) == (CHANGE, "line_hay")
    assert "Name ar eg" in entry.get_change_message()


def test_an_inline_change_is_logged(author: User) -> None:
    line = make.line()
    make.station(line)

    admin_client(author).post(
        f"/admin/content/line/{line.pk}/change/", line_post(line, **{"stations-0-name_ar_eg": "x"})
    )

    (entry,) = entries(Line, author)
    assert "station" in entry.get_change_message().lower()


def test_a_bulk_review_is_logged_per_line(sample_imported: User) -> None:
    pool = SpeechPool.objects.get(speech_key="passenger.pays")

    response = admin_client(sample_imported).post(
        "/admin/content/speechpool/",
        {"action": "mark_reviewed", "_selected_action": [str(pool.pk)]},
    )

    assert response.status_code == 302
    logged = entries(SpeechLine, sample_imported)
    assert [entry.object_id for entry in logged] == [
        str(line.pk) for line in pool.lines.order_by("order")
    ]
    assert {entry.change_message for entry in logged} == {review.REVIEW_MESSAGE}


def test_an_import_logs_each_added_and_changed_object(author: User) -> None:
    importer.import_dir(SAMPLE, author)

    added = LogEntry.objects.filter(user=author, action_flag=ADDITION)
    assert added.count() == 41
    assert {entry.change_message for entry in added} == {importer.IMPORT_MESSAGE}
    assert "line_hay" in {entry.object_repr for entry in entries(Line, author)}

    Line.objects.filter(line_id="line_hay").update(difficulty_max=31)
    importer.import_dir(SAMPLE, author)

    changed = LogEntry.objects.filter(user=author, action_flag=CHANGE)
    assert [entry.object_repr for entry in changed] == ["line_hay"]


def test_the_history_page_shows_it(sample_imported: User) -> None:
    line = Line.objects.get(line_id="line_hay")

    page = admin_client(sample_imported).get(f"/admin/content/line/{line.pk}/history/")

    assert page.status_code == 200
    assert importer.IMPORT_MESSAGE in page.content.decode()
