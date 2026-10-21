"""Passengers' alertness and patience (RULES.md §3 step 2, §4.5, §7.3).

Mirrors `packages/trip_engine/lib/src/rules/passengers.dart`. Only aboard passengers' timers run.
Speech is left out (research R3).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.clock import STEP_MS
from wassal_solver.engine.model import Alertness, Presence, RepCause
from wassal_solver.engine.money import scale
from wassal_solver.engine.rules.reputation import lose_reputation

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip

_CALLS_TO_ATTEND = 2
"""Taps that make a muted passenger attentive (§4.5 case 3)."""


def initial_alertness(archetype: str) -> Alertness:
    """`asleep` for a sleeper, `muted` for headphones, `awake` otherwise (§2.4)."""
    if archetype == "sleeper":
        return Alertness.ASLEEP
    if archetype == "headphones":
        return Alertness.MUTED
    return Alertness.AWAKE


def _due(tx: Trip, q: int, alertness: Alertness) -> bool:
    """`q` is aboard and `alertness`, and its timer has run out."""
    state = tx.state.passengers[q]
    until = state.alert_until_ms
    return (
        state.presence is Presence.ABOARD
        and state.alertness is alertness
        and until is not None
        and until <= tx.state.t_ms
    )


def alertness_timers(tx: Trip) -> None:
    """Phase 2.1 and 2.2 (§3), each in passenger order: a waking sleeper whose time has come
    wakes, then an awake sleeper whose time has come falls asleep again."""
    passengers = tx.state.passengers
    for q in range(len(passengers)):
        if _due(tx, q, Alertness.WAKING):
            wake(tx, q)
    archetype = tx.course.archetype
    for q in range(len(passengers)):
        if archetype[q] != "sleeper" or not _due(tx, q, Alertness.AWAKE):
            continue
        state = passengers[q]
        state.alertness = Alertness.ASLEEP
        state.alert_until_ms = None


def attention_timers(tx: Trip) -> None:
    """Phase 2.3 (§3): an attentive passenger whose time is up is muted again."""
    passengers = tx.state.passengers
    for q in range(len(passengers)):
        if not _due(tx, q, Alertness.ATTENTIVE):
            continue
        state = passengers[q]
        state.alertness = Alertness.MUTED
        state.alert_until_ms = None
        state.taps = 0


def call_muted(tx: Trip, q: int) -> None:
    """Tap case 3 (§4.5): a muted passenger is called, and attends on the second call."""
    state = tx.state.passengers[q]
    taps = state.taps + 1
    if taps < _CALLS_TO_ATTEND:
        state.taps = taps
        return
    state.alertness = Alertness.ATTENTIVE
    state.alert_until_ms = tx.state.t_ms + tx.params.trip_headphones_attentive_ms
    state.taps = 0


def start_waking(tx: Trip, q: int) -> None:
    """Tap case 1 (§4.5): an asleep passenger starts waking."""
    state = tx.state.passengers[q]
    state.alertness = Alertness.WAKING
    state.alert_until_ms = tx.state.t_ms + tx.params.trip_wake_ms


def wake(tx: Trip, q: int) -> None:
    """`q` is awake until `t + trip_sleeper_awake_ms`."""
    state = tx.state.passengers[q]
    state.alertness = Alertness.AWAKE
    state.alert_until_ms = tx.state.t_ms + tx.params.trip_sleeper_awake_ms


def start_patience(tx: Trip, q: int) -> None:
    """Patience starts the first time `q`'s balance is above 0 (§7.3)."""
    state = tx.state.passengers[q]
    if state.balance <= 0 or state.patience_start_ms is not None:
        return
    params = tx.params
    patience = (
        scale(params.trip_patience_ms, params.trip_patience_pct_hurry)
        if tx.course.archetype[q] == "hurry"
        else params.trip_patience_ms
    )
    state.patience_ms = patience
    state.patience_start_ms = patience


def drain_patience(tx: Trip) -> None:
    """Phase 6 (§3): every owed, aboard passenger with patience left loses one step of it, or
    more while traffic is active."""
    trip = tx.state
    drain = (
        scale(STEP_MS, tx.params.trip_patience_drain_pct_traffic)
        if trip.traffic_active
        else STEP_MS
    )
    for q, state in enumerate(trip.passengers):
        left = state.patience_ms
        start = state.patience_start_ms
        if (
            state.presence is not Presence.ABOARD
            or not state.fare_sent
            or state.balance <= 0
            or left is None
            or start is None
            or left <= 0
        ):
            continue
        after = left - drain if left > drain else 0
        state.patience_ms = after
        if not state.half_patience_spoken and after * 2 <= start:
            state.half_patience_spoken = True
        if after == 0:
            _run_out(tx, q)


def _run_out(tx: Trip, q: int) -> None:
    """Patience reached 0: once per passenger, as it never refills."""
    tx.state.passengers[q].impatient = True
    tx.state.counters.impatient += 1
    lose_reputation(tx, RepCause.IMPATIENT, tx.params.rep_impatient)
