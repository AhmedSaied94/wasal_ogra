"""Abandoning (RULES.md §4, §4.13, M01 FR-054), ported from `abandon_pause_test.dart`.

Pausing isn't mirrored (research R3): `paused` is set directly where a case needs it, and the case
that pause and resume are never logged isn't ported.
"""

from __future__ import annotations

from wassal_content.models import BoosterId

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, rejects, set_reputation, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import (
    Abandon,
    CollectDropped,
    Command,
    PickFromTray,
    RejectionCode,
    RequestBreak,
    ResolveChangeRequest,
    ResolveClaim,
    ResolveDispute,
    ReturnHand,
    Revive,
    SendHand,
    Tap,
    UndoLastSend,
    UseBooster,
)
from wassal_solver.engine.model import TripOutcome, TripStatus


def _trip() -> Trip:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1)
        .build()
    )
    step_to_seconds(trip, 3)
    return trip


def _abandon(trip: Trip) -> None:
    ok(trip, Abandon())
    result = trip.result
    assert result is not None
    assert trip.status == TripStatus.ABANDONED
    assert result.outcome == TripOutcome.ABANDONED
    assert (result.stars, result.earnings_jenehat) == (0, 0)
    assert result.duration_ms == trip.t_ms


def test_abandoning_a_running_trip() -> None:
    _abandon(_trip())


def test_abandoning_a_paused_trip() -> None:
    trip = _trip()
    trip.state.status = TripStatus.PAUSED
    _abandon(trip)


def test_abandoning_a_failed_trip() -> None:
    trip = _trip()
    set_reputation(trip, 0)
    trip.step()
    assert trip.status == TripStatus.FAILED
    _abandon(trip)


def test_commands_after_the_end_are_wrong_status() -> None:
    abandoned = _trip()
    ok(abandoned, Abandon())
    rejects(abandoned, Abandon(), RejectionCode.WRONG_STATUS)
    rejects(abandoned, PickFromTray(100), RejectionCode.WRONG_STATUS)
    finished = _trip()
    step_to_seconds(finished, 40)
    assert finished.status == TripStatus.FINISHED
    rejects(finished, Abandon(), RejectionCode.WRONG_STATUS)
    rejects(finished, UseBooster(BoosterId.CHANGE_BAG), RejectionCode.WRONG_STATUS)


def test_while_paused_only_choices_boosters_and_abandon_are_accepted() -> None:
    trip = _trip()
    ok(trip, PickFromTray(100))
    trip.state.status = TripStatus.PAUSED
    commands: list[Command] = [
        PickFromTray(100),
        ReturnHand(),
        SendHand("p1"),
        UndoLastSend(),
        Tap("p1"),
        RequestBreak(1000),
        CollectDropped(1),
        Revive(),
    ]
    for command in commands:
        rejects(trip, command, RejectionCode.WRONG_STATUS)
    rejects(trip, ResolveClaim("p1", insist=True), RejectionCode.NO_CHOICE)
    rejects(trip, ResolveDispute(0, "p1"), RejectionCode.NO_CHOICE)
    rejects(trip, ResolveChangeRequest("p1", agree=True), RejectionCode.NO_CHOICE)
    ok(trip, UseBooster(BoosterId.CHANGE_BAG))
    ok(trip, Abandon())
