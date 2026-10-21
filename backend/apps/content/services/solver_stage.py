"""The real solver stage (B05 contracts/content-pipeline.md §2, §3 and §5, research R13, R14).

For each trip of the pack, in order: its line and the bundled params, the `input_key`, the newest
`done` run with that key (reused, whichever kind made it) or else a new build run solved now, then
`progress()`, then the findings. The band check always uses this pack's line, so a band change is
checked at the next build even though every result is reused.
"""

from __future__ import annotations

import logging
from collections.abc import Mapping
from typing import Any

from django.utils import timezone
from pydantic import ValidationError
from wassal_content.findings import Finding
from wassal_content.models import TripDefinition, parse
from wassal_solver import Band, bundled_params, in_band, load_settings, solve
from wassal_solver.engine.params import ParamsError, TripParams
from wassal_solver.fingerprint import input_key, params_fingerprint, solver_fingerprint
from wassal_solver.settings import SCORE_INPUTS, SolverSettings

from apps.content.models import SolverRun
from apps.content.services.stages import Progress, SolverOutput

logger = logging.getLogger(__name__)

STAGE = "solver"
CLOCK_OR_BUG = frozenset({"safety_cap", "internal_error"})
"""Ends a result is never reused after: the safety cap reads the clock, an internal error is a
bug (§5)."""
_MS = 1000
EN_DASH = "\N{EN DASH}"
"""Between a band's ends, as data-model.md "Finding codes" writes them."""


def finish_run(run: SolverRun, result: Mapping[str, Any]) -> SolverRun:
    """Saves `result` and `finished_at`. `status` is `failed` for an end of `safety_cap` or
    `internal_error`, and `done` otherwise, so reuse never picks up those results (§5)."""
    status = SolverRun.Status.FAILED if result.get("end") in CLOCK_OR_BUG else SolverRun.Status.DONE
    return end_run(run, status, result)


def end_run(run: SolverRun, status: str, result: Mapping[str, Any]) -> SolverRun:
    """Ends a run that is still active and returns it as saved. The first end saved stays: a run
    the sweep failed meanwhile stays failed (§5). The row's lock orders the two updates."""
    now = timezone.now()
    ended = SolverRun.objects.filter(pk=run.pk, status__in=SolverRun.ACTIVE).update(
        input_key=run.input_key,
        result=dict(result),
        status=status,
        finished_at=now,
        updated_at=now,
    )
    run.refresh_from_db()
    if not ended:
        logger.warning("solver run %s had already ended as %s", run.pk, run.status)
    return run


def reusable(key: str) -> dict[str, Any] | None:
    """The newest `done` result for `key`, from a build or a preview."""
    found = (
        SolverRun.objects.filter(input_key=key, status=SolverRun.Status.DONE)
        .order_by("-finished_at", "-created_at")
        .values_list("result", flat=True)
        .first()
    )
    return None if found is None else dict(found)


def line_params(line_id: str) -> TripParams | str:
    """The bundled params of `line_id`, or why there are none: a new line whose tunables the app
    doesn't ship yet."""
    try:
        return bundled_params(line_id)
    except ParamsError as error:
        return f"the app's tunables have no params for {line_id} ({error})"


def solve_now(
    definition: TripDefinition, params: TripParams, settings: SolverSettings, run: SolverRun
) -> dict[str, Any]:
    """Solves `definition` for `run` and finishes it. `solve` never raises; anything else that
    does is logged with the trip id and stored as `internal_error`."""
    try:
        result = solve(definition, params, settings).to_json()
    except Exception:
        logger.exception("solver stage: internal error on %s", definition.trip_id)
        result = internal_error(definition, settings, params_fingerprint(params))
    finish_run(run, result)
    return result


def internal_error(
    definition: TripDefinition, settings: SolverSettings, params: str
) -> dict[str, Any]:
    """The result stored when solving raised: no exception text, which only the logs hold."""
    return {
        "trip_id": definition.trip_id,
        "rev": definition.rev,
        "verdict": "not_solved",
        "end": "internal_error",
        "stars": 0,
        "timeline": [],
        "effort_steps": 0,
        "settings_version": settings.settings_version,
        "solver_fingerprint": solver_fingerprint(),
        "params_fingerprint": params,
    }


class SolverStage:
    """`CONTENT_SOLVER_STAGE=solver`."""

    def run(self, pack: Mapping[str, Any], progress: Progress) -> SolverOutput:
        settings = load_settings()
        bands = {
            line["line_id"]: Band(line["difficulty_band"]["min"], line["difficulty_band"]["max"])
            for line in pack.get("lines", [])
        }
        findings: list[Finding] = []
        trips: list[dict[str, Any]] = []
        solved = reused = 0
        for index, document in enumerate(pack.get("trips", [])):
            trip_id = str(document.get("trip_id", ""))
            path = f"$.trips[{index}]"
            definition = _definition(document)
            if definition is None:
                findings.append(_finding("V-Z2", path, trip_id, UNREADABLE))
                trips.append({"trip_id": trip_id, "verdict": "refused", "end": "refused"})
                progress()
                continue
            params = line_params(definition.line_id)
            if isinstance(params, str):
                findings.append(_finding("V-Z2", path, trip_id, f"the trip is refused: {params}"))
                trips.append({"trip_id": trip_id, "verdict": "refused", "end": "refused"})
                progress()
                continue
            key = input_key(definition, params)
            result = reusable(key)
            was_reused = result is not None
            if result is None:
                run = SolverRun.objects.create(
                    kind=SolverRun.Kind.BUILD,
                    status=SolverRun.Status.RUNNING,
                    input_key=key,
                    trip_identifier=trip_id,
                )
                result = solve_now(definition, params, settings, run)
                solved += 1
            else:
                reused += 1
            progress()
            band = bands.get(definition.line_id)
            finding = finding_for(result, path, trip_id, band, settings)
            if finding is not None:
                findings.append(finding)
            trips.append(summary(definition, result, band, reused=was_reused))
        meta = {
            "solver_fingerprint": solver_fingerprint(),
            "settings_version": settings.settings_version,
            "solved": solved,
            "reused": reused,
        }
        return SolverOutput(findings, trips, meta)


UNREADABLE = "the trip is refused: it doesn't match the trip schema (see the schema stage)"


def _definition(document: Mapping[str, Any]) -> TripDefinition | None:
    try:
        definition = parse("trip", document)
    except ValidationError:
        return None
    return definition if isinstance(definition, TripDefinition) else None


def _finding(code: str, path: str, trip_id: str, message: str, *, warning: bool = False) -> Finding:
    return Finding(
        path=path,
        code=code,
        message=message,
        stage=STAGE,
        severity="warning" if warning else "error",
        entity="trip",
        id=trip_id,
    )


def seconds(t_ms: int) -> str:
    """`30030` → `30.030`, without floats."""
    return f"{t_ms // _MS}.{t_ms % _MS:03d}"


def finding_for(
    result: Mapping[str, Any],
    path: str,
    trip_id: str,
    band: Band | None,
    settings: SolverSettings,
) -> Finding | None:
    """The finding of one result (§2 step 5, data-model.md "Finding codes"), or None."""
    verdict, end = result.get("verdict"), result.get("end")
    if verdict == "refused":
        return _finding("V-Z2", path, trip_id, _refused(result.get("refusals") or []))
    if end == "safety_cap":
        message = f"the solver stopped at its safety cap after {settings.safety_cap_seconds} s"
        return _finding("V-Z3", path, trip_id, message)
    if end == "internal_error":
        logger.error("solver stage: internal error on %s", trip_id)
        return _finding("V-Z4", path, trip_id, "internal solver error; see the error monitor")
    if verdict != "solved":
        return _finding("V-Z1", path, trip_id, _not_solvable(result))
    score = result.get("score")
    if band is None or not isinstance(score, Mapping) or in_band(int(score["value"]), band):
        return None
    most = ", ".join(_most(score))
    message = (
        f"difficulty {score['value']} is outside the line's band "
        f"{band.min}{EN_DASH}{band.max}; "
        f"most from {most}"
    )
    return _finding("V-Z5", path, trip_id, message, warning=True)


def _refused(refusals: list[Mapping[str, Any]]) -> str:
    if not refusals:
        return "the trip is refused"
    first = refusals[0]
    more = f" (and {len(refusals) - 1} more)" if len(refusals) > 1 else ""
    return f"the trip is refused: {first.get('code')}: {first.get('message')}{more}"


def _not_solvable(result: Mapping[str, Any]) -> str:
    message = f"not 3-star solvable: best run {result.get('stars', 0)} stars"
    loss = result.get("first_loss")
    if isinstance(loss, Mapping):
        message += f", first {loss.get('kind')} at {seconds(int(loss.get('t_ms', 0)))} s"
        names = [str(loss[k]) for k in ("passenger_id", "station_id") if loss.get(k)]
        if names:
            message += f" ({', '.join(names)})"
    return f"{message}; search {result.get('end')}"


def _most(score: Mapping[str, Any], count: int = 2) -> list[str]:
    """The inputs that give the most points, the first in SCORE_INPUTS order on a tie."""
    inputs = score.get("inputs") or {}
    ranked = sorted(
        (name for name in SCORE_INPUTS if name in inputs),
        key=lambda name: (-int(inputs[name]["points"]), SCORE_INPUTS.index(name)),
    )
    return [name for name in ranked[:count] if int(inputs[name]["points"]) > 0]


def summary(
    definition: TripDefinition,
    result: Mapping[str, Any],
    band: Band | None,
    *,
    reused: bool,
) -> dict[str, Any]:
    """One trip of `stages.solver.trips` (data-model.md "Validation report additions"), with
    this pack's `rev` and band, even for a reused result."""
    out: dict[str, Any] = {
        "trip_id": definition.trip_id,
        "rev": definition.rev,
        "verdict": result.get("verdict"),
        "end": result.get("end"),
        "stars": result.get("stars", 0),
    }
    score = result.get("score")
    if isinstance(score, Mapping):
        out["score"] = score["value"]
        inputs = score["inputs"]
        out["inputs"] = {name: inputs[name]["value"] for name in SCORE_INPUTS if name in inputs}
    if band is not None:
        out["band"] = band.to_json()
        if isinstance(score, Mapping):
            out["in_band"] = in_band(int(score["value"]), band)
    if result.get("run_hash") is not None:
        out["run_hash"] = result["run_hash"]
    out["reused"] = reused
    if result.get("params_fingerprint") is not None:
        out["params_fingerprint"] = result["params_fingerprint"]
    return out
