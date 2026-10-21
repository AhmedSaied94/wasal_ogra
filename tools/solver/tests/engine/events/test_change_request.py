"""change_request (RULES.md §4.8, §5.5, §5.7, §14.4), ported from `change_request_test.dart`: a
passenger asks the driver to break a note. The default tray holds four 100s, four 50s and two
500s.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, rejects, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import RejectionCode, ResolveChangeRequest
from wassal_solver.engine.model import ChangeRequest, RepCause, TokenKind


def requesting(*, tray: dict[int, int] | None = None, bump_at: int | None = None) -> Trip:
    builder = (
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
        .event("change_request", 5, passengers=["p1"], amount=1000)
    )
    if tray is not None:
        builder.tray(tray)
    if bump_at is not None:
        builder.event("bump", bump_at)
    trip = start_trip(builder.build())
    step_to_seconds(trip, 6)
    return trip


def test_it_opens_with_the_note() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100])
        .event("change_request", 5, passengers=["p1"], amount=1000)
        .build()
    )
    step_to_seconds(trip, 6)
    # Dart also checks the change_request speech and its amount, which aren't mirrored.
    assert trip.state.change_requests == {"p1": ChangeRequest(note_piasters=1000)}


def test_agreeing_sends_the_chosen_pieces_and_the_note_comes_back() -> None:
    trip = requesting()
    tray = trip.state.tray
    ok(trip, ResolveChangeRequest("p1", agree=True))
    assert trip.state.change_requests == {}
    (token,) = trip.state.tokens.values()
    assert token.kind == TokenKind.BREAK_OUT
    assert token.pieces.to_json() == {"500": 2}
    assert trip.state.tray.count(500) == tray.count(500) - 2
    step_to_seconds(trip, 12)
    assert trip.state.tokens == {}
    assert trip.state.tray.count(1000) == tray.count(1000) + 1
    assert trip.state.tray.total == tray.total


def test_without_the_pieces_it_is_cannot_make_change_and_stays_open() -> None:
    # With the fare in, the tray holds a 500, two 100s and a 50: 750.
    trip = requesting(tray={50: 1})
    assert trip.state.tray.total == 750
    rejects(trip, ResolveChangeRequest("p1", agree=True), RejectionCode.CANNOT_MAKE_CHANGE)
    assert list(trip.state.change_requests) == ["p1"]


def test_declining_costs_reputation() -> None:
    trip = requesting()
    ok(trip, ResolveChangeRequest("p1", agree=False))
    # Dart also checks the change_request_declined speech, which isn't mirrored.
    declined = trip.params.rep_change_request_declined
    assert trip.state.reputation == 100 - declined
    assert trip.state.reputation_lost == {RepCause.CHANGE_REQUEST_DECLINED: declined}
    assert trip.state.change_requests == {}


def test_no_answer_by_their_stop_counts_as_declined() -> None:
    trip = requesting()
    trip.step_to(29997)
    assert trip.state.reputation == 100
    assert list(trip.state.change_requests) == ["p1"]
    trip.step_to(30030)
    declined = trip.params.rep_change_request_declined
    assert trip.state.reputation_lost == {RepCause.CHANGE_REQUEST_DECLINED: declined}
    assert trip.state.change_requests == {}
    step_to_seconds(trip, 40)
    assert trip.result is not None
    assert trip.result.reputation == 100 - declined


def test_a_lost_break_out_cancels_the_exchange_with_no_penalty() -> None:
    # Agreed at 6006, the break_out hops from 6039 to 7161; the bump at 7 s drops it.
    trip = requesting(bump_at=7)
    tray = trip.state.tray.total
    ok(trip, ResolveChangeRequest("p1", agree=True))
    trip.step_to(7029)
    assert next(iter(trip.state.tokens.values())).is_dropped
    step_to_seconds(trip, 40)
    assert trip.state.tokens == {}
    assert trip.state.reputation_lost == {}
    assert trip.state.tray.total == tray - 1000


def test_a_second_request_while_one_is_open_is_skipped() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
        .event("change_request", 5, passengers=["p1"], amount=1000)
        .event("change_request", 8, passengers=["p1"], amount=2000)
        .build()
    )
    step_to_seconds(trip, 9)
    assert trip.state.events_fired == [True, True]
    assert trip.state.change_requests == {"p1": ChangeRequest(note_piasters=1000)}
