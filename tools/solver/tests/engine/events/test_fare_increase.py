"""fare_increase (RULES.md §6.1, §6.2, §8), ported from `fare_increase_test.dart`: fares not yet
sent rise; listed passengers pay the old fare and owe the rest.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import Tap
from wassal_solver.engine.model import AlightOutcome, TokenKind


def increased() -> Trip:
    """+100 at 2 s, with p2 listed. p3 has paid before it."""
    return start_trip(
        TripBuilder()
        .station("gamaa", 40)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100], pays_at=5)
        .passenger("p2", seat="A_m", dest="gamaa", payment=[500, 100, 100], pays_at=6)
        .passenger("p3", seat="A_l", dest="gamaa", payment=[1000], pays_at=1)
        .event("fare_increase", 2, amount=100, passengers=["p2"])
        .build()
    )


def fares_of(trip: Trip, passenger_id: str) -> list[int]:
    return [
        token.pieces.total
        for token in trip.state.tokens.values()
        if token.kind == TokenKind.FARE and token.owner == passenger_id
    ]


def test_the_increase_and_the_listed_passengers_are_kept() -> None:
    trip = increased()
    step_to_seconds(trip, 3)
    assert trip.state.fare_increase_piasters == 100
    assert trip.state.old_fare_payers == {"p2"}


def test_an_unlisted_passenger_whose_payment_is_short_tops_it_up() -> None:
    trip = increased()
    step_to_seconds(trip, 6)
    assert fares_of(trip, "p1") == [800]
    p1 = passenger(trip, "p1")
    assert (p1.fare_piasters, p1.balance) == (800, 0)


def test_a_listed_passenger_pays_the_old_fare_and_owes_the_difference() -> None:
    trip = increased()
    step_to_seconds(trip, 7)
    # Dart also checks the speech (pays_old_fare, then pays_rest), which isn't mirrored.
    assert fares_of(trip, "p2") == [700]
    assert passenger(trip, "p2").balance == -100
    ok(trip, Tap("p2"))
    assert fares_of(trip, "p2") == [700, 100]
    assert passenger(trip, "p2").balance == 0


def test_fares_already_sent_do_not_change() -> None:
    trip = increased()
    step_to_seconds(trip, 7)
    p3 = passenger(trip, "p3")
    assert (p3.fare_piasters, p3.balance) == (700, 300)


def test_the_unpaid_remainder_at_the_stop_is_missing_from_fares_collected() -> None:
    trip = increased()
    step_to_seconds(trip, 50)
    assert passenger(trip, "p2").outcome == AlightOutcome.THANKED
    assert trip.result is not None
    assert trip.result.fares_collected_piasters == 800 + 700 + 700
