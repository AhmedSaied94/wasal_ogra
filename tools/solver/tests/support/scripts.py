"""Helpers for driving a mirror trip in tests, ported from `scripts.dart` and `edits.dart`.

`ok` and `rejects` apply a command expecting it to be accepted or rejected. The setters put the
state in a situation directly, outside the rules, for unit tests only.
"""

from __future__ import annotations

from collections.abc import Iterable

from wassal_content.models import TripDefinition

from tests.support.builders import default_params
from wassal_solver.engine import Trip, start
from wassal_solver.engine.commands import Command, RejectionCode
from wassal_solver.engine.model import (
    Alertness,
    Claim,
    MoneyToken,
    PassengerState,
    TokenKind,
)
from wassal_solver.engine.money import Pieces
from wassal_solver.engine.params import TripParams


def start_trip(
    definition: TripDefinition, *, params: TripParams | None = None, seed: int | None = None
) -> Trip:
    return start(
        definition,
        params or default_params(definition.line_id),
        definition.seed if seed is None else seed,
    )


def ok(trip: Trip, command: Command) -> None:
    """Applies `command`, expecting it to be accepted."""
    rejection = trip.apply(command)
    assert rejection is None, f"{command} was rejected: {rejection}"


def rejects(trip: Trip, command: Command, code: RejectionCode) -> None:
    """Applies `command`, expecting `code` and no change to the state or the log."""
    before = trip.state.to_json()
    log = list(trip.command_log)
    rejection = trip.apply(command)
    assert rejection is not None, f"{command} was accepted"
    assert rejection.code == code, f"{command}: {rejection}"
    assert trip.state.to_json() == before, f"a rejected {command} changed the state"
    assert list(trip.command_log) == log


def play(trip: Trip, script: Iterable[tuple[int, Command]]) -> Trip:
    """Steps to each time and applies its command, expecting it to be accepted."""
    for t_ms, command in script:
        trip.step_to(t_ms)
        ok(trip, command)
    return trip


def step_to_seconds(trip: Trip, seconds: int) -> None:
    trip.step_to(seconds * 1000)


def passenger(trip: Trip, passenger_id: str) -> PassengerState:
    return trip.state.passengers[trip.course.index_of(passenger_id)]


def balance(trip: Trip, passenger_id: str) -> int:
    return passenger(trip, passenger_id).balance


def set_alertness(trip: Trip, passenger_id: str, alertness: Alertness) -> None:
    """Sets `passenger_id`'s alertness, with no timer."""
    state = passenger(trip, passenger_id)
    state.alertness = alertness
    state.alert_until_ms = None
    state.taps = 0


def set_reputation(trip: Trip, reputation: int) -> None:
    trip.state.reputation = reputation


def set_traffic_active(trip: Trip, active: bool) -> None:
    trip.state.traffic_active = active


def open_claim(trip: Trip, passenger_id: str, *, truthful: bool) -> None:
    trip.state.claims[passenger_id] = Claim(truthful=truthful)


def hold_token(
    trip: Trip,
    holder: str,
    *,
    kind: TokenKind,
    pieces: dict[int, int],
    owner: str,
    target: str,
) -> MoneyToken:
    """Puts a new token in `holder`'s hands, with the next id."""
    state = trip.state
    token = MoneyToken(
        token_id=state.next_token_id,
        kind=kind,
        pieces=Pieces.of(pieces),
        owner=owner,
        target=target,
        holder=holder,
    )
    state.next_token_id += 1
    state.tokens[token.token_id] = token
    return token
