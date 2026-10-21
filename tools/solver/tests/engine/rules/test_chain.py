"""The passing chain (RULES.md §5.1 to §5.5, §5.8), ported from `test/rules/chain_test.dart`:
routing, hop length, blocking, and the tokens of a passenger who gets off.

The mirror has no events (research R3). Dart's `TokenHopStarted`, `TokenBlocked` and
`MoneyArrivedAtDriver` are read from the state instead: a hop that has just started has
`hop_elapsed_ms == 0`, a blocked token has `blocked_by`, and an arrival removes the token and fills
the tray.
"""

from __future__ import annotations

from typing import Any

from wassal_content.models import LineId, VehicleId

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, set_alertness, start_trip
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, SendHand
from wassal_solver.engine.model import DRIVER, Alertness, TokenKind, TripStatus


def column() -> list[dict[str, Any]]:
    """One column, rows front to D: front_r, A_r, B_r, C_r, D_r."""
    return [
        {
            "seat_id": f"{row}_r",
            "row": row,
            "col": "r",
            "reachable_by_driver": row in ("front", "A"),
        }
        for row in ("front", "A", "B", "C", "D")
    ]


def trace(trip: Trip, until_ms: int) -> dict[int, list[str]]:
    """Steps to `until_ms` one step at a time, and returns each token's hops as `from>to`, in the
    order they started (Dart's `TokenHopStarted`)."""
    hops: dict[int, list[str]] = {}
    while trip.status is TripStatus.RUNNING and trip.t_ms < until_ms:
        trip.step()
        for token in trip.state.tokens.values():
            if token.hop_to is not None and token.hop_elapsed_ms == 0:
                hops.setdefault(token.token_id, []).append(f"{token.holder}>{token.hop_to}")
    return hops


class TestRoutingTowardTheDriver:
    def test_from_row_d_through_each_occupied_seat_ahead_skipping_empty_c(self) -> None:
        trip = start_trip(
            TripBuilder()
            .seats(column())
            .station("gamaa", 60)
            .passenger("pD", seat="D_r", dest="gamaa", payment=[1000], pays_at=0)
            .passenger("pB", seat="B_r", dest="gamaa", payment=[1000])
            .passenger("pA", seat="A_r", dest="gamaa", payment=[1000])
            .passenger("pF", seat="front_r", dest="gamaa", payment=[1000])
            .build()
        )
        assert trace(trip, 10_000)[1] == ["pD>pB", "pB>pA", "pA>DRIVER"]
        assert 1 not in trip.state.tokens
        assert trip.state.tray.count(1000) == 1
        assert passenger(trip, "pD").paid_in == 1000

    def test_rows_front_and_a_hand_straight_to_the_driver(self) -> None:
        trip = start_trip(
            TripBuilder()
            .seats(column())
            .station("gamaa", 60)
            .passenger("pF", seat="front_r", dest="gamaa", payment=[1000], pays_at=0)
            .passenger("pA", seat="A_r", dest="gamaa", payment=[1000], pays_at=0)
            .build()
        )
        hops = trace(trip, 5000)
        assert hops[1] == ["pF>DRIVER"]
        assert hops[2] == ["pA>DRIVER"]

    def test_with_every_seat_ahead_empty_row_c_hands_to_the_driver(self) -> None:
        trip = start_trip(
            TripBuilder()
            .station("gamaa", 60)
            .passenger("p1", seat="C_m", dest="gamaa", payment=[1000], pays_at=0)
            .passenger("p2", seat="B_r", dest="gamaa", payment=[1000])
            .build()
        )
        assert trace(trip, 5000)[1] == ["p1>DRIVER"]


class TestRoutingTowardAPassenger:
    def test_from_the_driver_through_each_occupied_seat_of_their_column(self) -> None:
        trip = start_trip(
            TripBuilder()
            .seats(column())
            .station("gamaa", 60)
            .passenger("pD", seat="D_r", dest="gamaa", payment=[1000])
            .passenger("pB", seat="B_r", dest="gamaa", payment=[1000])
            .passenger("pA", seat="A_r", dest="gamaa", payment=[1000])
            .build()
        )
        ok(trip, PickFromTray(100))
        ok(trip, SendHand("pD"))
        assert trace(trip, 10_000)[1] == ["DRIVER>pA", "pA>pB", "pB>pD"]

    def test_rows_front_and_a_are_one_hop_from_the_driver(self) -> None:
        trip = start_trip(
            TripBuilder()
            .station("gamaa", 60)
            .passenger("p1", seat="front_r", dest="gamaa", payment=[1000])
            .passenger("p2", seat="A_m", dest="gamaa", payment=[1000])
            .build()
        )
        ok(trip, PickFromTray(100))
        ok(trip, SendHand("p1"))
        ok(trip, PickFromTray(100))
        ok(trip, SendHand("p2"))
        hops = trace(trip, 5000)
        assert hops[1] == ["DRIVER>p1"]
        assert hops[2] == ["DRIVER>p2"]


class TestTheNextHolderIsWorkedOutAtEachHop:
    @staticmethod
    def trip(*, middle: str) -> TripBuilder:
        boards = middle == "boards"
        return (
            TripBuilder()
            .station("kobri", 3)
            .station("gamaa", 60)
            .passenger("p1", seat="C_r", dest="gamaa", payment=[1000])
            .passenger("p2", seat="A_r", dest="gamaa", payment=[1000])
            .passenger(
                "p3",
                seat="B_r",
                dest="gamaa" if boards else "kobri",
                board="kobri" if boards else None,
                payment=[1000],
            )
        )

    @staticmethod
    def send_at_1980(builder: TripBuilder) -> list[str]:
        trip = start_trip(builder.build())
        trip.step_to(1980)
        ok(trip, PickFromTray(100))
        ok(trip, SendHand("p1"))
        return trace(trip, 8000)[1]

    def test_a_seat_that_fills_mid_transit_joins_the_chain(self) -> None:
        assert self.send_at_1980(self.trip(middle="boards")) == ["DRIVER>p2", "p2>p3", "p3>p1"]

    def test_a_seat_that_empties_mid_transit_leaves_it(self) -> None:
        assert self.send_at_1980(self.trip(middle="leaves")) == ["DRIVER>p2", "p2>p1"]


def test_a_1300_ms_hop_takes_40_steps() -> None:
    trip = start_trip(
        TripBuilder(vehicle=VehicleId.TUKTUK, line=LineId.LINE_HAY)
        .station("madrasa", 30)
        .passenger("p1", seat="A_r", dest="madrasa", payment=[1000], pays_at=0)
        .build()
    )
    trip.step()
    (token,) = trip.state.tokens.values()
    assert (trip.t_ms, token.hop_to, token.hop_elapsed_ms, token.hop_duration_ms) == (
        33,
        DRIVER,
        0,
        1300,
    )
    trip.step_to(33 + 39 * 33)
    assert 1 in trip.state.tokens, "not arrived yet"
    trip.step()
    assert trip.t_ms == 33 + 40 * 33
    assert 1 not in trip.state.tokens
    assert passenger(trip, "p1").paid_in == 1000


def test_the_hop_keeps_its_elapsed_time_for_the_progress() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 60)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=0)
        .build()
    )
    trip.step_to(33 + 10 * 33)
    (token,) = trip.state.tokens.values()
    # Dart reports `progressPermille` to the scene; the mirror keeps what it is computed from.
    assert (token.hop_elapsed_ms, token.hop_duration_ms) == (330, 1100)
    assert token.hop_elapsed_ms * 1000 // token.hop_duration_ms == 330 * 1000 // 1100


class TestBlocking:
    @staticmethod
    def start() -> Trip:
        return start_trip(
            TripBuilder()
            .station("gamaa", 60)
            .passenger("p1", seat="B_r", dest="gamaa", payment=[1000], pays_at=0)
            .passenger("p2", seat="A_r", dest="gamaa", payment=[1000])
            .build()
        )

    def test_an_unable_next_holder_blocks_and_the_hop_starts_once_they_are_able(self) -> None:
        trip = self.start()
        set_alertness(trip, "p2", Alertness.ASLEEP)
        assert trace(trip, 2000) == {}
        (token,) = trip.state.tokens.values()
        assert (token.token_id, token.blocked_by, token.holder, token.hop_to) == (
            1,
            "p2",
            "p1",
            None,
        )
        set_alertness(trip, "p2", Alertness.AWAKE)
        assert trace(trip, trip.t_ms + 33) == {1: ["p1>p2"]}
        assert token.blocked_by is None

    def test_an_unable_holder_blocks_the_token_it_holds(self) -> None:
        trip = self.start()
        # One step before the fare reaches p2; a hop in progress always ends.
        trip.step_to(33 + 33 * 33)
        set_alertness(trip, "p2", Alertness.ASLEEP)
        trip.step_to(5000)
        (token,) = trip.state.tokens.values()
        assert token.holder == "p2"
        assert token.blocked_by == "p2"
        assert token.hop_to is None

    def test_an_unable_target_blocks_its_change(self) -> None:
        trip = self.start()
        set_alertness(trip, "p2", Alertness.ASLEEP)
        ok(trip, PickFromTray(100))
        ok(trip, SendHand("p2"))
        trip.step_to(1000)
        change = trip.state.tokens[1]
        assert change.kind is TokenKind.CHANGE
        assert (change.holder, change.blocked_by, change.hop_to) == (DRIVER, "p2", None)
        # Dart checks token 2, p1's fare, which p2 blocks too as its next holder.
        fare = trip.state.tokens[2]
        assert (fare.kind, fare.holder, fare.blocked_by) == (TokenKind.FARE, "p1", "p2")


class TestAPassengerWhoGetsOff:
    @staticmethod
    def trip() -> TripBuilder:
        return (
            TripBuilder()
            .station("kobri", 1)
            .station("gamaa", 60)
            .passenger("p1", seat="C_r", dest="gamaa", payment=[1000], pays_at=0)
            .passenger("p2", seat="B_r", dest="kobri", payment=[500, 100, 100, 100, 50], pays_at=30)
        )

    def test_hands_the_driver_what_they_hold_or_are_about_to_receive(self) -> None:
        trip = start_trip(self.trip().build())
        assert trace(trip, 990) == {1: ["p1>p2"]}
        assert trip.state.tokens[1].hop_to == "p2"
        trip.step()
        assert trip.t_ms == 1023
        assert passenger(trip, "p1").paid_in == 1000
        assert trip.state.tokens == {}
        assert trip.state.tray.count(1000) == 1

    def test_sends_the_tokens_addressed_to_them_back_to_the_tray(self) -> None:
        trip = start_trip(
            self.trip().passenger("p3", seat="A_l", dest="gamaa", payment=[1000]).build()
        )
        tray = trip.state.tray
        ok(trip, PickFromTray(100))
        ok(trip, SendHand("p2"))
        trip.step_to(1023)
        assert [t for t in trip.state.tokens.values() if t.kind is TokenKind.CHANGE] == []
        assert trip.state.tray.plus(trip.state.hand).count(100) == tray.count(100)
