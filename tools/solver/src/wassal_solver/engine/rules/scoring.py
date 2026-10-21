"""The result of every end: finished, failed or abandoned (RULES.md §11).

Mirrors `packages/trip_engine/lib/src/rules/scoring.dart`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.model import RepCause, StarFlags, TripOutcome, TripResult

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip

PIASTERS_PER_POUND = 100
"""1 EGP = 100 piasters (glossary §3.2)."""


def build_result(tx: Trip, outcome: TripOutcome) -> TripResult:
    state = tx.state
    fares = 0
    for passenger in state.passengers:
        if not passenger.fare_sent:
            continue
        fare = passenger.fare_piasters or 0
        fares += min(fare, passenger.paid_in)
    counters = state.counters
    earnings = fares - counters.overpaid_piasters + counters.tips_piasters
    finished = outcome is TripOutcome.FINISHED
    no_fights = counters.fights == 0
    no_mistakes = not state.mistakes
    pounds = max(earnings, 0) // PIASTERS_PER_POUND
    definition = tx.course.definition
    return TripResult(
        trip_id=definition.trip_id,
        rev=definition.rev,
        outcome=outcome,
        stars=(1 + (1 if no_fights else 0) + (1 if no_fights and no_mistakes else 0))
        if finished
        else 0,
        star_flags=StarFlags(reached=finished, no_fights=no_fights, no_mistakes=no_mistakes),
        fares_collected_piasters=fares,
        overpaid_piasters=counters.overpaid_piasters,
        tips_piasters=counters.tips_piasters,
        earnings_jenehat=min(pounds, definition.max_earnings_jenehat) if finished else 0,
        fights=counters.fights,
        lost_fares=counters.lost_fares,
        missed_stops=counters.missed_stops,
        impatient=counters.impatient,
        caught_liars=counters.caught_liars,
        mistakes=tuple(state.mistakes),
        reputation=max(state.reputation, 0),
        reputation_lost=tuple(
            (cause, state.reputation_lost[cause])
            for cause in RepCause
            if cause in state.reputation_lost
        ),
        duration_ms=state.t_ms,
        boosters_used=tuple(state.boosters_used),
        revived=state.revived,
        command_log_hash=tx.log_hash(),
    )
