"""Watching a mirror trip step by step, in place of the Dart events the mirror leaves out
(research R3): when a hop starts, and when a condition first holds."""

from __future__ import annotations

from collections.abc import Callable

from wassal_solver.engine import Trip
from wassal_solver.engine.model import TripStatus


def hops(trip: Trip, until_ms: int, token_id: int | None = None) -> list[tuple[str, int]]:
    """Steps to `until_ms` one step at a time and lists each hop as it starts, as
    `("from>to", duration_ms)`: Dart's `TokenHopStarted`. A hop starts in `move_tokens`, so a
    token whose hop has 0 ms elapsed after a step started it in that step."""
    out: list[tuple[str, int]] = []
    while trip.status is TripStatus.RUNNING and trip.t_ms < until_ms:
        trip.step()
        for token in trip.state.tokens.values():
            if token_id is not None and token.token_id != token_id:
                continue
            if token.hop_to is not None and token.hop_elapsed_ms == 0:
                out.append((f"{token.holder}>{token.hop_to}", token.hop_duration_ms))
    return out


def first_t(trip: Trip, holds: Callable[[Trip], bool], until_ms: int) -> int | None:
    """Steps one step at a time until `holds(trip)`, and returns the clock then; None if it
    doesn't hold by `until_ms`."""
    while trip.status is TripStatus.RUNNING and trip.t_ms < until_ms:
        trip.step()
        if holds(trip):
            return trip.t_ms
    return None
