"""The regular customer's tip (RULES.md §9.3), the big note and the student (§6.1, §7.1), ported
from `regular_customer_test.dart`.

The tip's speech isn't mirrored (research R3); its amount is checked in the counters.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, SendHand
from wassal_solver.engine.model import AlightOutcome


def _one(
    archetype: str,
    *,
    payment: tuple[int, ...] = (500, 100, 100),
    fare: int = 700,
    student_discount_pct: int = 0,
) -> Trip:
    return start_trip(
        TripBuilder()
        .station("gamaa", 30, fare=fare)
        .passenger(
            "p1", seat="A_r", dest="gamaa", payment=list(payment), pays_at=1, archetype=archetype
        )
        .rules(student_discount_pct=student_discount_pct)
        .build()
    )


def test_thanked_and_not_impatient_a_regular_customer_tips() -> None:
    trip = _one("regular_customer")
    step_to_seconds(trip, 40)
    assert trip.state.counters.tips_piasters == trip.params.trip_tip_piasters_regular_customer
    result = trip.result
    assert result is not None
    assert result.tips_piasters == 200
    assert result.earnings_jenehat == 9, "fare 700 plus the 200 tip"


def test_an_impatient_regular_customer_tips_nothing() -> None:
    trip = _one("regular_customer", payment=(1000,))
    step_to_seconds(trip, 22)
    assert passenger(trip, "p1").impatient
    for piece in (100, 100, 100):
        ok(trip, PickFromTray(piece))
    ok(trip, SendHand("p1"))
    step_to_seconds(trip, 40)
    assert passenger(trip, "p1").outcome == AlightOutcome.THANKED
    assert trip.result is not None
    assert trip.result.tips_piasters == 0


def test_a_regular_customer_who_fights_tips_nothing() -> None:
    trip = _one("regular_customer", payment=(1000,))
    step_to_seconds(trip, 40)
    assert passenger(trip, "p1").outcome == AlightOutcome.FIGHT
    assert trip.result is not None
    assert trip.result.tips_piasters == 0


def test_a_big_note_paying_20000_on_a_700_fare_is_owed_19300() -> None:
    trip = _one("big_note", payment=(20000,))
    trip.step_to(1023)
    assert passenger(trip, "p1").balance == 19300


def test_a_students_discount_applies_to_their_fare_850_at_50_pct_is_450() -> None:
    trip = _one("student", payment=(1000,), fare=850, student_discount_pct=50)
    trip.step_to(1023)
    assert passenger(trip, "p1").fare_piasters == 450
    assert passenger(trip, "p1").balance == 550
