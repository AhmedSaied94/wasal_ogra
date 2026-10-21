"""The bump (RULES.md §8, §5.7, §3 step 2.5), ported from `bump_test.dart`: every mid-hop token
falls to the floor for `trip_bump_collect_ms` (3 s).

line_gamaa: p1 in A_r pays 1000 at 1 s; the fare hops from 1023 to 2145. The mirror has no events
(research R3), so each Dart event is checked through the state it leaves.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, rejects, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import CollectDropped, PickFromTray, RejectionCode, SendHand
from wassal_solver.engine.model import TokenKind, TripStatus


def bumped(bump_at: int, *, archetype: str = "regular", station: int = 30) -> Trip:
    return start_trip(
        TripBuilder()
        .station("gamaa", station)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1, archetype=archetype)
        .event("bump", bump_at)
        .build()
    )


def send_change(trip: Trip, pieces: list[int]) -> None:
    """Sends `pieces` to p1 once the fare is in, at 2145; the change hops from 2178 to 3300."""
    trip.step_to(2145)
    for piece in pieces:
        ok(trip, PickFromTray(piece))
    ok(trip, SendHand("p1"))


def test_only_mid_hop_tokens_drop() -> None:
    trip = bumped(2)
    trip.step_to(1980)
    assert trip.state.events_fired == [False]
    trip.step_to(2013)
    assert trip.state.events_fired == [True]
    assert list(trip.state.tokens) == [1]
    token = trip.state.tokens[1]
    assert (token.is_dropped, token.hop_to, token.dropped_until_ms) == (True, None, 5013)


def test_a_held_token_stays_where_it_is() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="C_r", dest="gamaa", payment=[1000], pays_at=1)
        .passenger("p2", seat="B_r", dest="gamaa", payment=[500, 100, 100], archetype="sleeper")
        .event("bump", 2)
        .build()
    )
    step_to_seconds(trip, 3)
    token = trip.state.tokens[1]
    assert token.dropped_until_ms is None
    assert token.blocked_by == "p2"


class TestCollectedInTime:
    def test_a_fare_arrives_at_the_driver(self) -> None:
        trip = bumped(2)
        step_to_seconds(trip, 3)
        tray = trip.state.tray.total
        ok(trip, CollectDropped(1))
        assert trip.state.tray.total == tray + 1000
        assert passenger(trip, "p1").paid_in == 1000
        assert 1 not in trip.state.tokens

    def test_change_goes_to_the_tray_and_the_passenger_is_still_owed(self) -> None:
        trip = bumped(3)
        send_change(trip, [100, 100, 100])
        step_to_seconds(trip, 4)
        assert trip.state.tokens[2].is_dropped
        tray = trip.state.tray.total
        ok(trip, CollectDropped(2))
        assert trip.state.tray.total == tray + 300
        assert passenger(trip, "p1").balance == 300

    def test_an_honest_passengers_return_goes_to_the_tray(self) -> None:
        trip = bumped(4, archetype="honest")
        send_change(trip, [500])
        step_to_seconds(trip, 5)
        assert trip.state.tokens[3].kind == TokenKind.RETURNED
        assert trip.state.tokens[3].is_dropped
        tray = trip.state.tray.total
        ok(trip, CollectDropped(3))
        assert trip.state.tray.total == tray + 200
        step_to_seconds(trip, 40)
        assert trip.result is not None
        assert trip.result.overpaid_piasters == 0


class TestLostAfterTheDeadline:
    def test_a_lost_fare_never_counts_but_its_balance_stands(self) -> None:
        trip = bumped(2)
        trip.step_to(4983)
        assert 1 in trip.state.tokens
        trip.step_to(5016)
        assert 1 not in trip.state.tokens
        p1 = passenger(trip, "p1")
        assert (p1.fare_sent, p1.balance, p1.paid_in) == (True, 300, 0)
        step_to_seconds(trip, 40)
        assert trip.result is not None
        assert trip.result.fares_collected_piasters == 0

    def test_a_lost_return_is_overpaid(self) -> None:
        trip = bumped(4, archetype="honest")
        send_change(trip, [500])
        trip.step_to(6996)
        assert 3 in trip.state.tokens
        trip.step_to(7029)
        assert 3 not in trip.state.tokens
        step_to_seconds(trip, 40)
        assert trip.result is not None
        assert trip.result.overpaid_piasters == 200

    def test_lost_change_is_gone_and_the_passenger_is_still_owed(self) -> None:
        trip = bumped(3)
        send_change(trip, [100, 100, 100])
        tray = trip.state.tray.total
        trip.step_to(6006)
        assert trip.state.tokens == {}
        assert trip.state.tray.total == tray
        assert passenger(trip, "p1").balance == 300


def test_collect_dropped_on_a_token_that_is_not_dropped_has_no_effect() -> None:
    trip = bumped(20)
    trip.step_to(1023)
    rejects(trip, CollectDropped(1), RejectionCode.NO_EFFECT)
    rejects(trip, CollectDropped(9), RejectionCode.NO_EFFECT)


def test_a_dropped_token_at_the_end_of_the_trip_is_lost() -> None:
    trip = bumped(2, station=4)
    trip.step_to(3993)
    assert trip.state.tokens[1].is_dropped
    step_to_seconds(trip, 10)
    assert trip.status == TripStatus.FINISHED
    assert trip.state.tokens == {}
    assert trip.result is not None
    assert trip.result.duration_ms == 4026
    assert trip.result.fares_collected_piasters == 0
    assert passenger(trip, "p1").paid_in == 0
