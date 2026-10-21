"""Paying on schedule or when tapped (RULES.md §3 step 4, §4.5 cases 4 and 6, M01 clarification
4), ported from `tap_pay_test.dart`. A `FareSent` event is checked as the fare token it creates.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, rejects, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import RejectionCode, Tap
from wassal_solver.engine.model import TokenKind
from wassal_solver.engine.money import Pieces


def _trip(*, pays_at: int | None = None, payment: tuple[int, ...] = (1000,)) -> Trip:
    return start_trip(
        TripBuilder()
        .station("kobri", 30, fare=850)
        .passenger("p1", seat="A_r", dest="kobri", payment=list(payment), pays_at=pays_at)
        .build()
    )


def _fares(trip: Trip) -> list[int]:
    """The totals of the fare tokens in flight."""
    return [t.pieces.total for t in trip.state.tokens.values() if t.kind is TokenKind.FARE]


def test_a_passenger_pays_at_pays_at_seconds() -> None:
    trip = _trip(pays_at=5)
    trip.step_to(4983)
    assert not passenger(trip, "p1").fare_sent
    assert _fares(trip) == []
    trip.step()
    assert trip.t_ms == 5016
    assert passenger(trip, "p1").fare_sent
    assert _fares(trip) == [1000]


def test_a_tap_before_that_time_pays_at_once_and_only_once() -> None:
    trip = _trip(pays_at=5)
    trip.step_to(990)
    ok(trip, Tap("p1"))
    assert _fares(trip) == [1000]
    assert trip.state.next_token_id == 2
    step_to_seconds(trip, 20)
    assert trip.state.next_token_id == 2, "no second fare"
    assert passenger(trip, "p1").fare_sent


def test_a_passenger_with_no_payment_time_pays_only_when_tapped() -> None:
    trip = _trip()
    step_to_seconds(trip, 20)
    assert trip.state.next_token_id == 1
    assert not passenger(trip, "p1").fare_sent
    ok(trip, Tap("p1"))
    assert _fares(trip) == [1000]


def test_a_tap_on_a_passenger_who_owes_makes_them_pay_the_rest() -> None:
    trip = _trip(pays_at=0, payment=(500,))
    trip.step()
    assert passenger(trip, "p1").balance == -350
    ok(trip, Tap("p1"))
    rest = trip.state.tokens[2]
    assert (rest.kind, rest.pieces) == (TokenKind.FARE, Pieces.of({100: 3, 50: 1}))
    assert passenger(trip, "p1").balance == 0
    step_to_seconds(trip, 5)
    assert passenger(trip, "p1").paid_in == 850


def test_a_tap_on_a_passenger_who_is_not_aboard_is_rejected() -> None:
    rejects(_trip(), Tap("p9"), RejectionCode.NOT_ABOARD)
