"""PickFromTray, ReturnHand and SendHand (RULES.md §4.1 to §4.3), ported from
`hand_commands_test.dart`. The `ChangeSent` event is checked as the token it creates.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, rejects, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, RejectionCode, ReturnHand, SendHand
from wassal_solver.engine.model import LastSend, Presence


def _trip() -> Trip:
    return start_trip(
        TripBuilder()
        .tray({100: 2, 50: 1})
        .station("kobri", 1)
        .station("gamaa", 60)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000])
        .passenger("p2", seat="A_m", dest="gamaa", board="kobri", payment=[1000])
        .passenger("p3", seat="A_l", dest="kobri", payment=[1000])
        .build()
    )


class TestPickFromTray:
    def test_moves_one_piece_from_the_tray_to_the_hand(self) -> None:
        trip = _trip()
        ok(trip, PickFromTray(100))
        assert trip.state.tray.to_json() == {"50": 1, "100": 1}
        assert trip.state.hand.to_json() == {"100": 1}

    def test_is_rejected_for_a_denomination_the_tray_lacks_or_that_does_not_exist(self) -> None:
        trip = _trip()
        rejects(trip, PickFromTray(500), RejectionCode.TRAY_EMPTY)
        rejects(trip, PickFromTray(300), RejectionCode.BAD_ARGUMENT)
        ok(trip, PickFromTray(50))
        rejects(trip, PickFromTray(50), RejectionCode.TRAY_EMPTY)


class TestReturnHand:
    def test_puts_the_whole_hand_back(self) -> None:
        trip = _trip()
        ok(trip, PickFromTray(100))
        ok(trip, PickFromTray(50))
        ok(trip, ReturnHand())
        assert trip.state.hand.is_empty
        assert trip.state.tray.to_json() == {"50": 1, "100": 2}

    def test_is_rejected_with_an_empty_hand(self) -> None:
        rejects(_trip(), ReturnHand(), RejectionCode.HAND_EMPTY)


class TestSendHand:
    def test_creates_a_change_token_from_the_driver_and_clears_the_hand(self) -> None:
        trip = _trip()
        trip.step_to(330)
        ok(trip, PickFromTray(100))
        ok(trip, PickFromTray(50))
        ok(trip, SendHand("p1"))
        (token,) = trip.state.tokens.values()
        assert token.to_json() == {
            "token_id": 1,
            "kind": "change",
            "pieces": {"50": 1, "100": 1},
            "owner": "p1",
            "target": "p1",
            "holder": "DRIVER",
            "hops_done": 0,
        }
        assert token.pieces.total == 150
        assert trip.state.hand.is_empty
        assert trip.state.last_send == LastSend(token_id=1, until_ms=1330)

    def test_is_rejected_with_an_empty_hand(self) -> None:
        rejects(_trip(), SendHand("p1"), RejectionCode.HAND_EMPTY)

    def test_is_rejected_for_a_passenger_who_is_not_aboard(self) -> None:
        trip = _trip()
        ok(trip, PickFromTray(100))
        rejects(trip, SendHand("p2"), RejectionCode.NOT_ABOARD)
        rejects(trip, SendHand("p9"), RejectionCode.NOT_ABOARD)
        step_to_seconds(trip, 2)
        assert passenger(trip, "p3").presence == Presence.GONE
        rejects(trip, SendHand("p3"), RejectionCode.NOT_ABOARD)


def test_rejected_commands_are_not_logged_accepted_ones_are() -> None:
    trip = _trip()
    rejects(trip, ReturnHand(), RejectionCode.HAND_EMPTY)
    rejects(trip, PickFromTray(500), RejectionCode.TRAY_EMPTY)
    ok(trip, PickFromTray(100))
    ok(trip, SendHand("p1"))
    assert [entry.to_json() for entry in trip.command_log] == [
        [0, "PickFromTray", 100],
        [0, "SendHand", "p1"],
    ]
