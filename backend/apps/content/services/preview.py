"""The trip preview (B05 contracts/content-pipeline.md §6, spec US5, FR-034 to FR-038).

`request_preview` records a queued preview run and queues `solve_trip` on commit. `run_preview`
runs on the worker: the trip's own checks first, then the solver, finished like a build's run, so
a result that depended on the clock or on a bug is never reused. Neither writes to the trip, any
authoring model, a pack or the audit log. `requested_by` stays on the run's row.
"""

from __future__ import annotations

import hashlib
import logging
from typing import Any

from django.db import IntegrityError, transaction
from django.utils import timezone
from pydantic import ValidationError
from wassal_content.canonical import canonical_bytes
from wassal_content.models import TripDefinition, parse
from wassal_content.validate import document_findings
from wassal_solver import bundled_params, load_settings, solve
from wassal_solver.engine.params import ParamsError
from wassal_solver.fingerprint import input_key, params_fingerprint

from apps.accounts.models import User
from apps.content.models import SolverRun, Trip
from apps.content.services import snapshot
from apps.content.services.solver_stage import end_run, finish_run, internal_error

logger = logging.getLogger(__name__)


def trip_document(trip: Trip) -> dict[str, Any]:
    """The trip as a pack would hold it, read fresh with what `trip_part` needs."""
    fresh = snapshot.trips().get(pk=trip.pk)
    return snapshot.trip_part(fresh)


def _definition(document: dict[str, Any]) -> TripDefinition | None:
    try:
        definition = parse("trip", document)
    except ValidationError:
        return None
    return definition if isinstance(definition, TripDefinition) else None


def key_of(document: dict[str, Any]) -> str:
    """The `input_key` builds reuse by, or, for a trip that doesn't parse or whose line has no
    params yet, a hash of the document with its `rev` at 0: it still tells whether the trip
    changed since its preview."""
    definition = _definition(document)
    if definition is not None:
        try:
            return input_key(definition, bundled_params(definition.line_id))
        except ParamsError:
            pass
    return hashlib.sha256(canonical_bytes({**document, "rev": 0})).hexdigest()


def current_key(trip: Trip) -> str:
    return key_of(trip_document(trip))


def request_preview(trip: Trip, user: User) -> tuple[SolverRun, bool]:
    """A new queued preview and True, or the trip's active one and False (one at a time)."""
    from apps.content import tasks  # the tasks module imports the services

    try:
        with transaction.atomic():
            run = SolverRun.objects.create(
                kind=SolverRun.Kind.PREVIEW,
                status=SolverRun.Status.QUEUED,
                trip=trip,
                trip_identifier=trip.trip_id,
                input_key=current_key(trip),
                requested_by=user.get_username(),
            )
    except IntegrityError as error:
        if _constraint(error) != ONE_ACTIVE_PREVIEW:
            raise
        active = SolverRun.objects.filter(
            trip=trip, kind=SolverRun.Kind.PREVIEW, status__in=SolverRun.ACTIVE
        ).first()
        if active is None:  # it finished in between
            raise
        return active, False
    run_pk = str(run.pk)
    transaction.on_commit(lambda: _queue(tasks.solve_trip, run_pk))
    return run, True


ONE_ACTIVE_PREVIEW = "solverrun_one_active_preview"


def _constraint(error: IntegrityError) -> str | None:
    """The name of the constraint the database refused the row for, when it says."""
    diag = getattr(error.__cause__, "diag", None)
    name = getattr(diag, "constraint_name", None)
    return name if isinstance(name, str) else None


def _queue(task: Any, run_pk: str) -> None:
    """Queues the job, or fails the run if the broker refuses, so the trip isn't left with a
    preview that never runs. The page it redirects to then shows the failure."""
    try:
        task.delay(run_pk)
    except Exception:
        logger.exception("solver preview: could not queue run %s", run_pk)
        SolverRun.objects.filter(pk=run_pk, status=SolverRun.Status.QUEUED).update(
            status=SolverRun.Status.FAILED,
            result={"error": "the preview could not be queued"},
            finished_at=timezone.now(),
            updated_at=timezone.now(),
        )


def _claim(run_pk: str) -> SolverRun | None:
    """Sets a queued run `running`. None for a run that is gone, running or finished, so a
    redelivered job changes nothing."""
    with transaction.atomic():
        run = SolverRun.objects.select_for_update().filter(pk=run_pk).first()
        if run is None or run.status != SolverRun.Status.QUEUED:
            return None
        run.status = SolverRun.Status.RUNNING
        run.save(update_fields=["status", "updated_at"])
    return run


def run_preview(run_pk: str) -> SolverRun | None:
    """The job of `content.tasks.solve_trip`: checks, then the solver. Whatever stops it after
    the claim fails the run, so the trip can be previewed again at once."""
    run = _claim(run_pk)
    if run is None:
        return None
    try:
        return _preview(run)
    except Trip.DoesNotExist:  # deleted after the request
        return _failed(run, {"error": "the trip no longer exists"})
    except Exception:
        logger.exception("solver preview: the preview of %s stopped", run.trip_identifier)
        return _failed(run, {"error": "the preview stopped on an internal error"})


def _preview(run: SolverRun) -> SolverRun:
    trip = run.trip
    if trip is None:
        raise Trip.DoesNotExist
    document = trip_document(trip)
    run.input_key = key_of(document)
    findings = document_findings("trip", document)
    errors = [finding for finding in findings if finding.severity == "error"]
    definition = _definition(document)
    if errors or definition is None:
        return _failed(run, {"findings": [finding.to_dict() for finding in findings]})
    settings = load_settings()
    try:
        params = bundled_params(definition.line_id)
    except ParamsError as error:
        message = f"the app's tunables have no params for {definition.line_id} ({error})"
        return _failed(run, {"error": message})
    try:
        result = solve(definition, params, settings).to_json()
    except Exception:
        logger.exception("solver preview: internal error on %s", definition.trip_id)
        result = internal_error(definition, settings, params_fingerprint(params))
    return finish_run(run, result)


def _failed(run: SolverRun, result: dict[str, Any]) -> SolverRun:
    return end_run(run, SolverRun.Status.FAILED, result)
