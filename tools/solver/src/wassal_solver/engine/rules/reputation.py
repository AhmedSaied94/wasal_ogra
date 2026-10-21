"""Reputation changes and the failure check (RULES.md §10).

Mirrors `packages/trip_engine/lib/src/rules/reputation.dart`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.model import RepCause, TripOutcome, TripStatus
from wassal_solver.engine.rules.scoring import build_result

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip

MAX_REPUTATION = 100
"""The reputation scale (RULES.md §1.4)."""


def gain_reputation(tx: Trip, cause: RepCause, amount: int) -> None:
    """Adds `amount`, capping the result at 100. A gain isn't recorded: `cause` names it, for
    the event Dart emits."""
    state = tx.state
    state.reputation = min(state.reputation + amount, MAX_REPUTATION)


def lose_reputation(tx: Trip, cause: RepCause, amount: int) -> None:
    """Subtracts `amount` and records it under `cause`."""
    state = tx.state
    state.reputation -= amount
    if amount > 0:
        state.reputation_lost[cause] = state.reputation_lost.get(cause, 0) + amount


def failure_check(tx: Trip) -> None:
    """After each step and each accepted command (§10.2): a running or paused trip fails when
    reputation is gone, or at the first fight of a trip that requires none. A fight failure can't
    be revived."""
    state = tx.state
    if state.status is not TripStatus.RUNNING and state.status is not TripStatus.PAUSED:
        return
    fought = tx.course.definition.rules.no_fights_required and state.counters.fights > 0
    if state.reputation > 0 and not fought:
        return
    if fought:
        state.revivable = False
    state.status = TripStatus.FAILED
    state.result = build_result(tx, TripOutcome.FAILED)
