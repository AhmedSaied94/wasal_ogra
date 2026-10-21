"""The pack pages of the admin (tasks.md T075, contracts/admin.md "Pack pages")."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest
from pytest_django import DjangoCaptureOnCommitCallbacks, Settings

from apps.accounts.models import User
from apps.accounts.tests.test_admin_csp import (
    InlineScripts,
    admin_csp,
    csp_hash,
    script_sources,
)
from apps.content import tasks
from apps.content.admin.reports import report_sections
from apps.content.models import ContentPack, Trip, TripPassenger
from apps.content.tests.conftest import admin_client
from apps.content.tests.test_build import built, off_trip_station, queued
from apps.content.tests.test_publish import published

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

__all__ = ["queued"]


# -- builds ------------------------------------------------------------------------------


CHANGELIST = "/admin/content/contentpack/"


def test_the_build_button_is_offered_to_builders_on_the_source(
    sample_reviewed: User, plain_staff: User, settings: Settings
) -> None:
    author = admin_client(sample_reviewed)
    assert "Build a new pack" in author.get(CHANGELIST).content.decode()
    assert "Build a new pack" not in admin_client(plain_staff).get(CHANGELIST).content.decode()
    settings.CONTENT_ROLE = "target"
    assert "Build a new pack" not in author.get(CHANGELIST).content.decode()


def test_the_build_button_queues_a_build_and_shows_its_page(
    sample_reviewed: User,
    queued: list[str],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    client = admin_client(sample_reviewed)
    assert client.get("/admin/content/contentpack/build/").status_code == 405

    with django_capture_on_commit_callbacks(execute=True):
        response = client.post("/admin/content/contentpack/build/")

    pack = ContentPack.objects.get()
    assert response.status_code == 302
    assert response["Location"] == f"/admin/content/contentpack/{pack.pk}/change/"
    assert queued == [str(pack.pk)]
    page = client.get(response["Location"]).content.decode()
    assert 'http-equiv="refresh"' in page


def test_the_build_endpoint_refuses_others(
    sample_reviewed: User, plain_staff: User, settings: Settings
) -> None:
    assert admin_client(plain_staff).post("/admin/content/contentpack/build/").status_code == 403
    settings.CONTENT_ROLE = "target"
    client = admin_client(sample_reviewed)
    assert client.post("/admin/content/contentpack/build/").status_code == 403
    assert not ContentPack.objects.exists()


def test_the_pack_page_shows_the_report_with_links(
    sample_reviewed: User, plain_staff: User
) -> None:
    trip = Trip.objects.select_related("line").order_by("line__line_id", "number").first()
    assert trip is not None
    passenger = TripPassenger.objects.filter(trip=trip).order_by("order").first()
    assert passenger is not None
    TripPassenger.objects.filter(pk=passenger.pk).update(dest_station=off_trip_station(trip))
    pack = built(sample_reviewed)

    page = admin_client(plain_staff).get(f"/admin/content/contentpack/{pack.pk}/change/")

    html = page.content.decode()
    assert page.status_code == 200
    assert "Validation report" in html
    assert "references: failed" in html
    assert (
        f'<a href="/admin/content/trip/{trip.pk}/change/">{trip.permanent_identifier()}</a>' in html
    )
    assert (
        html.index("schema: passed")
        < html.index("references: failed")
        < html.index("size: passed (")
    )
    assert 'http-equiv="refresh"' not in html
    assert "Save" not in html


def _report(findings: list[dict[str, str]]) -> dict[str, Any]:
    return {"stages": {"references": {"result": "failed"}}, "findings": findings}


def test_report_sections_put_errors_first_and_link_known_objects(sample_reviewed: User) -> None:
    warning = {"stage": "references", "severity": "warning", "entity": "line", "id": "line_x"}
    error = {"stage": "references", "severity": "error", "entity": "trip", "id": "bad id"}

    [section] = report_sections(_report([warning, error]))

    assert [f["severity"] for f in section["findings"]] == ["error", "warning"]
    assert [f["url"] for f in section["findings"]] == [None, None]
    assert section["hidden"] == 0


def test_the_pack_page_shows_the_solver_table(
    sample_reviewed: User, plain_staff: User, settings: Settings, packs_dir: Path
) -> None:
    settings.CONTENT_SOLVER_STAGE = "solver"
    built(sample_reviewed)
    pack = built(sample_reviewed)

    html = admin_client(plain_staff).get(page(pack)).content.decode()

    assert "solver: passed" in html
    assert "Solver: 0 solved, 5 reused" in html
    table = html[html.index('<table class="solver-trips">') :]
    table = table[: table.index("</table>")]
    headers = ["Trip", "Verdict", "End", "Stars", "Score", "owed_at_once", "change_pieces"]
    headers += ["blockers", "breaks", "tightness_ms", "variety", "Band", "In band", "Reused"]
    assert all(f"<th>{name}</th>" in table for name in headers)
    assert table.count("<tr>") == 6
    trip = Trip.objects.get(line__line_id="line_hay", number=1)
    assert f'<a href="/admin/content/trip/{trip.pk}/change/">line_hay.01</a>' in table
    assert "<td>0\N{EN DASH}30</td>" in table


def test_the_solver_section_holds_its_trips_in_input_order() -> None:
    inputs = {"variety": 4, "breaks": 0, "owed_at_once": 2}
    trip = {"trip_id": "line_x.01", "verdict": "solved", "score": 9, "inputs": inputs}
    report = {
        "stages": {"solver": {"result": "passed", "trips": [trip], "meta": {"solved": 1}}},
        "findings": [],
    }

    [section] = report_sections(report)

    assert section["meta"] == {"solved": 1}
    [row] = section["trips"]
    assert row["inputs"] == [2, "", "", 0, "", 4]
    assert row["url"] is None


def test_a_stage_without_trips_has_no_solver_table(sample_reviewed: User) -> None:
    [section] = report_sections(_report([]))
    assert section["trips"] == []
    assert section["meta"] == {}


# -- publish, rollback, minimum version, download, export (T089) ----------------------------------


def page(pack: ContentPack, action: str = "change") -> str:
    return f"/admin/content/contentpack/{pack.pk}/{action}/"


@pytest.fixture
def delays(monkeypatch: pytest.MonkeyPatch) -> dict[str, list[tuple[Any, ...]]]:
    calls: dict[str, list[tuple[Any, ...]]] = {"publish": [], "build": []}
    monkeypatch.setattr(tasks.publish_pack, "delay", lambda *a: calls["publish"].append(a))
    monkeypatch.setattr(tasks.build_pack, "delay", lambda *a: calls["build"].append(a))
    return calls


def test_a_publisher_confirms_then_queues_the_publish(
    sample_reviewed: User,
    publisher: User,
    delays: dict[str, list[tuple[Any, ...]]],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    pack = built(sample_reviewed)
    client = admin_client(publisher)
    assert ">Publish</a>" in client.get(page(pack)).content.decode()
    confirm = client.get(page(pack, "publish"))
    assert confirm.status_code == 200
    assert "Apps get it within a minute" in confirm.content.decode()

    with django_capture_on_commit_callbacks(execute=True):
        response = client.post(page(pack, "publish"))

    assert response.status_code == 302
    assert response["Location"] == page(pack)
    assert delays["publish"] == [(str(pack.pk), "publisher1")]


def test_publish_is_not_offered_without_the_permission(
    sample_reviewed: User, plain_staff: User
) -> None:
    pack = built(sample_reviewed)
    author = admin_client(sample_reviewed)
    assert ">Publish</a>" not in author.get(page(pack)).content.decode()
    assert author.get(page(pack, "publish")).status_code == 403
    assert author.post(page(pack, "publish")).status_code == 403
    assert admin_client(plain_staff).post(page(pack, "publish")).status_code == 403


def test_a_refused_publish_shows_why(
    sample_reviewed: User,
    publisher: User,
    settings: Settings,
    delays: dict[str, list[tuple[Any, ...]]],
) -> None:
    settings.CONTENT_SOLVER_STAGE = "none"
    pack = built(sample_reviewed)

    response = admin_client(publisher).post(page(pack, "publish"), follow=True)

    assert "solver stage is not_available" in response.content.decode()
    assert delays["publish"] == []


@pytest.fixture
def live(sample_reviewed: User, publisher: User, packs_dir: Path) -> ContentPack:
    return published(built(sample_reviewed), publisher)


def test_a_published_pack_shows_its_promotion_code_on_the_source(
    live: ContentPack, plain_staff: User, settings: Settings
) -> None:
    client = admin_client(plain_staff)
    html = client.get(page(live)).content.decode()
    assert f"<code>core-1:{live.release_sha256}</code>" in html
    settings.CONTENT_ROLE = "target"
    assert "Promotion code" not in client.get(page(live)).content.decode()


def test_a_rollback_is_confirmed_then_queued(
    live: ContentPack,
    publisher: User,
    delays: dict[str, list[tuple[Any, ...]]],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    client = admin_client(publisher)
    assert "Roll back to this" in client.get(page(live)).content.decode()
    assert client.get(page(live, "rollback")).status_code == 200

    with django_capture_on_commit_callbacks(execute=True):
        response = client.post(page(live, "rollback"))

    draft = ContentPack.objects.get(rollback_of=live)
    assert response["Location"] == page(draft)
    assert delays["build"] == [(str(draft.pk),)]


def test_the_minimum_app_version_form(live: ContentPack, publisher: User) -> None:
    client = admin_client(publisher)
    form = client.get(page(live, "min-version"))
    assert form.status_code == 200
    assert 'value="1.0.0"' in form.content.decode()

    refused = client.post(page(live, "min-version"), {"min_client_version": "0.9.0"})
    assert refused.status_code == 200
    assert "need at least 1.0.0" in refused.content.decode()
    saved = client.post(page(live, "min-version"), {"min_client_version": "1.3.0"})
    assert saved.status_code == 302

    assert ContentPack.objects.get(pk=live.pk).min_client_version == "1.3.0"


def test_any_staff_downloads_and_exports(live: ContentPack, plain_staff: User) -> None:
    client = admin_client(plain_staff)

    download = client.get(page(live, "download"))
    assert download["Content-Type"] == "application/gzip"
    assert download["Content-Disposition"] == 'attachment; filename="core-1.json.gz"'
    assert download.content == bytes(live.file)
    export = client.get(page(live, "export"))
    assert export["Content-Type"] == "application/zip"
    assert export["Content-Disposition"] == 'attachment; filename="content-test-core-1.zip"'
    assert export.content.startswith(b"PK")


def test_drafts_cannot_be_exported_or_rolled_back_to(
    sample_imported: User, publisher: User
) -> None:
    draft = built(sample_imported)
    client = admin_client(publisher)
    assert client.get(page(draft, "export")).status_code == 404
    assert client.post(page(draft, "rollback")).status_code == 403
    assert client.get(page(draft, "min-version")).status_code == 403


def test_the_pack_pages_add_no_inline_script(live: ContentPack, publisher: User) -> None:
    allowed = {s for s in script_sources(admin_csp("Caddyfile")) if s.startswith("'sha256-")}
    client = admin_client(publisher)
    for url in (CHANGELIST, page(live), page(live, "rollback"), page(live, "min-version")):
        response = client.get(url)
        assert response.status_code == 200, url
        parser = InlineScripts()
        parser.feed(response.content.decode())
        assert parser.handlers == [], url
        assert {csp_hash(script) for script in parser.scripts} <= allowed, url


def test_the_solver_table_looks_up_only_the_trips_it_lists(sample_reviewed: User) -> None:
    from apps.content.admin.reports import solver_rows

    hay_01 = Trip.objects.get(line__line_id="line_hay", number=1)
    rows = solver_rows([{"trip_id": "line_hay.01"}, {"trip_id": "line_x.01"}])

    assert [row["url"] for row in rows] == [f"/admin/content/trip/{hay_01.pk}/change/", None]


def test_the_trip_links_query_names_each_trip(sample_reviewed: User) -> None:
    from apps.content.admin import reports

    urls = reports._trip_urls(["line_hay.01", "line_gamaa.02", "not a trip id"])

    assert sorted(urls) == ["line_gamaa.02", "line_hay.01"]
