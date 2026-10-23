"""Authored events (RULES.md §8): each fires once, at its `at_seconds` on the trip clock, which
shifts never move.

Mirrors `packages/trip_engine/lib/src/rules/authored_events.dart`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_content.models import TripEvent

from wassal_solver.engine.clock import MS_PER_SECOND
from wassal_solver.engine.model import ChangeRequest, Dispute, Presence
from wassal_solver.engine.rules.chain import drop_mid_hop
from wassal_solver.engine.rules.stations import board_if_free, shift_schedule

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip


def authored_events(tx: Trip) -> None:
    """Phase 3 (§3): events whose time has come, in definition order. One that can't apply is
    skipped, and never fires later."""
    state = tx.state
    fired = state.events_fired
    index = tx.course.passenger_index
    for i, event in enumerate(tx.course.events):
        if fired[i] or event.at_seconds * MS_PER_SECOND > state.t_ms:
            continue
        fired[i] = True
        named = [index[passenger_id] for passenger_id in event.passenger_ids or ()]
        if _can_fire(tx, event, named):
            _fire(tx, i, event, named)


def _can_fire(tx: Trip, event: TripEvent, named: list[int]) -> bool:
    """Everyone named must be aboard, or waiting for a pickup; a passenger has at most one open
    change request; and a dispute needs a liar: exactly one of the two has paid."""
    event_id = event.event_id.value
    presence = Presence.WAITING if event_id == "roadside_pickup" else Presence.ABOARD
    passengers = tx.state.passengers
    if any(passengers[q].presence is not presence for q in named):
        return False
    if event_id == "change_request":
        return not any(passengers[q].passenger_id in tx.state.change_requests for q in named)
    if event_id == "payment_dispute":
        return sum(passengers[q].fare_sent for q in named) == 1
    return True


def _fire(tx: Trip, index: int, event: TripEvent, named: list[int]) -> None:
    """The parameters were validated at start, so a missing one is never reached."""
    state = tx.state
    passengers = state.passengers
    event_id = event.event_id.value
    if event_id == "bump":
        drop_mid_hop(tx)
    elif event_id == "traffic" and event.seconds is not None:
        shift_schedule(tx, event.seconds * MS_PER_SECOND)
        state.traffic_active = True
    elif event_id == "open_road" and event.seconds is not None:
        shift_schedule(tx, -event.seconds * MS_PER_SECOND)
    elif event_id == "fare_increase" and event.amount_piasters is not None:
        state.fare_increase_piasters += event.amount_piasters
        for q in named:
            state.old_fare_payers.add(passengers[q].passenger_id)
    elif event_id == "drop_me_here":
        (q,) = named
        seconds = event.seconds
        passengers[q].deadline_ms = state.t_ms + (
            tx.params.trip_station_warning_ms if seconds is None else seconds * MS_PER_SECOND
        )
    elif event_id == "payment_dispute":
        a, b = (passengers[q].passenger_id for q in named)
        state.disputes[index] = Dispute(a=a, b=b)
    elif event_id == "change_request" and event.amount_piasters is not None:
        (q,) = named
        state.change_requests[passengers[q].passenger_id] = ChangeRequest(event.amount_piasters)
    elif event_id == "roadside_pickup":
        for q in named:
            passengers[q].pickup_due = True
            board_if_free(tx, q)
