"""The real solver stage over the sample (B05 contracts/content-pipeline.md §2, §3, §5; T083)."""

from __future__ import annotations

import logging
from dataclasses import replace
from io import StringIO
from pathlib import Path
from typing import Any

import pytest
from django.core.management import call_command
from pytest_django import Settings
from wassal_content.source import assemble_pack
from wassal_solver import SolverResult, Verdict
from wassal_solver import bundled_params as real_params
from wassal_solver import solve as real_solve
from wassal_solver.engine.params import ParamsError
from wassal_solver.engine.validation import Refusal, RefusalCode
from wassal_solver.settings import SCORE_INPUTS
from wassal_solver.solver import End

from apps.accounts.models import User
from apps.content.models import ContentPack, Line, SolverRun, Trip
from apps.content.models.packs import Status
from apps.content.services import publish, snapshot, solver_stage
from apps.content.tests.test_build import built, findings, results

pytestmark = pytest.mark.django_db

SAMPLE_TRIPS = ["line_gamaa.01", "line_gamaa.02", "line_hay.01", "line_hay.02", "line_hay.03"]
SUMMARY_FIELDS = {
    "trip_id",
    "rev",
    "verdict",
    "end",
    "stars",
    "score",
    "inputs",
    "band",
    "in_band",
    "run_hash",
    "reused",
    "params_fingerprint",
}


@pytest.fixture(autouse=True)
def _real_solver(settings: Settings, packs_dir: Path) -> None:
    settings.CONTENT_SOLVER_STAGE = "solver"


def solver_of(pack: ContentPack) -> dict[str, Any]:
    stage: dict[str, Any] = pack.validation_report["stages"]["solver"]
    return stage


def trip_of(trip_id: str) -> Trip:
    line_id, number = trip_id.split(".")
    return Trip.objects.get(line__line_id=line_id, number=int(number))


def without_reuse(stage: dict[str, Any]) -> dict[str, Any]:
    trips = [{k: v for k, v in trip.items() if k != "reused"} for trip in stage["trips"]]
    meta = {k: v for k, v in stage["meta"].items() if k not in ("solved", "reused")}
    return {"result": stage["result"], "trips": trips, "meta": meta}


def test_the_sample_passes_with_five_solved_trips_and_publishes(
    sample_reviewed: User, publisher: User
) -> None:
    pack = built(sample_reviewed)

    assert pack.status == Status.VALIDATED
    stage = solver_of(pack)
    assert stage["result"] == "passed"
    assert [trip["trip_id"] for trip in stage["trips"]] == SAMPLE_TRIPS
    for trip in stage["trips"]:
        assert set(trip) == SUMMARY_FIELDS
        assert (trip["verdict"], trip["end"], trip["stars"]) == ("solved", "found", 3)
        assert set(trip["inputs"]) == set(SCORE_INPUTS)
        assert all(type(value) is int for value in trip["inputs"].values())
        assert trip["in_band"] is True
        assert trip["reused"] is False
    assert stage["trips"][2]["band"] == [0, 30]
    assert stage["trips"][0]["band"] == [20, 55]
    meta = stage["meta"]
    assert set(meta) == {"solver_fingerprint", "settings_version", "solved", "reused"}
    assert (meta["solved"], meta["reused"]) == (5, 0)
    assert SolverRun.objects.filter(kind="build", status="done").count() == 5
    published = publish.publish(str(pack.pk), publisher)
    assert published.status == Status.PUBLISHED, published.failure_reason


def test_a_rebuild_with_nothing_changed_reuses_every_result(sample_reviewed: User) -> None:
    first = solver_of(built(sample_reviewed))
    second = solver_of(built(sample_reviewed))

    assert (second["meta"]["solved"], second["meta"]["reused"]) == (0, 5)
    assert all(trip["reused"] for trip in second["trips"])
    assert without_reuse(second) == without_reuse(first)
    assert SolverRun.objects.count() == 5


def test_a_band_change_is_checked_at_each_build_never_read_from_a_stored_result(
    sample_reviewed: User,
) -> None:
    built(sample_reviewed)
    Line.objects.filter(line_id="line_hay").update(difficulty_max=17)

    narrowed = built(sample_reviewed)

    stage = solver_of(narrowed)
    assert stage["meta"]["reused"] == 5
    assert stage["result"] == "warning"
    warned = findings(narrowed, "V-Z5")
    assert [(f["id"], f["severity"], f["stage"]) for f in warned] == [
        ("line_hay.02", "warning", "solver")
    ]
    assert warned[0]["message"] == (
        "difficulty 19 is outside the line's band 0–17; most from variety, change_pieces"  # noqa: RUF001
    )
    assert warned[0]["path"] == "$.trips[3]"
    hay_02 = stage["trips"][3]
    assert (hay_02["band"], hay_02["in_band"]) == ([0, 17], False)

    Line.objects.filter(line_id="line_hay").update(difficulty_max=30)
    restored = built(sample_reviewed)
    assert solver_of(restored)["result"] == "passed"
    assert findings(restored, "V-Z5") == []


def test_an_out_of_band_trip_warns_and_still_publishes(
    sample_reviewed: User, publisher: User
) -> None:
    Line.objects.filter(line_id="line_gamaa").update(difficulty_min=40)

    pack = built(sample_reviewed)

    assert pack.status == Status.VALIDATED
    assert results(pack)["solver"] == "warning"
    assert [f["id"] for f in findings(pack, "V-Z5")] == ["line_gamaa.01"]
    published = publish.publish(str(pack.pk), publisher)
    assert published.status == Status.PUBLISHED, published.failure_reason


def test_a_trip_whose_change_cannot_be_made_fails_the_stage(
    sample_reviewed: User, publisher: User
) -> None:
    Trip.objects.filter(pk=trip_of("line_hay.01").pk).update(
        tray_50=0, tray_100=0, max_break_requests=0
    )

    pack = built(sample_reviewed)

    assert pack.status == Status.DRAFT
    assert results(pack)["solver"] == "failed"
    [failure] = findings(pack, "V-Z1")
    assert (failure["stage"], failure["entity"], failure["id"], failure["path"]) == (
        "solver",
        "trip",
        "line_hay.01",
        "$.trips[2]",
    )
    assert failure["severity"] == "error"
    assert failure["message"].startswith("not 3-star solvable: best run 1 stars, first fight at ")
    assert "(p1, madrasa); search " in failure["message"]
    stage = solver_of(pack)
    assert [trip["trip_id"] for trip in stage["trips"]] == SAMPLE_TRIPS
    assert stage["trips"][2]["verdict"] == "not_solved"
    assert "score" not in stage["trips"][2]
    assert [t["verdict"] for i, t in enumerate(stage["trips"]) if i != 2] == ["solved"] * 4
    refused = publish.publish(str(pack.pk), publisher)
    assert refused.status == Status.DRAFT


def _replaced(**changes: Any) -> Any:
    def fake(*args: Any) -> SolverResult:
        return replace(real_solve(*args), **changes)

    return fake


def test_a_refused_trip_is_v_z2(sample_reviewed: User, monkeypatch: pytest.MonkeyPatch) -> None:
    refusals = (
        Refusal(RefusalCode.UNSUPPORTED_ARCHETYPE, "$.passengers[0]", "not played"),
        Refusal(RefusalCode.UNKNOWN_SEAT, "$.passengers[1]", "no such seat"),
    )
    monkeypatch.setattr(
        solver_stage,
        "solve",
        _replaced(
            verdict=Verdict.REFUSED, end=End.REFUSED, run=None, score=None, refusals=refusals
        ),
    )

    pack = built(sample_reviewed)

    messages = {f["message"] for f in findings(pack, "V-Z2")}
    assert messages == {"the trip is refused: unsupported_archetype: not played (and 1 more)"}
    assert len(findings(pack, "V-Z2")) == 5


def no_hop_for(line_id: str, real: Any) -> Any:
    """`bundled_params` as if the app's tunables had no `trip_hop_ms_<line_id>` yet."""

    def params(line: str) -> Any:
        if line == line_id:
            raise ParamsError(f"TripParams key trip_hop_ms_{line} is missing")
        return real(line)

    return params


def test_a_line_without_tunables_is_v_z2_and_the_build_finishes(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(solver_stage, "bundled_params", no_hop_for("line_hay", real_params))

    pack = built(sample_reviewed)

    assert pack.build_state == "finished"
    assert results(pack)["solver"] == "failed"
    refused = findings(pack, "V-Z2")
    assert sorted(f["id"] for f in refused) == ["line_hay.01", "line_hay.02", "line_hay.03"]
    assert {f["message"] for f in refused} == {
        "the trip is refused: the app's tunables have no params for line_hay "
        "(TripParams key trip_hop_ms_line_hay is missing)"
    }
    assert not findings(pack, "V-Z4")


def test_a_safety_cap_is_v_z3_and_is_never_reused(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        solver_stage,
        "solve",
        _replaced(verdict=Verdict.NOT_SOLVED, end=End.SAFETY_CAP, run=None, score=None),
    )

    pack = built(sample_reviewed)

    messages = {f["message"] for f in findings(pack, "V-Z3")}
    assert messages == {"the solver stopped at its safety cap after 180 s"}
    assert SolverRun.objects.filter(status="failed").count() == 5
    monkeypatch.setattr(solver_stage, "solve", real_solve)
    again = solver_of(built(sample_reviewed))
    assert (again["meta"]["solved"], again["meta"]["reused"]) == (5, 0)
    assert again["result"] == "passed"


def test_an_internal_error_is_v_z4_logged_with_the_trip_and_never_reused(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    def broken(*args: Any) -> Any:
        raise RuntimeError("secret detail")

    monkeypatch.setattr(solver_stage, "solve", broken)

    with caplog.at_level(logging.ERROR, logger="apps.content.services.solver_stage"):
        pack = built(sample_reviewed)

    errors = findings(pack, "V-Z4")
    assert {f["message"] for f in errors} == {"internal solver error; see the error monitor"}
    assert len(errors) == 5
    assert "secret detail" not in str(pack.validation_report)
    assert "line_hay.01" in caplog.text
    assert "secret detail" in caplog.text
    assert SolverRun.objects.filter(status="failed").count() == 5
    monkeypatch.setattr(solver_stage, "solve", real_solve)
    assert solver_of(built(sample_reviewed))["meta"]["solved"] == 5


def test_an_internal_error_result_is_v_z4(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    monkeypatch.setattr(
        solver_stage,
        "solve",
        _replaced(verdict=Verdict.NOT_SOLVED, end=End.INTERNAL_ERROR, run=None, score=None),
    )
    with caplog.at_level(logging.ERROR, logger="apps.content.services.solver_stage"):
        pack = built(sample_reviewed)
    assert len(findings(pack, "V-Z4")) == 5
    assert "line_gamaa.02" in caplog.text


def test_progress_is_called_once_per_trip(sample_reviewed: User) -> None:
    pack = solver_stage_pack()
    beats: list[int] = []

    output = solver_stage.SolverStage().run(pack, lambda: beats.append(1))

    assert len(beats) == len(pack["trips"]) == 5
    assert len(output.trips) == 5


def solver_stage_pack() -> dict[str, Any]:
    return assemble_pack(snapshot.snapshot("1.0").tree, 1)


def test_a_dry_run_changes_no_pack(sample_reviewed: User) -> None:
    pack = built(sample_reviewed)
    before = list(ContentPack.objects.values_list("pk", "updated_at"))

    out = StringIO()
    call_command("content_build", "--actor", sample_reviewed.username, "--dry-run", stdout=out)

    assert DRY_RUN_NOTE in out.getvalue()
    assert list(ContentPack.objects.values_list("pk", "updated_at")) == before
    assert ContentPack.objects.get(pk=pack.pk).updated_at == pack.updated_at


DRY_RUN_NOTE = "(dry run, no pack saved)"


def test_a_dry_run_keeps_its_solver_results_for_the_next_build(sample_reviewed: User) -> None:
    packs = ContentPack.objects.count()

    out = StringIO()
    call_command("content_build", "--actor", sample_reviewed.username, "--dry-run", stdout=out)

    assert DRY_RUN_NOTE in out.getvalue()
    assert ContentPack.objects.count() == packs
    assert SolverRun.objects.filter(kind="build", status="done").count() == len(SAMPLE_TRIPS)
    pack = built(sample_reviewed)
    meta = pack.validation_report["stages"]["solver"]["meta"]
    assert (meta["solved"], meta["reused"]) == (0, len(SAMPLE_TRIPS))


def test_finish_run_fails_the_clock_and_bug_ends() -> None:
    for end, status in (
        ("found", "done"),
        ("exhausted", "done"),
        ("budget_spent", "done"),
        ("refused", "done"),
        ("safety_cap", "failed"),
        ("internal_error", "failed"),
    ):
        run = SolverRun.objects.create(
            kind="build", status="running", input_key="k" * 64, trip_identifier="line_hay.01"
        )
        solver_stage.finish_run(run, {"end": end})
        run.refresh_from_db()
        assert (run.status, run.result) == (status, {"end": end})
        assert run.finished_at is not None


def test_no_solve_outlasts_the_sweep_of_stuck_runs() -> None:
    """The sweep fails any run with no progress for STALE_AFTER_SECONDS, and a preview's run makes
    none while it solves: the safety cap must end every solve well before that."""
    from wassal_solver import load_settings

    from apps.content.services.build import STALE_AFTER_SECONDS

    assert load_settings().safety_cap_seconds * 5 <= STALE_AFTER_SECONDS


def test_the_first_end_saved_stays_when_the_sweep_and_the_solve_meet() -> None:
    """The sweep and `finish_run` both end a run; whichever saves first wins, so a run the sweep
    failed isn't then marked done, and a finished run isn't swept."""
    from datetime import timedelta

    from django.utils import timezone

    from apps.content.services import build

    swept = SolverRun.objects.create(
        kind="build", status="running", input_key="s" * 64, trip_identifier="line_hay.01"
    )
    finished = SolverRun.objects.create(
        kind="build", status="running", input_key="f" * 64, trip_identifier="line_hay.02"
    )
    solver_stage.finish_run(finished, {"verdict": "solved", "end": "found"})
    stale = timezone.now() - timedelta(seconds=build.STALE_AFTER_SECONDS + 60)
    SolverRun.objects.update(updated_at=stale)

    assert build.sweep_stuck_builds() == 1
    late = solver_stage.finish_run(swept, {"verdict": "solved", "end": "found"})

    assert (late.status, late.result) == ("failed", {"error": f"stopped: {build.STOPPED}"})
    swept.refresh_from_db()
    assert (swept.status, swept.result) == (late.status, late.result)
    finished.refresh_from_db()
    assert (finished.status, finished.result) == ("done", {"verdict": "solved", "end": "found"})
