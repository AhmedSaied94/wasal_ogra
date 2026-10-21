"""The trip preview in the admin (B05 contracts/content-pipeline.md §6, spec US5; T098)."""

from __future__ import annotations

import inspect
from dataclasses import replace
from pathlib import Path
from typing import Any

import pytest
from django.contrib.admin.models import LogEntry
from django.db import IntegrityError, OperationalError
from django.forms.models import model_to_dict
from django.test import Client
from pytest_django import DjangoCaptureOnCommitCallbacks, Settings
from wassal_content.source import assemble_pack
from wassal_solver import SolverResult, Verdict
from wassal_solver import bundled_params as real_params
from wassal_solver import solve as real_solve
from wassal_solver.engine.params import ParamsError
from wassal_solver.settings import SCORE_INPUTS
from wassal_solver.solver import End

from apps.accounts.models import User
from apps.content import tasks
from apps.content.models import (
    ContentAuditRecord,
    ContentPack,
    Line,
    SolverRun,
    Trip,
    TripPassenger,
)
from apps.content.services import preview, snapshot
from apps.content.tests.conftest import admin_client
from apps.content.tests.test_build import built, off_trip_station

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

Status = SolverRun.Status
RUNNING = "The solver is running. Reload this page in a minute."
ALREADY = "A preview is already running."
EARLIER = "This preview is for an earlier version of the trip."


@pytest.fixture(autouse=True)
def _real_solver(settings: Settings, packs_dir: Path) -> None:
    settings.CONTENT_SOLVER_STAGE = "solver"


@pytest.fixture
def eager(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    """`solve_trip.delay` runs the job at once, in this process. Returns the run ids."""
    calls: list[str] = []

    def run(run_pk: str) -> None:
        calls.append(run_pk)
        tasks.solve_trip.apply(args=(run_pk,)).get()

    monkeypatch.setattr(tasks.solve_trip, "delay", run)
    return calls


def hay_01() -> Trip:
    return Trip.objects.select_related("line").get(line__line_id="line_hay", number=1)


def solve_url(trip: Trip) -> str:
    return f"/admin/content/trip/{trip.pk}/solve/"


def change_url(trip: Trip) -> str:
    return f"/admin/content/trip/{trip.pk}/change/"


def previewed(
    client: Client, trip: Trip, capture: DjangoCaptureOnCommitCallbacks
) -> tuple[str, SolverRun]:
    """POSTs the button, runs the queued job on commit, then reads the page it redirects to."""
    with capture(execute=True):
        response = client.post(solve_url(trip))
    assert response.status_code == 302
    assert response["Location"] == change_url(trip)
    run = SolverRun.objects.filter(trip=trip, kind="preview").latest("created_at")
    return client.get(change_url(trip)).content.decode(), run


def state() -> dict[str, Any]:
    """Everything a preview must leave alone (FR-037)."""
    return {
        "pack": assemble_pack(snapshot.snapshot("1.0").tree, 1),
        "trips": sorted(
            (str(t.pk), t.rev, t.updated_at, model_to_dict(t)) for t in Trip.objects.all()
        ),
        "packs": ContentPack.objects.count(),
        "audit": ContentAuditRecord.objects.count(),
        "log": LogEntry.objects.count(),
    }


# -- who and where -------------------------------------------------------------------------------


def test_an_author_sees_the_button_and_queues_a_preview(
    sample_reviewed: User,
    eager: list[str],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    client = admin_client(sample_reviewed)
    trip = hay_01()
    page = client.get(change_url(trip)).content.decode()
    assert "Run the solver" in page
    assert f'action="{solve_url(trip)}"' in page

    page, run = previewed(client, trip, django_capture_on_commit_callbacks)

    assert RUNNING in page
    assert eager == [str(run.pk)]
    assert (run.kind, run.status, run.requested_by) == ("preview", "done", "author1")
    assert run.trip_identifier == "line_hay.01"


def test_staff_without_change_trip_see_no_button_and_get_403(
    sample_reviewed: User, plain_staff: User, eager: list[str]
) -> None:
    client = admin_client(plain_staff)
    trip = hay_01()
    assert "Run the solver" not in client.get(change_url(trip)).content.decode()
    assert client.post(solve_url(trip)).status_code == 403
    assert not SolverRun.objects.exists()
    assert eager == []


def test_the_solve_url_takes_only_a_post_with_a_csrf_token(
    sample_reviewed: User, eager: list[str]
) -> None:
    signed_in = admin_client(sample_reviewed)
    trip = hay_01()
    assert signed_in.get(solve_url(trip)).status_code == 405
    strict = Client(enforce_csrf_checks=True)
    strict.cookies = signed_in.cookies

    assert strict.post(solve_url(trip)).status_code == 403

    assert not SolverRun.objects.exists()


def test_production_offers_no_preview(
    sample_reviewed: User, settings: Settings, eager: list[str]
) -> None:
    client = admin_client(sample_reviewed)
    trip = hay_01()
    SolverRun.objects.create(
        kind="preview",
        status="done",
        trip=trip,
        input_key=preview.current_key(trip),
        trip_identifier=trip.trip_id,
        result={"verdict": "solved", "end": "found", "stars": 3},
        finished_at=trip.updated_at,
    )
    settings.CONTENT_ROLE = "target"
    settings.CONTENT_PROMOTION_SOURCE_URL = "https://staging.example.test/packs/"

    page = client.get(change_url(trip)).content.decode()

    assert "Run the solver" not in page
    assert "Solver preview" not in page
    assert client.post(solve_url(trip)).status_code == 403
    assert SolverRun.objects.count() == 1


# -- one at a time -------------------------------------------------------------------------------


@pytest.mark.parametrize("status", ["queued", "running"])
def test_a_second_preview_while_one_is_active_makes_no_run(
    sample_reviewed: User,
    eager: list[str],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
    status: str,
) -> None:
    client = admin_client(sample_reviewed)
    trip = hay_01()
    active = SolverRun.objects.create(
        kind="preview",
        status=status,
        trip=trip,
        input_key=preview.current_key(trip),
        trip_identifier=trip.trip_id,
        requested_by="someone",
    )

    page = client.get(change_url(trip)).content.decode()
    assert "Running since" in page
    assert "disabled" in page
    with django_capture_on_commit_callbacks(execute=True):
        response = client.post(solve_url(trip), follow=True)

    assert ALREADY in response.content.decode()
    assert list(SolverRun.objects.values_list("pk", flat=True)) == [active.pk]
    assert eager == []


def test_request_preview_returns_the_active_run(sample_reviewed: User, eager: list[str]) -> None:
    trip = hay_01()
    first, created = preview.request_preview(trip, sample_reviewed)
    again, created_again = preview.request_preview(trip, sample_reviewed)
    assert (created, created_again) == (True, False)
    assert again.pk == first.pk
    assert first.status == "queued"


# -- the job --------------------------------------------------------------------------------------


def test_another_integrity_error_is_not_taken_for_a_running_preview(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    trip = hay_01()
    queued(trip)

    def broken(**fields: Any) -> SolverRun:
        raise IntegrityError("some other constraint")

    monkeypatch.setattr(SolverRun.objects, "create", broken)
    with pytest.raises(IntegrityError, match="some other constraint"):
        preview.request_preview(trip, sample_reviewed)


def test_a_trip_that_fails_its_checks_is_never_solved(
    sample_reviewed: User,
    eager: list[str],
    monkeypatch: pytest.MonkeyPatch,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    trip = hay_01()
    passenger = TripPassenger.objects.filter(trip=trip).order_by("order").first()
    assert passenger is not None
    TripPassenger.objects.filter(pk=passenger.pk).update(dest_station=off_trip_station(trip))

    def never(*args: Any) -> Any:
        raise AssertionError("solve was called")

    monkeypatch.setattr(preview, "solve", never)

    page, run = previewed(admin_client(sample_reviewed), trip, django_capture_on_commit_callbacks)

    assert run.status == "failed"
    assert run.finished_at is not None
    [finding] = [f for f in run.result["findings"] if f["code"] == "V-T4"]
    assert finding["severity"] == "error"
    assert "Solver preview" in page
    assert "V-T4" in page


def test_a_safety_cap_is_stored_failed_and_a_build_solves_the_trip_again(
    sample_reviewed: User,
    eager: list[str],
    monkeypatch: pytest.MonkeyPatch,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    def capped(*args: Any) -> SolverResult:
        result = real_solve(*args)
        return replace(result, verdict=Verdict.NOT_SOLVED, end=End.SAFETY_CAP, run=None, score=None)

    monkeypatch.setattr(preview, "solve", capped)
    page, run = previewed(
        admin_client(sample_reviewed), hay_01(), django_capture_on_commit_callbacks
    )

    assert (run.status, run.result["end"]) == ("failed", "safety_cap")
    assert "safety cap" in page
    pack = built(sample_reviewed)
    meta = pack.validation_report["stages"]["solver"]["meta"]
    assert (meta["solved"], meta["reused"]) == (5, 0)


def test_a_done_preview_is_reused_by_the_next_build(
    sample_reviewed: User,
    eager: list[str],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    _, run = previewed(admin_client(sample_reviewed), hay_01(), django_capture_on_commit_callbacks)
    assert run.status == "done"

    pack = built(sample_reviewed)

    meta = pack.validation_report["stages"]["solver"]["meta"]
    assert (meta["solved"], meta["reused"]) == (4, 1)
    assert "author1" not in str(pack.validation_report)
    assert b"author1" not in bytes(pack.file)


def test_a_redelivered_job_changes_nothing(sample_reviewed: User) -> None:
    trip = hay_01()
    for status in ("running", "done", "failed"):
        finished = None if status == "running" else trip.updated_at
        run = SolverRun.objects.create(
            kind="build" if status != "running" else "preview",
            status=status,
            trip=trip if status == "running" else None,
            input_key="k" * 64,
            trip_identifier=trip.trip_id,
            result={"kept": status},
            finished_at=finished,
        )
        before = (run.status, run.result, run.finished_at, run.updated_at)

        tasks.solve_trip.apply(args=(str(run.pk),)).get()

        run.refresh_from_db()
        assert (run.status, run.result, run.finished_at, run.updated_at) == before


def queued(trip: Trip) -> SolverRun:
    return SolverRun.objects.create(
        kind="preview",
        status="queued",
        trip=trip,
        input_key=preview.current_key(trip),
        trip_identifier=trip.trip_id,
    )


def test_a_preview_that_stops_on_an_error_is_failed_and_frees_the_trip(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    trip = hay_01()
    run = queued(trip)

    def broken(*args: object, **kwargs: object) -> list[Any]:
        raise RuntimeError("a bug in the checks")

    monkeypatch.setattr(preview, "document_findings", broken)
    tasks.solve_trip.apply(args=(str(run.pk),)).get()

    run.refresh_from_db()
    assert run.status == Status.FAILED
    assert run.result == {"error": "the preview stopped on an internal error"}
    assert run.finished_at is not None
    assert "solver preview: the preview of line_hay.01 stopped" in caplog.text
    _, made = preview.request_preview(trip, sample_reviewed)
    assert made


def test_a_trip_deleted_while_its_preview_runs_fails_the_run(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    run = queued(hay_01())

    def gone(trip: Trip) -> dict[str, Any]:
        raise Trip.DoesNotExist

    monkeypatch.setattr(preview, "trip_document", gone)
    tasks.solve_trip.apply(args=(str(run.pk),)).get()

    run.refresh_from_db()
    assert run.status == Status.FAILED
    assert run.result == {"error": "the trip no longer exists"}


def test_a_line_without_tunables_fails_the_preview_and_keeps_the_page(
    sample_reviewed: User,
    eager: list[str],
    monkeypatch: pytest.MonkeyPatch,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    real = real_params

    def params(line_id: str) -> Any:
        if line_id == "line_hay":
            raise ParamsError(f"TripParams key trip_hop_ms_{line_id} is missing")
        return real(line_id)

    monkeypatch.setattr(preview, "bundled_params", params)
    trip = hay_01()
    page, run = previewed(admin_client(sample_reviewed), trip, django_capture_on_commit_callbacks)

    assert run.status == Status.FAILED
    assert run.result == {
        "error": "the app's tunables have no params for line_hay "
        "(TripParams key trip_hop_ms_line_hay is missing)"
    }
    assert "the app&#x27;s tunables have no params for line_hay" in page


def test_a_preview_the_broker_refuses_is_failed_and_frees_the_trip(
    sample_reviewed: User,
    monkeypatch: pytest.MonkeyPatch,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    def refused(run_pk: str) -> None:
        raise ConnectionError("the broker is down")

    monkeypatch.setattr(tasks.solve_trip, "delay", refused)
    trip = hay_01()
    page, run = previewed(admin_client(sample_reviewed), trip, django_capture_on_commit_callbacks)

    run.refresh_from_db()
    assert run.status == Status.FAILED
    assert run.result == {"error": "the preview could not be queued"}
    assert "the preview could not be queued" in page
    _, made = preview.request_preview(trip, sample_reviewed)
    assert made


def test_a_run_that_no_longer_exists_is_ignored(sample_reviewed: User) -> None:
    tasks.solve_trip.apply(args=("01a00000-0000-7000-8000-000000000000",)).get()
    assert not SolverRun.objects.exists()


def test_the_job_has_the_content_queue_options() -> None:
    task: Any = tasks.solve_trip._get_current_object()  # type: ignore[attr-defined]
    assert task.name == "content.tasks.solve_trip"
    assert task.queue == "content"
    assert task.acks_late is True
    assert task.reject_on_worker_lost is True
    assert task.max_retries == 3
    assert task.retry_backoff is True
    assert task.autoretry_for == (OperationalError,)
    # bind=True: the class keeps the function itself, which takes the task as `self`.
    assert list(inspect.signature(type(task).__dict__["run"]).parameters) == ["self", "run_pk"]


# -- the panel ------------------------------------------------------------------------------------


def test_the_panel_shows_the_result_and_checks_the_band_as_it_is_now(
    sample_reviewed: User,
    eager: list[str],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    client = admin_client(sample_reviewed)
    trip = hay_01()
    page, run = previewed(client, trip, django_capture_on_commit_callbacks)
    score = run.result["score"]

    assert "Solver preview" in page
    assert "solved, found" in page
    assert "3 stars" in page
    assert f"Score {score['value']}" in page
    for name in SCORE_INPUTS:
        entry = score["inputs"][name]
        assert f"<td>{name}</td><td>{entry['value']}</td><td>{entry['points']}</td>" in page
    assert "Band 0\N{EN DASH}30: in band" in page
    assert run.result["settings_version"] in page
    timeline = run.result["timeline"]
    assert page.count('<tr class="timeline">') == len(timeline) > 0
    assert "collect_fare" in page
    assert "give_change" in page
    assert EARLIER not in page
    assert "Running since" not in page

    Line.objects.filter(line_id="line_hay").update(difficulty_max=score["value"] - 1)
    narrowed = client.get(change_url(trip)).content.decode()
    assert f"Band 0\N{EN DASH}{score['value'] - 1}: outside the band" in narrowed
    assert SolverRun.objects.count() == 1


def test_the_panel_says_when_the_preview_is_for_an_earlier_version(
    sample_reviewed: User,
    eager: list[str],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    client = admin_client(sample_reviewed)
    trip = hay_01()
    previewed(client, trip, django_capture_on_commit_callbacks)
    Trip.objects.filter(pk=trip.pk).update(tray_50=trip.tray_50 + 1)

    assert EARLIER in client.get(change_url(trip)).content.decode()


def test_a_trip_that_cannot_be_solved_names_the_passenger_and_station(
    sample_reviewed: User,
    eager: list[str],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    trip = hay_01()
    Trip.objects.filter(pk=trip.pk).update(tray_50=0, tray_100=0, max_break_requests=0)

    page, run = previewed(admin_client(sample_reviewed), trip, django_capture_on_commit_callbacks)

    assert (run.status, run.result["verdict"]) == ("done", "not_solved")
    assert "not_solved, exhausted" in page
    assert "First fight at 30.030 s (p1, madrasa)" in page


# -- nothing changes ------------------------------------------------------------------------------


def test_a_preview_changes_no_content_pack_or_audit_record(
    sample_reviewed: User,
    eager: list[str],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    client = admin_client(sample_reviewed)
    trip = hay_01()
    before = state()

    _, run = previewed(client, trip, django_capture_on_commit_callbacks)

    assert run.status == "done"
    assert state() == before
    assert "author1" not in str(run.result)
    assert list(SolverRun.objects.values_list("requested_by", flat=True)) == ["author1"]
