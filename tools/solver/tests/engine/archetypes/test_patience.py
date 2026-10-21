"""Patience (RULES.md §3 step 6, §7.3, M01 clarification 2), ported from `patience_test.dart`: it
starts when a passenger is first owed and drains 33 per step while they are owed and aboard. p1
pays 1000 at 1023 for 700 on line_gamaa.

The events are checked as the state they leave; speech isn't mirrored (research R3), so
`wants_change` is checked as `half_patience_spoken`.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder, params_with
from tests.support.scripts import (
    ok,
    passenger,
    set_traffic_active,
    start_trip,
    step_to_seconds,
)
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, SendHand
from wassal_solver.engine.model import RepCause


def _owed(archetype: str = "regular") -> Trip:
    return start_trip(
        TripBuilder()
        .station("gamaa", 60)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1, archetype=archetype)
        .build()
    )


def _give(trip: Trip, pieces: list[int]) -> None:
    for piece in pieces:
        ok(trip, PickFromTray(piece))
    ok(trip, SendHand("p1"))


def test_it_starts_when_he_is_first_owed_and_drains_in_that_step() -> None:
    trip = _owed()
    trip.step_to(990)
    assert passenger(trip, "p1").patience_ms is None
    trip.step()
    p1 = passenger(trip, "p1")
    assert p1.patience_start_ms == 20000
    assert p1.patience_ms == 20000 - 33
    assert p1.patience_ms * 1000 // p1.patience_start_ms == 998, "Dart's patiencePermille"


def test_a_hurried_passengers_patience_is_half() -> None:
    trip = _owed("hurry")
    trip.step_to(1023)
    assert passenger(trip, "p1").patience_start_ms == 10000


def test_a_passenger_who_paid_exactly_never_starts_patience() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
        .build()
    )
    step_to_seconds(trip, 20)
    assert passenger(trip, "p1").patience_ms is None


def test_wants_change_is_said_once_at_half() -> None:
    # The 304th drain takes 20000 to 9968, at 1023 + 303 * 33.
    trip = _owed()
    trip.step_to(10989)
    assert not passenger(trip, "p1").half_patience_spoken
    trip.step()
    assert trip.t_ms == 11022
    assert passenger(trip, "p1").half_patience_spoken
    assert passenger(trip, "p1").patience_ms == 9968
    assert passenger(trip, "p1").balance == 300


def test_at_zero_reputation_once_and_a_count() -> None:
    trip = _owed()
    trip.step_to(20988)
    assert passenger(trip, "p1").patience_ms == 2
    assert not passenger(trip, "p1").impatient
    trip.step()
    assert trip.t_ms == 21021
    p1 = passenger(trip, "p1")
    assert (p1.patience_ms, p1.impatient) == (0, True)
    assert trip.state.counters.impatient == 1
    assert trip.state.reputation_lost == {RepCause.IMPATIENT: trip.params.rep_impatient}
    assert trip.state.reputation == 100 - trip.params.rep_impatient


def test_it_never_refills_or_repeats() -> None:
    trip = _owed()
    trip.step_to(21021)
    _give(trip, [100, 100])
    step_to_seconds(trip, 70)
    result = trip.result
    assert result is not None
    lost = dict(result.reputation_lost)
    assert lost[RepCause.SHORT_CHANGE] == trip.params.rep_short_change, "the change was short"
    assert lost[RepCause.IMPATIENT] == trip.params.rep_impatient, "charged once"
    assert passenger(trip, "p1").patience_ms == 0
    assert result.impatient == 1


def test_it_stops_draining_once_he_is_settled() -> None:
    trip = _owed()
    trip.step_to(2145)
    _give(trip, [100, 100, 100])
    step_to_seconds(trip, 5)
    settled = passenger(trip, "p1").patience_ms
    step_to_seconds(trip, 30)
    assert passenger(trip, "p1").balance == 0
    assert passenger(trip, "p1").patience_ms == settled


def test_while_traffic_is_active_it_drains_49_per_step() -> None:
    trip = _owed()
    trip.step_to(1023)
    set_traffic_active(trip, True)
    trip.step()
    assert passenger(trip, "p1").patience_ms == 20000 - 33 - 49


def test_one_drain_can_reach_half_and_zero() -> None:
    # Patience of one step: the drain in the step he pays empties it. Dart also checks the
    # speech order pays, wants_change, impatient.
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 60)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1)
        .build(),
        params=params_with({"trip_patience_ms": 33, "trip_patience_pct_hurry": 100}),
    )
    trip.step_to(990)
    assert not passenger(trip, "p1").impatient
    trip.step_to(1023)
    p1 = passenger(trip, "p1")
    assert (p1.patience_ms, p1.half_patience_spoken, p1.impatient) == (0, True, True)
    assert trip.state.counters.impatient == 1
