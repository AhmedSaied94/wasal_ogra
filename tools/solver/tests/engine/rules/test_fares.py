"""Fares and payments (RULES.md §6.1 to §6.4) and fares collected (§11), ported from
`test/rules/fares_test.dart`.

Dart's `FareSent` event is read from the new fare token; the `pays` and `pays_rest` speech isn't
mirrored (research R3).
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import Tap
from wassal_solver.engine.model import DRIVER, TokenKind, TripStatus
from wassal_solver.engine.money import Pieces


def paying(
    payment: list[int], *, fare: int = 850, archetype: str = "regular", discount: int = 0
) -> Trip:
    trip = start_trip(
        TripBuilder()
        .rules(student_discount_pct=discount)
        .station("kobri", 30, fare=fare)
        .passenger("p1", archetype=archetype, seat="A_r", dest="kobri", payment=payment, pays_at=0)
        .build()
    )
    trip.step()
    return trip


def test_the_fare_is_the_destinations_fare() -> None:
    p1 = passenger(paying([1000]), "p1")
    assert p1.fare_sent
    assert p1.fare_piasters == 850
    assert p1.balance == 150


def test_a_students_fare_is_discounted_and_rounded_up_to_50() -> None:
    def fare(station_fare: int, discount: int) -> int | None:
        trip = paying([1000], fare=station_fare, archetype="student", discount=discount)
        return passenger(trip, "p1").fare_piasters

    assert fare(850, 50) == 450
    assert fare(700, 50) == 350
    assert fare(850, 0) == 850
    assert fare(850, 100) == 0


def test_only_students_get_the_discount() -> None:
    assert passenger(paying([1000], discount=50), "p1").fare_piasters == 850


def test_paying_sends_the_authored_pieces_and_fixes_the_balance() -> None:
    owed = paying([1000])
    (token,) = owed.state.tokens.values()
    assert token.pieces == Pieces.of({1000: 1})
    assert token.kind is TokenKind.FARE
    assert passenger(owed, "p1").balance == 150
    assert passenger(paying([500, 100, 100, 100, 50]), "p1").balance == 0
    assert passenger(paying([500]), "p1").balance == -350


def test_paying_creates_the_fare_token() -> None:
    # Dart checks the `FareSent` event and the `pays` speech; the token carries the same facts.
    trip = paying([1000])
    token = trip.state.tokens[1]
    assert (token.owner, token.target, token.pieces.total) == ("p1", DRIVER, 1000)
    assert token.hop_to == DRIVER, "it starts hopping in the step it is sent"


def test_a_tap_on_a_passenger_who_owes_makes_them_pay_the_rest_in_the_fewest_pieces() -> None:
    trip = paying([500])
    ok(trip, Tap("p1"))
    rest = trip.state.tokens[2]
    assert (rest.kind, rest.owner, rest.target) == (TokenKind.FARE, "p1", DRIVER)
    assert rest.pieces.total == 350
    assert rest.pieces == Pieces.of({100: 3, 50: 1})
    assert passenger(trip, "p1").balance == 0


def test_fares_collected_is_the_sum_of_min_fare_paid_in() -> None:
    trip = start_trip(
        TripBuilder()
        .station("kobri", 10, fare=850)
        .passenger("p1", seat="A_r", dest="kobri", payment=[500, 100, 100, 100, 50], pays_at=0)
        .passenger("p2", seat="A_m", dest="kobri", payment=[500], pays_at=0)
        .passenger("p3", seat="A_l", dest="kobri", payment=[1000])
        .build()
    )
    step_to_seconds(trip, 20)
    assert trip.status is TripStatus.FINISHED
    assert trip.result is not None
    assert trip.result.fares_collected_piasters == 850 + 500
    assert trip.result.lost_fares == 1
