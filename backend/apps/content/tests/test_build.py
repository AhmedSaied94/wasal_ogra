"""Building and validating packs (tasks.md T069, US3, FR-019-FR-024, research R7, R10)."""

from __future__ import annotations

import json
import threading
from collections.abc import Callable, Mapping
from datetime import timedelta
from io import StringIO
from typing import Any

import pytest
from django.core.exceptions import PermissionDenied
from django.core.management import CommandError, call_command
from django.db import connection, transaction
from django.utils import timezone
from pytest_django import DjangoCaptureOnCommitCallbacks, Settings
from wassal_content.engine import capabilities
from wassal_content.findings import STAGES, Finding
from wassal_content.rules import size

from apps.accounts.models import User
from apps.content import tasks
from apps.content.models import (
    ContentChannel,
    ContentPack,
    SolverRun,
    SpeechLine,
    SpeechPool,
    Station,
    TaskTemplate,
    Trip,
    TripPassenger,
)
from apps.content.models.packs import BuildState, Status
from apps.content.services import build, exporter
from apps.content.services import snapshot as snapshot_module
from apps.content.services.stages import SolverOutput
from apps.content.tests.conftest import SAMPLE
from apps.content.tests.factories import sync_channel

GOLDEN = json.loads((SAMPLE.parent / "sample.golden.json").read_text())

pytestmark = pytest.mark.django_db


@pytest.fixture
def queued(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    """The pack ids `build_pack.delay` was called with. Nothing reaches the broker."""
    calls: list[str] = []
    monkeypatch.setattr(tasks.build_pack, "delay", calls.append)
    return calls


def built(actor: User) -> ContentPack:
    return build.run_build(str(build.new_draft(actor).pk))


def publish(pack: ContentPack) -> ContentPack:
    """Make a validated pack current, as Phase 7's publish will."""
    with transaction.atomic():
        pack.status = Status.PUBLISHED
        pack.release_sha256 = "r" * 64
        pack.save()
        sync_channel()
    return pack


def findings(pack: ContentPack, code: str) -> list[dict[str, str]]:
    return [f for f in pack.validation_report["findings"] if f["code"] == code]


def results(pack: ContentPack) -> dict[str, str]:
    return {stage: data["result"] for stage, data in pack.validation_report["stages"].items()}


# -- green and draft builds -----------------------------------------------------------------------


def test_the_sample_builds_to_validated(
    sample_reviewed: User,
    queued: list[str],
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    with django_capture_on_commit_callbacks(execute=True):
        pack = build.request_build(sample_reviewed)
    assert pack.status == Status.DRAFT
    assert pack.build_state == BuildState.QUEUED
    assert pack.version is None
    assert queued == [str(pack.pk)]

    pack = build.run_build(queued[0])

    assert pack.status == Status.VALIDATED
    assert pack.build_state == BuildState.FINISHED
    assert pack.version == 1
    assert pack.size == len(bytes(pack.file)) > 0
    assert len(pack.sha256) == len(pack.canonical_sha256) == 64
    assert pack.built_by == "author1"
    assert pack.built_at is not None
    assert pack.min_client_version == "1.0.0"
    pack.refresh_from_db()
    assert set(pack.validation_report["stages"]) == set(STAGES)
    assert set(results(pack).values()) == {"passed"}
    assert pack.validation_report["stages"]["size"]["bytes"] == pack.size
    assert pack.validation_report["schema_version"] == "1.0"
    assert pack.validation_report["findings"] == []
    assert exporter.stored_pack(pack)["version"] == 1


def test_an_unreviewed_import_stays_draft_with_one_finding_per_line(
    sample_imported: User,
) -> None:
    pack = built(sample_imported)

    assert pack.status == Status.DRAFT
    assert pack.build_state == BuildState.FINISHED
    assert results(pack)["review"] == "failed"
    unreviewed = findings(pack, "V-V1")
    assert len(unreviewed) == SpeechLine.objects.count()
    assert {(f["entity"], f["stage"], f["severity"]) for f in unreviewed} == {
        ("speech_pool", "review", "error")
    }
    assert unreviewed[0]["path"] == "$.lines[0]"


def test_min_client_version_follows_the_current_pack(sample_reviewed: User) -> None:
    first = built(sample_reviewed)
    ContentPack.objects.filter(pk=first.pk).update(min_client_version="1.4.0")
    first.refresh_from_db()
    publish(first)

    assert build.new_draft(sample_reviewed).min_client_version == "1.4.0"


# -- who may build (FR-019) -----------------------------------------------------------------------


def test_request_build_needs_build_pack_on_the_source(
    sample_reviewed: User, plain_staff: User, inactive_author: User, settings: Settings
) -> None:
    for actor in (None, plain_staff, inactive_author):
        with pytest.raises(PermissionDenied):
            build.request_build(actor)
    settings.CONTENT_ROLE = "target"
    with pytest.raises(PermissionDenied):
        build.request_build(sample_reviewed)
    assert not ContentPack.objects.exists()


def test_the_command_needs_an_actor() -> None:
    with pytest.raises(CommandError, match="--actor"):
        call_command("content_build")


@pytest.mark.parametrize("dry_run", [False, True])
def test_the_command_refuses_actors_without_build_pack(
    sample_reviewed: User, plain_staff: User, inactive_author: User, dry_run: bool
) -> None:
    flags = ["--dry-run"] if dry_run else []
    for username in ("staff1", "former1"):
        with pytest.raises(CommandError, match="build_pack"):
            call_command("content_build", "--actor", username, *flags)
    with pytest.raises(CommandError, match="There is no user"):
        call_command("content_build", "--actor", "nobody", *flags)
    assert not ContentPack.objects.exists()
    assert ContentChannel.objects.get(pack_id="core").last_assigned_version == 0


@pytest.mark.parametrize("dry_run", [False, True])
def test_the_command_is_refused_on_the_target(
    sample_reviewed: User, settings: Settings, dry_run: bool
) -> None:
    settings.CONTENT_ROLE = "target"
    flags = ["--dry-run"] if dry_run else []
    with pytest.raises(CommandError):
        call_command("content_build", "--actor", "author1", *flags)
    assert not ContentPack.objects.exists()


def test_the_command_builds_synchronously(sample_reviewed: User) -> None:
    out = StringIO()
    call_command("content_build", "--actor", "author1", stdout=out)

    pack = ContentPack.objects.get()
    assert pack.status == Status.VALIDATED
    assert f"version 1: validated\nsha256 {pack.sha256}\n" in out.getvalue()


def test_the_command_fails_on_a_draft_result(sample_imported: User) -> None:
    out = StringIO()
    with pytest.raises(CommandError, match="stays draft"):
        call_command("content_build", "--actor", "author1", stdout=out)
    assert "error V-V1 speech_pool" in out.getvalue()


def test_version_is_only_for_a_dry_run(sample_reviewed: User) -> None:
    with pytest.raises(CommandError, match="only for --dry-run"):
        call_command("content_build", "--actor", "author1", "--version", "3")
    with pytest.raises(CommandError, match="at least 1"):
        call_command("content_build", "--actor", "author1", "--dry-run", "--version", "0")
    assert not ContentPack.objects.exists()


# -- reproducible (US3-2, SC-004) -----------------------------------------------------------------


def test_the_same_content_and_version_give_the_golden_checksums(sample_imported: User) -> None:
    outputs = []
    for _ in range(2):
        out = StringIO()
        call_command(
            "content_build", "--actor", "author1", "--dry-run", "--version", "1", stdout=out
        )
        outputs.append(out.getvalue())

    assert outputs[0] == outputs[1]
    assert f"sha256 {GOLDEN['sha256']}\n" in outputs[0]
    assert f"canonical_sha256 {GOLDEN['canonical_sha256']}\n" in outputs[0]
    assert f"size {GOLDEN['size']}\n" in outputs[0]
    assert not ContentPack.objects.exists()
    assert ContentChannel.objects.get(pack_id="core").last_assigned_version == 0


def test_a_dry_run_without_version_shows_the_next_one(sample_reviewed: User) -> None:
    out = StringIO()
    call_command("content_build", "--actor", "author1", "--dry-run", stdout=out)
    assert out.getvalue().startswith("version 1 (dry run, no pack saved)\n")


def test_two_builds_of_the_same_content_store_the_same_bytes_but_their_version(
    sample_reviewed: User,
) -> None:
    first, second = built(sample_reviewed), built(sample_reviewed)

    assert (first.version, second.version) == (1, 2)
    one, two = exporter.stored_pack(first), exporter.stored_pack(second)
    assert {**one, "version": 0} == {**two, "version": 0}
    rebuilt = build.produce(snapshot_module.snapshot("1.0"), 1, None, review=True)
    assert rebuilt.file == bytes(first.file)


# -- findings (US3-3, US3-4, US3-5) ---------------------------------------------------------------


def off_trip_station(trip: Trip) -> Station:
    """A station of the trip's line that the trip doesn't stop at, added if there is none."""
    on_trip = set(trip.trip_stations.values_list("station", flat=True))
    spare = trip.line.stations.exclude(pk__in=on_trip).first()
    if spare is not None:
        return spare
    last = trip.line.stations.order_by("-order").first()
    order = (last.order if last else 0) + 1
    return Station.objects.create(line=trip.line, station_id="spare", order=order, name_ar_eg="x")


def test_a_broken_reference_stays_draft_and_names_its_path(sample_reviewed: User) -> None:
    trip = Trip.objects.select_related("line").order_by("line__line_id", "number").first()
    assert trip is not None
    passenger = TripPassenger.objects.filter(trip=trip).order_by("order").first()
    assert passenger is not None
    TripPassenger.objects.filter(pk=passenger.pk).update(dest_station=off_trip_station(trip))

    pack = built(sample_reviewed)

    assert pack.status == Status.DRAFT
    assert results(pack)["references"] == "failed"
    [broken] = [f for f in findings(pack, "V-T4") if f["path"].endswith(".dest_station_id")]
    assert broken["entity"] == "trip"
    assert broken["id"] == trip.permanent_identifier()
    index = list(trip.passengers.order_by("order").values_list("pk", flat=True)).index(passenger.pk)
    assert broken["path"] == f"$.passengers[{index}].dest_station_id"


def test_a_digit_in_task_text_is_a_content_rule_error(sample_reviewed: User) -> None:
    task = TaskTemplate.objects.order_by("task_id").first()
    assert task is not None
    TaskTemplate.objects.filter(pk=task.pk).update(text_ar_eg="do it 5 times")

    pack = built(sample_reviewed)

    assert pack.status == Status.DRAFT
    [digit] = [f for f in findings(pack, "V-X1") if f["id"] == task.task_id]
    assert (digit["entity"], digit["path"]) == ("task", "$.text.ar-EG")


def test_a_bonat_item_price_is_a_content_rule_error(sample_reviewed: User) -> None:
    # The database refuses such a price, so the stage is tested on the snapshot itself: a
    # rollback rebuilds stored content, which the same stage must check.
    parts = snapshot_module.snapshot("1.0")
    assert parts.tree.catalog is not None
    prices = parts.tree.catalog["prices"]
    index = next(i for i, price in enumerate(prices) if price["sku_kind"] == "item")
    prices[index] = {**prices[index], "currency": "BONAT"}

    output = build.produce(parts, 1, None, review=True)

    assert not output.passed
    assert [f["code"] for f in output.report["findings"]] == ["V-M1"]


def test_findings_are_grouped_by_stage_with_errors_first(sample_imported: User) -> None:
    task = TaskTemplate.objects.order_by("task_id").first()
    assert task is not None
    TaskTemplate.objects.filter(pk=task.pk).update(text_ar_eg="do it 5 times")

    pack = built(sample_imported)

    stages = [f["stage"] for f in pack.validation_report["findings"]]
    assert stages == sorted(stages, key=STAGES.index)
    assert stages[0] == "content_rules"
    assert stages[-1] == "review"


def test_the_size_warning_does_not_block(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(size, "SIZE_WARNING_BYTES", 100)

    pack = built(sample_reviewed)

    assert pack.status == Status.VALIDATED
    assert results(pack)["size"] == "warning"
    [warning] = findings(pack, "V-S1")
    assert (warning["severity"], warning["entity"], warning["id"]) == ("warning", "pack", "core")


# -- the engine's rules and speech (specs/004 content-contract §5) --------------------------------


def no_fights(trips: list[dict[str, Any]]) -> dict[str, bool]:
    return {trip["trip_id"]: trip["rules"]["no_fights_required"] for trip in trips}


def test_the_snapshot_and_the_pack_carry_no_fights_required(sample_reviewed: User) -> None:
    Trip.objects.filter(line__line_id="line_hay", number=1).update(no_fights_required=True)
    expected = {
        "line_gamaa.01": False,
        "line_gamaa.02": False,
        "line_hay.01": True,
        "line_hay.02": False,
        "line_hay.03": True,
    }

    parts = snapshot_module.snapshot("1.0").tree.parts
    pack = built(sample_reviewed)

    assert no_fights(parts["trips"]) == expected
    assert pack.status == Status.VALIDATED
    assert no_fights(exporter.stored_pack(pack)["trips"]) == expected


def test_one_reviewed_line_per_engine_slot_builds_to_validated(engine_pools: User) -> None:
    keys = {slot.default_key for slot in capabilities().speech_slots.values()}
    assert set(SpeechPool.objects.values_list("speech_key", flat=True)) == keys

    pack = built(engine_pools)

    assert pack.status == Status.VALIDATED
    assert pack.validation_report["findings"] == []


def test_a_missing_engine_pool_stays_draft_with_v_t10(engine_pools: User) -> None:
    slot = list(capabilities().speech_slots.values())[-1]
    SpeechPool.objects.filter(speech_key=slot.default_key).delete()

    pack = built(engine_pools)

    assert pack.status == Status.DRAFT
    assert results(pack)["content_rules"] == "failed"
    [missing] = pack.validation_report["findings"]
    assert (missing["code"], missing["entity"], missing["id"], missing["path"]) == (
        "V-T10",
        "pack",
        "core",
        "$.speech_pools",
    )
    assert slot.default_key in missing["message"]


# -- rev (US3-6, FR-023) --------------------------------------------------------------------------


def test_rev_goes_up_only_for_changed_trips(sample_reviewed: User) -> None:
    first = publish(built(sample_reviewed))
    before = {trip["trip_id"]: trip["rev"] for trip in exporter.stored_pack(first)["trips"]}
    changed = Trip.objects.select_related("line").order_by("line__line_id", "number").first()
    assert changed is not None
    Trip.objects.filter(pk=changed.pk).update(seed=changed.seed + 1 if changed.seed < 10**6 else 1)

    second = built(sample_reviewed)

    after = {trip["trip_id"]: trip["rev"] for trip in exporter.stored_pack(second)["trips"]}
    changed_id = changed.permanent_identifier()
    assert after[changed_id] == before[changed_id] + 1
    assert {k: v for k, v in after.items() if k != changed_id} == {
        k: v for k, v in before.items() if k != changed_id
    }
    # The authored `rev` doesn't move: only the built pack carries the new one.
    assert Trip.objects.get(pk=changed.pk).rev == changed.rev


def test_with_revs_keeps_new_trips_and_unchanged_ones() -> None:
    pack = {"trips": [{"trip_id": "a", "rev": 1, "x": 1}, {"trip_id": "b", "rev": 1, "x": 2}]}
    current = {"a": {"trip_id": "a", "rev": 4, "x": 1}}

    trips = build.with_revs(pack, current)["trips"]

    assert trips == [{"trip_id": "a", "rev": 4, "x": 1}, {"trip_id": "b", "rev": 1, "x": 2}]


# -- the solver stage (US3-8, FR-022) -------------------------------------------------------------


class FailingSolver:
    """A stage that fails every pack, with the protocol of B05 contracts/content-pipeline.md §1."""

    def run(self, pack: Mapping[str, Any], progress: Callable[[], None]) -> SolverOutput | None:
        progress()
        finding = Finding(
            path="$",
            code="V-Z1",
            message="no 3-star solution",
            stage="solver",
            entity="trip",
            id=pack["trips"][0]["trip_id"],
        )
        return SolverOutput([finding], [], {})


def test_no_solver_reports_not_available(sample_reviewed: User, settings: Settings) -> None:
    settings.CONTENT_SOLVER_STAGE = "none"

    pack = built(sample_reviewed)

    # Validated, but its solver stage didn't pass, so publishing refuses it (test_publish).
    assert results(pack)["solver"] == "not_available"
    assert pack.status == Status.VALIDATED


def test_the_stand_in_passes(sample_reviewed: User, settings: Settings) -> None:
    settings.CONTENT_SOLVER_STAGE = "stand_in"
    pack = built(sample_reviewed)
    assert results(pack)["solver"] == "passed"
    solver = pack.validation_report["stages"]["solver"]
    assert (solver["trips"], solver["meta"]) == ([], {"stand_in": True})


def test_a_failing_solver_keeps_the_pack_draft(sample_reviewed: User, settings: Settings) -> None:
    settings.CONTENT_SOLVER_STAGE = f"{__name__}.FailingSolver"

    pack = built(sample_reviewed)

    assert pack.status == Status.DRAFT
    assert results(pack)["solver"] == "failed"
    assert [f["code"] for f in pack.validation_report["findings"]] == ["V-Z1"]


# -- snapshots (US3-7) ----------------------------------------------------------------------------


@pytest.mark.django_db(transaction=True)
def test_an_edit_committed_during_a_build_is_not_in_the_pack(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    trip = Trip.objects.order_by("line__line_id", "number").first()
    assert trip is not None
    original = snapshot_module.vehicles

    def edit_then_read() -> Any:
        # Lines are already read, so the snapshot is fixed. Another connection commits an edit.
        def commit_edit() -> None:
            try:
                Trip.objects.filter(pk=trip.pk).update(seed=trip.seed + 1)
            finally:
                connection.close()

        worker = threading.Thread(target=commit_edit)
        worker.start()
        worker.join()
        return original()

    monkeypatch.setattr(snapshot_module, "vehicles", edit_then_read)

    pack = built(sample_reviewed)

    stored = {t["trip_id"]: t for t in exporter.stored_pack(pack)["trips"]}
    assert stored[trip.permanent_identifier()]["seed"] == trip.seed
    assert Trip.objects.get(pk=trip.pk).seed == trip.seed + 1


# -- the job ---------------------------------------------------------------------------------------


def test_running_the_task_twice_gives_the_same_result(sample_reviewed: User) -> None:
    draft = build.new_draft(sample_reviewed)

    tasks.build_pack.apply(args=(str(draft.pk),)).get()
    first = ContentPack.objects.get(pk=draft.pk)
    tasks.build_pack.apply(args=(str(draft.pk),)).get()
    second = ContentPack.objects.get(pk=draft.pk)

    assert first.status == second.status == Status.VALIDATED
    assert (first.version, first.sha256, first.updated_at) == (
        second.version,
        second.sha256,
        second.updated_at,
    )
    assert ContentChannel.objects.get(pack_id="core").last_assigned_version == 1


def test_a_build_redelivered_while_running_keeps_its_version(sample_reviewed: User) -> None:
    draft = build.new_draft(sample_reviewed)
    ContentPack.objects.filter(pk=draft.pk).update(build_state=BuildState.RUNNING, version=7)

    pack = build.run_build(str(draft.pk))

    assert (pack.version, pack.status) == (7, Status.VALIDATED)
    assert ContentChannel.objects.get(pack_id="core").last_assigned_version == 0


def test_an_unexpected_error_fails_the_build_without_details(
    sample_reviewed: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    def broken(*args: Any, **kwargs: Any) -> Any:
        raise RuntimeError("secret detail")

    monkeypatch.setattr(build, "produce", broken)

    pack = built(sample_reviewed)

    assert (pack.status, pack.build_state) == (Status.DRAFT, BuildState.FAILED)
    assert pack.failure_reason == "internal error, see the logs"


def _aged(pack: ContentPack, minutes: int) -> None:
    ContentPack.objects.filter(pk=pack.pk).update(
        build_state=BuildState.RUNNING, updated_at=timezone.now() - timedelta(minutes=minutes)
    )


def test_the_sweeper_fails_builds_running_for_over_30_minutes(sample_reviewed: User) -> None:
    stuck, recent = build.new_draft(sample_reviewed), build.new_draft(sample_reviewed)
    _aged(stuck, 31)
    _aged(recent, 5)

    assert tasks.sweep_stuck_builds.apply().get() == 1

    stuck.refresh_from_db()
    recent.refresh_from_db()
    assert stuck.build_state == BuildState.FAILED
    assert stuck.failure_reason == "the build stopped: no progress for 30 minutes"
    assert recent.build_state == BuildState.RUNNING
    # A swept build that a worker then picks up changes nothing.
    assert build.run_build(str(stuck.pk)).build_state == BuildState.FAILED


def test_a_build_the_heartbeat_keeps_fresh_is_not_swept(sample_reviewed: User) -> None:
    pack = build.new_draft(sample_reviewed)
    _aged(pack, 45)

    build.heartbeat(pack.pk)()

    assert tasks.sweep_stuck_builds.apply().get() == 0
    pack.refresh_from_db()
    assert pack.build_state == BuildState.RUNNING


def test_a_build_passes_its_heartbeat_to_the_stage(
    sample_reviewed: User, settings: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings.CONTENT_SOLVER_STAGE = f"{__name__}.FailingSolver"
    beats: list[str] = []
    real = build.heartbeat

    def counted(pack_pk: Any) -> Callable[[], None]:
        beat = real(pack_pk)

        def counted_beat() -> None:
            beats.append(str(pack_pk))
            beat()

        return counted_beat

    monkeypatch.setattr(build, "heartbeat", counted)
    pack = built(sample_reviewed)
    assert beats == [str(pack.pk)]


def _run(status: str, minutes: int) -> SolverRun:
    created = SolverRun.objects.create(
        kind=SolverRun.Kind.PREVIEW if status == SolverRun.Status.QUEUED else SolverRun.Kind.BUILD,
        status=status,
        input_key="k" * 64,
        trip_identifier="line_hay.01",
        finished_at=timezone.now() if status in SolverRun.FINISHED else None,
    )
    SolverRun.objects.filter(pk=created.pk).update(
        updated_at=timezone.now() - timedelta(minutes=minutes)
    )
    return created


def test_the_sweeper_fails_solver_runs_with_no_progress_for_30_minutes() -> None:
    queued = _run(SolverRun.Status.QUEUED, 31)
    running = _run(SolverRun.Status.RUNNING, 40)
    recent = _run(SolverRun.Status.RUNNING, 5)
    done = _run(SolverRun.Status.DONE, 90)

    assert tasks.sweep_stuck_builds.apply().get() == 2

    for stopped in (queued, running):
        stopped.refresh_from_db()
        assert stopped.status == SolverRun.Status.FAILED
        assert stopped.result == {"error": "stopped: no progress for 30 minutes"}
        assert stopped.finished_at is not None
    recent.refresh_from_db()
    done.refresh_from_db()
    assert recent.status == SolverRun.Status.RUNNING
    assert done.status == SolverRun.Status.DONE
