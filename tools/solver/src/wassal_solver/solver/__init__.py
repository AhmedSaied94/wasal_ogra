"""The solver: the idealized player and its search (contracts/solver.md §1 to §4).

`solve` never raises. A trip the mirror refuses gives `refused`; any exception in the search is
logged and gives `internal_error`, which is never `solved` (spec FR-020).
"""

from __future__ import annotations

import logging

from wassal_content.models import TripDefinition

from wassal_solver.engine.params import TripParams
from wassal_solver.engine.replay import ReplayRefused, replay
from wassal_solver.engine.trip import start
from wassal_solver.engine.validation import Refusal, TripRefused
from wassal_solver.fingerprint import params_fingerprint, solver_fingerprint
from wassal_solver.scoring.difficulty import Score, score_trip
from wassal_solver.settings import SolverSettings
from wassal_solver.solver.result import SolverResult, Verdict
from wassal_solver.solver.search import End, Run, run_search
from wassal_solver.solver.timeline import timeline

__all__ = ["End", "SolverResult", "Verdict", "solve"]

logger = logging.getLogger(__name__)

_THREE = 3


def solve(definition: TripDefinition, params: TripParams, settings: SolverSettings) -> SolverResult:
    """Searches `definition` for a 3-star run with `params`, playing from the trip's own seed."""
    made = _Made(definition, params, settings)
    try:
        trip = start(definition, params, definition.seed)
    except TripRefused as refused:
        return made.result(Verdict.REFUSED, End.REFUSED, None, 0, refusals=refused.refusals)
    try:
        outcome = run_search(trip, settings)
        run = outcome.run
        if outcome.end is End.FOUND and run is not None:
            if _confirms(definition, params, run):
                score = score_trip(definition, run.trip.command_log, params, settings)
                return made.result(
                    Verdict.SOLVED, End.FOUND, run, outcome.effort_steps, score=score
                )
            logger.error(
                "solver: the run found for %s did not replay to 3 stars", definition.trip_id
            )
            return made.result(Verdict.NOT_SOLVED, End.INTERNAL_ERROR, None, outcome.effort_steps)
        return made.result(Verdict.NOT_SOLVED, outcome.end, run, outcome.effort_steps)
    except Exception:
        logger.exception("solver: internal error on %s", definition.trip_id)
        return made.result(Verdict.NOT_SOLVED, End.INTERNAL_ERROR, None, 0)


def _confirms(definition: TripDefinition, params: TripParams, run: Run) -> bool:
    """FR-020: the run replays from scratch to 3 stars."""
    try:
        result = replay(definition, definition.seed, params, run.trip.command_log)
    except ReplayRefused:
        return False
    return result.stars == _THREE


class _Made:
    """What every result names: the trip and the fingerprints of what made it."""

    def __init__(
        self, definition: TripDefinition, params: TripParams, settings: SolverSettings
    ) -> None:
        self.definition = definition
        self.settings_version = settings.settings_version
        self.params_fingerprint = params_fingerprint(params)

    def result(
        self,
        verdict: Verdict,
        end: End,
        run: Run | None,
        effort_steps: int,
        *,
        refusals: tuple[Refusal, ...] | None = None,
        score: Score | None = None,
    ) -> SolverResult:
        solved = verdict is Verdict.SOLVED
        log = None if run is None else run.trip.command_log
        entries = () if run is None else tuple(taken.entry for taken in run.taken)
        loss = None if run is None or solved else run.loss
        return SolverResult(
            trip_id=self.definition.trip_id,
            rev=self.definition.rev,
            verdict=verdict,
            end=end,
            stars=0 if run is None else run.stars,
            run=log if solved else None,
            best_run=None if solved else log,
            first_loss=loss,
            timeline=timeline(entries, loss),
            score=score,
            refusals=refusals,
            effort_steps=effort_steps,
            settings_version=self.settings_version,
            solver_fingerprint=solver_fingerprint(),
            params_fingerprint=self.params_fingerprint,
        )
