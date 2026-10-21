"""Headphones (RULES.md §2.4, §3 step 2.3, §4.5 case 3), ported from `headphones_test.dart`: muted
until called twice, then attentive for `trip_headphones_attentive_ms` (15 s).

The events are checked as the state they leave; speech isn't mirrored (research R3).
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, SendHand, Tap
from wassal_solver.engine.model import Alertness, TokenKind


def _headphones(*, pays_at: int | None = 1) -> Trip:
    return start_trip(
        TripBuilder()
        .station("gamaa", 60)
        .passenger(
            "p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=pays_at, archetype="headphones"
        )
        .build()
    )


def _alert(trip: Trip) -> tuple[Alertness, int | None, int]:
    p1 = passenger(trip, "p1")
    return p1.alertness, p1.alert_until_ms, p1.taps


def test_they_start_muted_and_the_second_tap_makes_them_attentive_for_15_s() -> None:
    trip = _headphones()
    assert passenger(trip, "p1").alertness == Alertness.MUTED
    ok(trip, Tap("p1"))
    assert _alert(trip) == (Alertness.MUTED, None, 1)
    ok(trip, Tap("p1"))
    assert _alert(trip) == (Alertness.ATTENTIVE, 15000, 0)


def test_then_they_are_muted_again_with_taps_reset() -> None:
    trip = _headphones()
    for _ in range(3):
        ok(trip, Tap("p1"))
    trip.step_to(14982)
    assert passenger(trip, "p1").alertness == Alertness.ATTENTIVE
    trip.step()
    assert trip.t_ms == 15015
    assert _alert(trip) == (Alertness.MUTED, None, 0)


def test_while_muted_a_tap_never_asks_for_the_fare() -> None:
    trip = _headphones(pays_at=None)
    ok(trip, Tap("p1"))
    ok(trip, Tap("p1"))
    assert not passenger(trip, "p1").fare_sent
    assert trip.state.tokens == {}
    ok(trip, Tap("p1"))
    (fare,) = trip.state.tokens.values()
    assert (fare.kind, fare.owner) == (TokenKind.FARE, "p1")


def test_their_scheduled_payment_waits_until_they_are_attentive() -> None:
    trip = _headphones()
    step_to_seconds(trip, 5)
    assert not passenger(trip, "p1").fare_sent
    ok(trip, Tap("p1"))
    ok(trip, Tap("p1"))
    trip.step()
    assert trip.t_ms == 5049
    assert passenger(trip, "p1").fare_sent


def test_muted_as_a_middle_holder_they_block_the_chain() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 60)
        .passenger("p1", seat="C_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
        .passenger("p2", seat="B_r", dest="gamaa", payment=[500, 100, 100], archetype="headphones")
        .build()
    )
    step_to_seconds(trip, 4)
    (fare,) = trip.state.tokens.values()
    assert (fare.holder, fare.blocked_by) == ("p1", "p2")
    ok(trip, Tap("p2"))
    ok(trip, Tap("p2"))
    trip.step()
    assert (fare.blocked_by, fare.hop_to) == (None, "p2")


def test_muted_again_as_the_target_they_block_their_change() -> None:
    # Attentive from 0 to 15 s: they pay 1000 at 1023 and go muted at 15015.
    trip = _headphones()
    ok(trip, Tap("p1"))
    ok(trip, Tap("p1"))
    step_to_seconds(trip, 16)
    for piece in (100, 100, 100):
        ok(trip, PickFromTray(piece))
    ok(trip, SendHand("p1"))
    step_to_seconds(trip, 20)
    (change,) = trip.state.tokens.values()
    assert change.blocked_by == "p1"
    assert passenger(trip, "p1").balance == 300, "not delivered"
