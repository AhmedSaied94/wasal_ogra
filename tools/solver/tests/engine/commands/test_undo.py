"""UndoLastSend (RULES.md §4.4), ported from `undo_test.dart`: the last send comes back to the hand
while the undo window lasts and before its first hop ends. p1 pays 1000 at 1 s; the fare is in at
2145.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder, params_with
from tests.support.scripts import ok, rejects, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, RejectionCode, SendHand, UndoLastSend


def _trip(*, undo_window: int | None = None, events: tuple[tuple[str, int], ...] = ()) -> Trip:
    builder = (
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1)
    )
    for event_id, at in events:
        builder.event(event_id, at)
    params = None if undo_window is None else params_with({"trip_undo_window_ms": undo_window})
    trip = start_trip(builder.build(), params=params)
    trip.step_to(2145)
    return trip


def _send(trip: Trip, pieces: list[int]) -> None:
    for piece in pieces:
        ok(trip, PickFromTray(piece))
    ok(trip, SendHand("p1"))


def test_within_the_window_it_puts_the_pieces_back_in_the_hand() -> None:
    trip = _trip()
    _send(trip, [100, 100, 100])
    send = trip.state.last_send
    assert send is not None
    assert send.until_ms == 2145 + 1000
    trip.step_to(2178)
    ok(trip, UndoLastSend())
    assert trip.state.hand.total == 300
    assert send.token_id not in trip.state.tokens
    assert trip.state.last_send is None


def test_after_the_window_it_is_undo_unavailable() -> None:
    trip = _trip()
    _send(trip, [100])
    trip.step_to(3168)
    rejects(trip, UndoLastSend(), RejectionCode.UNDO_UNAVAILABLE)


def test_after_the_first_hop_ends_it_is_undo_unavailable() -> None:
    # p2 in A_r passes p1's change on, so the send takes two hops.
    definition = (
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="C_r", dest="gamaa", payment=[1000], pays_at=1)
        .passenger("p2", seat="A_r", dest="gamaa", payment=[500, 100, 100])
        .build()
    )
    trip = start_trip(definition, params=params_with({"trip_undo_window_ms": 60000}))
    step_to_seconds(trip, 5)
    _send(trip, [100])
    trip.step_to(trip.t_ms + 35 * 33)
    (token,) = trip.state.tokens.values()
    assert token.hops_done == 1
    rejects(trip, UndoLastSend(), RejectionCode.UNDO_UNAVAILABLE)


def test_a_dropped_token_cannot_be_undone() -> None:
    trip = _trip(undo_window=60000, events=(("bump", 3),))
    _send(trip, [100])
    step_to_seconds(trip, 3)
    (token,) = trip.state.tokens.values()
    assert token.is_dropped
    rejects(trip, UndoLastSend(), RejectionCode.UNDO_UNAVAILABLE)


def test_a_second_undo_is_undo_unavailable() -> None:
    trip = _trip()
    _send(trip, [100])
    ok(trip, UndoLastSend())
    rejects(trip, UndoLastSend(), RejectionCode.UNDO_UNAVAILABLE)


def test_only_the_last_send_can_be_undone() -> None:
    trip = _trip()
    _send(trip, [100])
    _send(trip, [100, 100])
    ok(trip, UndoLastSend())
    assert trip.state.hand.total == 200
    (token,) = trip.state.tokens.values()
    assert token.pieces.total == 100
    rejects(trip, UndoLastSend(), RejectionCode.UNDO_UNAVAILABLE)


def test_with_nothing_sent_it_is_undo_unavailable() -> None:
    rejects(_trip(), UndoLastSend(), RejectionCode.UNDO_UNAVAILABLE)
