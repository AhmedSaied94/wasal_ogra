"""roadside_pickup and skipped events (RULES.md §8, §9.5), ported from
`roadside_pickup_test.dart`.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import passenger, start_trip, step_to_seconds
from wassal_solver.engine.model import ChangeRequest, Presence


def base() -> TripBuilder:
    """p2 waits for the free A_m; p3 for A_r, which p1 frees at kobri (10 s)."""
    return (
        TripBuilder()
        .station("kobri", 10)
        .station("gamaa", 40)
        .passenger("p1", seat="A_r", dest="kobri", payment=[500, 100, 100], pays_at=1)
        .passenger("p2", seat="A_m", dest="gamaa", payment=[500, 100, 100])
        .passenger("p3", seat="A_r", dest="gamaa", payment=[500, 100, 100])
        .event("roadside_pickup", 5, passengers=["p2", "p3"])
    )


def test_listed_passengers_start_waiting() -> None:
    trip = start_trip(base().build())
    assert passenger(trip, "p2").presence == Presence.WAITING
    assert passenger(trip, "p3").presence == Presence.WAITING


def test_one_whose_seat_is_free_boards_at_the_event() -> None:
    trip = start_trip(base().build())
    trip.step_to(4983)
    assert passenger(trip, "p2").presence == Presence.WAITING
    trip.step_to(5016)
    # Dart also checks the boards speech, which isn't mirrored.
    p2 = passenger(trip, "p2")
    assert (p2.presence, p2.seat_id, p2.pickup_due) == (Presence.ABOARD, "A_m", False)
    step_to_seconds(trip, 6)
    p3 = passenger(trip, "p3")
    assert (p3.presence, p3.pickup_due) == (Presence.WAITING, True)


def test_one_whose_seat_is_taken_boards_the_moment_it_is_freed() -> None:
    trip = start_trip(base().build())
    trip.step_to(9999)
    assert passenger(trip, "p3").presence == Presence.WAITING
    # Dart checks the order of the boarding and alighting events; the state shows p1 gone and
    # p3 aboard in the same step, at kobri.
    trip.step_to(10032)
    assert passenger(trip, "p1").presence == Presence.GONE
    p3 = passenger(trip, "p3")
    assert (p3.presence, p3.pickup_due) == (Presence.ABOARD, False)
    assert trip.state.occupant("A_r") == trip.course.index_of("p3")


def test_an_event_naming_a_passenger_who_is_not_aboard_is_skipped() -> None:
    trip = start_trip(
        base()
        .event("drop_me_here", 6, passengers=["p3"])
        .event("change_request", 12, passengers=["p1"], amount=1000)
        .build()
    )
    step_to_seconds(trip, 13)
    assert trip.state.events_fired == [True, True, True]
    assert passenger(trip, "p3").deadline_ms is None
    assert trip.state.change_requests == {}


def test_a_second_change_request_while_one_is_open_is_skipped() -> None:
    trip = start_trip(
        base()
        .event("change_request", 6, passengers=["p2"], amount=1000)
        .event("change_request", 7, passengers=["p2"], amount=2000)
        .build()
    )
    step_to_seconds(trip, 8)
    assert trip.state.events_fired == [True, True, True]
    assert trip.state.change_requests == {"p2": ChangeRequest(note_piasters=1000)}
