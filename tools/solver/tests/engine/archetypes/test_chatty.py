"""Chatty (RULES.md §5.4), ported from `chatty_test.dart`: while able, a chatty passenger slows
every hop out of a seat in their row to `scale(trip_hop_ms, trip_hop_pct_chatty_row)`.

The hop events are checked as the hops the tokens start (research R3).
"""

from __future__ import annotations

from tests.engine.archetypes.watch import hops
from tests.support.builders import TripBuilder
from tests.support.scripts import set_alertness, start_trip
from wassal_solver.engine import Trip
from wassal_solver.engine.model import Alertness


def _row(*, middle: str = "regular", chatty_dest: str = "gamaa") -> TripBuilder:
    """p1 in C_r pays; p3 in B_r passes it on; the chatty p2 sits in B_m."""
    return (
        TripBuilder()
        .station("kobri", 2)
        .station("gamaa", 60)
        .passenger("p1", seat="C_r", dest="gamaa", payment=[500, 100, 100], pays_at=5)
        .passenger("p2", seat="B_m", dest=chatty_dest, payment=[500, 100, 100], archetype="chatty")
        .passenger("p3", seat="B_r", dest="gamaa", payment=[500, 100, 100], archetype=middle)
    )


def _fare_hops(trip: Trip) -> list[tuple[str, int]]:
    return hops(trip, 15000, token_id=1)


def test_hops_out_of_a_seat_in_their_row_are_slower_others_are_not() -> None:
    trip = start_trip(_row().build())
    assert _fare_hops(trip) == [("p1>p3", 1100), ("p3>DRIVER", 1650)]


def test_the_multiplier_stacks_after_the_hajja() -> None:
    trip = start_trip(_row(middle="hajja").build())
    assert _fare_hops(trip) == [("p1>p3", 1100), ("p3>DRIVER", 3300)]


def test_it_does_not_apply_while_the_chatty_passenger_is_not_able() -> None:
    trip = start_trip(_row().build())
    set_alertness(trip, "p2", Alertness.ASLEEP)
    assert _fare_hops(trip) == [("p1>p3", 1100), ("p3>DRIVER", 1100)]


def test_it_does_not_apply_after_they_get_off() -> None:
    trip = start_trip(_row(chatty_dest="kobri").build())
    assert _fare_hops(trip) == [("p1>p3", 1100), ("p3>DRIVER", 1100)]
