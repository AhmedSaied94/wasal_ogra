"""drop_me_here (RULES.md §3 step 8.1, §8, §9.2, §9.3), ported from `drop_me_here_test.dart`: a
passenger gets off at their deadline instead of their station.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, SendHand
from wassal_solver.engine.model import AlightOutcome, Presence


def dropping(*, seconds: int | None = None) -> Trip:
    """p1 in A_r owes 300 from 1023; p2 boards at kobri (10 s) into A_r once p1 has left it; p3
    rides to gamaa in A_m."""
    return start_trip(
        TripBuilder()
        .station("kobri", 10)
        .station("gamaa", 40)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1)
        .passenger("p2", seat="A_r", board="kobri", dest="gamaa", payment=[500, 100, 100])
        .passenger("p3", seat="A_m", dest="gamaa", payment=[500, 100, 100])
        .event("drop_me_here", 5, passengers=["p1"], seconds=seconds)
        .build()
    )


def test_the_deadline_is_t_plus_seconds() -> None:
    trip = dropping(seconds=10)
    step_to_seconds(trip, 6)
    # Dart also checks the drop_me_here speech, which isn't mirrored.
    assert passenger(trip, "p1").deadline_ms == 5016 + 10000


def test_without_seconds_it_is_t_plus_the_station_warning() -> None:
    trip = dropping()
    step_to_seconds(trip, 6)
    assert passenger(trip, "p1").deadline_ms == 5016 + 8000


def test_at_the_deadline_they_get_off_as_at_a_stop_and_the_seat_is_taken() -> None:
    trip = dropping(seconds=10)
    trip.step_to(15015)
    assert passenger(trip, "p1").presence == Presence.ABOARD
    assert passenger(trip, "p2").presence == Presence.WAITING
    trip.step_to(15048)
    p1 = passenger(trip, "p1")
    assert (p1.presence, p1.outcome) == (Presence.GONE, AlightOutcome.FIGHT)
    assert trip.state.counters.fights == 1
    assert trip.result is None
    p2 = passenger(trip, "p2")
    assert (p2.presence, p2.pickup_due) == (Presence.ABOARD, False)


def test_tokens_are_handed_over_at_the_deadline() -> None:
    trip = dropping(seconds=10)
    step_to_seconds(trip, 14)
    for piece in (100, 100):
        ok(trip, PickFromTray(piece))
    ok(trip, SendHand("p1"))
    tray = trip.state.tray.total
    trip.step_to(15048)
    assert trip.state.tokens == {}
    assert trip.state.tray.total == tray + 200


def test_they_leave_before_their_station() -> None:
    trip = dropping(seconds=30)
    step_to_seconds(trip, 33)
    # Dart checks that gamaa's warning (at 32 s) lists p3 and not p1, from the StationWarning
    # event, which isn't mirrored. The state keeps that the warning fired, and p1 is still aboard
    # until the deadline, 35016, before gamaa.
    assert trip.state.schedule[1].warned
    assert passenger(trip, "p1").presence == Presence.ABOARD
    trip.step_to(35046)
    assert passenger(trip, "p1").presence == Presence.GONE
    assert passenger(trip, "p3").presence == Presence.ABOARD
