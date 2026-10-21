"""Stations: the warning, getting off, boarding, and the end of the trip (RULES.md §9, §11).

Mirrors `packages/trip_engine/lib/src/rules/stations.dart`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.model import (
    Alertness,
    AlightOutcome,
    Mistake,
    MistakeKind,
    Presence,
    RepCause,
    TokenKind,
    TripOutcome,
    TripStatus,
)
from wassal_solver.engine.rules.chain import at_driver, hand_over_tokens, lose_dropped, to_tray
from wassal_solver.engine.rules.claims import accept_claim
from wassal_solver.engine.rules.passengers import initial_alertness
from wassal_solver.engine.rules.reputation import lose_reputation
from wassal_solver.engine.rules.requests import decline_change_request
from wassal_solver.engine.rules.scoring import build_result

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip


def warn_station(tx: Trip) -> None:
    """Phase 7 (§3, §9.2): the next station's warning, once. Who is told is an event, which isn't
    mirrored; the state keeps that the warning fired."""
    state = tx.state
    i = state.next_station_index
    if i >= tx.course.station_count:
        return
    station = state.schedule[i]
    if station.warned or state.t_ms < station.at_ms - tx.params.trip_station_warning_ms:
        return
    station.warned = True


def reach_stations(tx: Trip) -> None:
    """Phase 8.2 (§3): every station reached is processed, in order. The station counts as
    processed from the moment its processing starts."""
    state = tx.state
    count = tx.course.station_count
    while (
        state.next_station_index < count
        and state.t_ms >= state.schedule[state.next_station_index].at_ms
    ):
        i = state.next_station_index
        state.next_station_index += 1
        _process(tx, i)


def _process(tx: Trip, i: int) -> None:
    """§9.4."""
    state = tx.state
    dest = tx.course.dest_index
    board = tx.course.board_index
    for q in range(len(state.passengers)):
        if state.passengers[q].presence is Presence.ABOARD and dest[q] == i:
            get_off(tx, q)
    for q in range(len(state.passengers)):
        passenger = state.passengers[q]
        if passenger.presence is Presence.WAITING and board[q] == i:
            passenger.pickup_due = True
            board_if_free(tx, q)
    state.traffic_active = False


def get_off(tx: Trip, p: int) -> None:
    """Passenger `p` gets off, at their station or their deadline (§9.3)."""
    close_choices(tx, p)
    trip = tx.state
    state = trip.passengers[p]
    counters = trip.counters
    params = tx.params
    unpaid = not state.fare_sent and not tx.course.is_member(p)
    if state.alertness is Alertness.ASLEEP or state.alertness is Alertness.WAKING:
        outcome = AlightOutcome.MISSED_STOP
        lose_reputation(tx, RepCause.MISSED_STOP, params.rep_missed_stop)
        counters.missed_stops += 1
        if unpaid:
            counters.lost_fares += 1
        if state.is_owed:
            _unreturned(tx, p)
    elif state.is_owed:
        outcome = AlightOutcome.FIGHT
        lose_reputation(tx, RepCause.FIGHT, params.rep_fight)
        counters.fights += 1
        _unreturned(tx, p)
    elif unpaid:
        outcome = AlightOutcome.LEFT_UNPAID
        counters.lost_fares += 1
    else:
        outcome = AlightOutcome.THANKED
        _tip(tx, p)
    hand_over_tokens(tx, p)
    trip.set_presence(p, Presence.GONE)
    state.outcome = outcome
    _board_freed(tx, state.seat_id)


def _unreturned(tx: Trip, p: int) -> None:
    """`p` leaves owed: the unreturned balance is a mistake."""
    state = tx.state.passengers[p]
    tx.state.mistakes.append(Mistake(state.passenger_id, MistakeKind.UNRETURNED, state.balance))


def _tip(tx: Trip, p: int) -> None:
    """§9.3: a regular customer who leaves thanked and not impatient tips."""
    if tx.course.archetype[p] != "regular_customer" or tx.state.passengers[p].impatient:
        return
    tx.state.counters.tips_piasters += tx.params.trip_tip_piasters_regular_customer


def close_choices(tx: Trip, p: int) -> None:
    """`p`'s open choices close as they get off (§9.3.1): a claim is accepted, a change request
    declined, and a dispute dropped."""
    state = tx.state
    passenger_id = state.passengers[p].passenger_id
    if passenger_id in state.claims:
        accept_claim(tx, p)
    if passenger_id in state.change_requests:
        decline_change_request(tx, p)
    if state.disputes:
        for index in [
            key
            for key, dispute in state.disputes.items()
            if dispute.a == passenger_id or dispute.b == passenger_id
        ]:
            del state.disputes[index]


def shift_schedule(tx: Trip, delta: int) -> None:
    """Shifts the schedule by `delta` from the next station on (§9.1). An earlier arrival is
    clamped so the next station stays at least `trip_station_warning_ms` away."""
    state = tx.state
    first = state.next_station_index
    count = tx.course.station_count
    if first >= count:
        return
    applied = delta
    if delta < 0:
        at = state.schedule[first].at_ms
        soonest = state.t_ms + tx.params.trip_station_warning_ms
        target = at + delta if at + delta > soonest else soonest
        applied = target - at if target < at else 0
    for j in range(first, count):
        state.schedule[j].at_ms += applied


def reach_deadlines(tx: Trip) -> None:
    """Phase 8.1 (§3): passengers whose `drop_me_here` deadline has come get off, in passenger
    order."""
    state = tx.state
    for q in range(len(state.passengers)):
        passenger = state.passengers[q]
        deadline = passenger.deadline_ms
        if (
            passenger.presence is Presence.ABOARD
            and deadline is not None
            and deadline <= state.t_ms
        ):
            get_off(tx, q)


def _board_freed(tx: Trip, seat_id: str) -> None:
    """Step 5 of §9.3: a waiting passenger whose pickup has come takes the seat."""
    for q, passenger in enumerate(tx.state.passengers):
        if passenger.seat_id == seat_id:
            board_if_free(tx, q)


def board_if_free(tx: Trip, q: int) -> None:
    """Boards `q` if they are waiting, their pickup has come, their seat is free and their
    destination is still ahead (§9.5)."""
    trip = tx.state
    state = trip.passengers[q]
    if (
        state.presence is not Presence.WAITING
        or not state.pickup_due
        or trip.occupant(state.seat_id) is not None
        or tx.course.dest_index[q] < trip.next_station_index
    ):
        return
    trip.set_presence(q, Presence.ABOARD)
    state.alertness = initial_alertness(tx.course.archetype[q])
    state.alert_until_ms = None
    state.taps = 0
    state.pickup_due = False


def end_check(tx: Trip) -> None:
    """Phase 10 (§3, §11): once every station is processed, the money still in transit is
    settled and the trip finishes."""
    state = tx.state
    if state.status is not TripStatus.RUNNING or state.next_station_index < tx.course.station_count:
        return
    for token in list(state.tokens.values()):
        if token.dropped_until_ms is not None:
            lose_dropped(tx, token)
        elif token.kind is TokenKind.FARE:
            at_driver(tx, token)
        else:
            to_tray(tx, token)
    state.result = build_result(tx, TripOutcome.FINISHED)
    state.status = TripStatus.FINISHED
