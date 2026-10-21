"""The `SolverRun` table (B05 data-model.md "SolverRun", tasks.md T082)."""

from __future__ import annotations

import pytest
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.common.ids import uuid7
from apps.content.models import SolverRun, Trip
from apps.content.tests import factories as make

pytestmark = pytest.mark.django_db

Kind = SolverRun.Kind
Status = SolverRun.Status


def a_trip() -> Trip:
    line, vehicle = make.line(), make.vehicle()
    return make.trip(line, vehicle)


def run(trip: Trip | None, kind: str = Kind.PREVIEW, status: str = Status.QUEUED) -> SolverRun:
    finished = timezone.now() if status in SolverRun.FINISHED else None
    return SolverRun.objects.create(
        kind=kind,
        status=status,
        input_key="k" * 64,
        trip_identifier="line_hay.01",
        trip=trip,
        finished_at=finished,
    )


def test_the_id_is_a_uuid7() -> None:
    created = run(a_trip())
    assert created.id.version == 7
    assert type(created.id) is type(uuid7())


@pytest.mark.parametrize("active", [Status.QUEUED, Status.RUNNING])
def test_one_active_preview_per_trip(active: str) -> None:
    trip = a_trip()
    run(trip, status=active)
    with pytest.raises(IntegrityError), transaction.atomic():
        run(trip, status=Status.QUEUED)


@pytest.mark.parametrize("finished", [Status.DONE, Status.FAILED])
def test_a_new_preview_is_allowed_once_the_last_one_finished(finished: str) -> None:
    trip = a_trip()
    run(trip, status=finished)
    run(trip, status=Status.QUEUED)
    assert SolverRun.objects.filter(trip=trip).count() == 2


def test_build_runs_are_never_limited() -> None:
    trip = a_trip()
    run(trip, kind=Kind.BUILD, status=Status.RUNNING)
    run(trip, kind=Kind.BUILD, status=Status.RUNNING)
    run(trip, status=Status.RUNNING)
    run(None, kind=Kind.BUILD, status=Status.RUNNING)
    run(None, kind=Kind.BUILD, status=Status.RUNNING)
    assert SolverRun.objects.count() == 5


@pytest.mark.parametrize(
    ("status", "finished"),
    [
        (Status.DONE, False),
        (Status.FAILED, False),
        (Status.QUEUED, True),
        (Status.RUNNING, True),
    ],
)
def test_finished_at_is_set_exactly_when_the_run_finished(status: str, finished: bool) -> None:
    with pytest.raises(IntegrityError), transaction.atomic():
        SolverRun.objects.create(
            kind=Kind.BUILD,
            status=status,
            input_key="k" * 64,
            trip_identifier="line_hay.01",
            finished_at=timezone.now() if finished else None,
        )


def test_deleting_the_trip_keeps_its_runs() -> None:
    trip = a_trip()
    kept = run(trip, status=Status.DONE)
    trip.delete()
    kept.refresh_from_db()
    assert kept.trip is None
    assert kept.trip_identifier == "line_hay.01"
