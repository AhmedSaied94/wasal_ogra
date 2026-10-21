"""Random runs of the sample trips for the property tests (spec FR-050), drawn as the Dart engine's
`test/fuzz/fuzz_test.dart` draws them: commands chosen among those that could apply in the
current state, interleaved with bursts of steps. Some candidates are still rejected, which is part
of what is tested: a rejected command changes nothing and isn't logged.

Hypothesis draws a seed for each run, as Dart seeds its Xorshift32: a run makes hundreds of
choices, and drawing each through Hypothesis makes its smallest example (never step, always the
first candidate) run to the command cap.
"""

from __future__ import annotations

from collections.abc import Callable
from functools import cache
from pathlib import Path
from random import Random

from hypothesis import strategies as st
from wassal_content.loader import load_json_bytes
from wassal_content.models import BoosterId, TripDefinition

from tests.paths import SAMPLE
from tests.support.builders import definition_of
from wassal_solver.engine import Trip, start
from wassal_solver.engine.commands import (
    Abandon,
    CollectDropped,
    Command,
    PickFromTray,
    RequestBreak,
    ResolveChangeRequest,
    ResolveClaim,
    ResolveDispute,
    ReturnHand,
    Revive,
    SendHand,
    Tap,
    UndoLastSend,
    UseBooster,
)
from wassal_solver.engine.model import Presence, TripState, TripStatus
from wassal_solver.engine.money import DENOMINATIONS
from wassal_solver.engine.params import TripParams

SAMPLES = sorted((SAMPLE / "trips").rglob("*.json"))
"""The five sample trips."""

SEEDS = st.integers(min_value=0, max_value=2**32 - 1)
"""The seed of a run's choices."""

IN_TRIP_BOOSTERS = (
    BoosterId.CHANGE_BAG,
    BoosterId.WAKE_ALL,
    BoosterId.LEDGER_PEEK,
    BoosterId.TRAFFIC_JAM,
)

Observer = Callable[[Trip, Command | None], None]
"""Called at the start, after every step (with None) and after every accepted command."""


@cache
def sample(path: Path) -> TripDefinition:
    return definition_of(load_json_bytes(path.read_bytes()))


def undo_available(state: TripState) -> bool:
    """Dart's `TripState.undoAvailableUntilMs != null`."""
    send = state.last_send
    if send is None or state.status is not TripStatus.RUNNING or state.t_ms > send.until_ms:
        return False
    token = state.tokens.get(send.token_id)
    return token is not None and not token.is_dropped and token.hops_done == 0


def candidates(trip: Trip, rnd: Random) -> list[Command]:
    """The commands that could apply now."""
    state = trip.state
    if state.status is TripStatus.FAILED:
        revive: list[Command] = [Revive()] if state.revivable else []
        return [*revive, Abandon()]
    aboard = [p.passenger_id for p in state.passengers if p.presence is Presence.ABOARD]
    held = [d for d, count in zip(DENOMINATIONS, state.tray.counts, strict=True) if count]
    out: list[Command] = [PickFromTray(d) for d in held]
    if not state.hand.is_empty:
        out.append(ReturnHand())
        out += [SendHand(passenger_id) for passenger_id in aboard]
    if undo_available(state):
        out.append(UndoLastSend())
    out += [Tap(passenger_id) for passenger_id in aboard]
    out += [ResolveClaim(key, insist=rnd.randrange(2) == 0) for key in state.claims]
    out += [
        ResolveDispute(key, dispute.a if rnd.randrange(2) == 0 else dispute.b)
        for key, dispute in state.disputes.items()
    ]
    out += [ResolveChangeRequest(key, agree=rnd.randrange(3) != 0) for key in state.change_requests]
    if trip.course.max_break_requests - state.breaks_used > 0:
        out += [RequestBreak(d) for d in held if d >= 1000]
    out += [CollectDropped(token.token_id) for token in state.tokens.values() if token.is_dropped]
    out.append(UseBooster(rnd.choice(IN_TRIP_BOOSTERS)))
    return out


def run(
    definition: TripDefinition,
    params: TripParams,
    seed: int,
    observe: Observer | None = None,
) -> Trip:
    """One random run of `definition`, to its end. `observe` sees the start, every step and every
    accepted command; every rejected command is checked to change nothing."""
    rnd = Random(seed)  # noqa: S311 - a test's seeded choices, not security
    trip = start(definition, params, definition.seed)
    if observe is not None:
        observe(trip, None)
    while trip.status is TripStatus.RUNNING or (
        trip.status is TripStatus.FAILED and trip.state.revivable
    ):
        if trip.status is TripStatus.RUNNING and rnd.randrange(3) != 0:
            for _ in range(rnd.randrange(45) + 1):
                trip.step()
                if observe is not None:
                    observe(trip, None)
                if trip.status is not TripStatus.RUNNING:
                    break
            continue
        command = rnd.choice(candidates(trip, rnd))
        if isinstance(command, Abandon) and rnd.randrange(20) != 0:
            continue
        before = trip.state.to_json()
        logged = len(trip.command_log)
        if trip.apply(command) is None:
            if observe is not None:
                observe(trip, command)
        else:
            assert trip.state.to_json() == before, f"a rejected {command} changed the state"
            assert len(trip.command_log) == logged
    return trip
