"""`replay` (contracts/mirror.md §3), ported from `replay_test.dart`: a live run's log replays to
the same result, and a log the engine can't follow is refused with its reason and the entry's index.
"""

from __future__ import annotations

import json

import pytest
from wassal_content.models import TripDefinition

from tests.support.builders import TripBuilder, default_params
from tests.support.scripts import ok, start_trip, step_to_seconds
from wassal_solver.engine import Trip, command_log_hash
from wassal_solver.engine.commands import (
    LoggedCommand,
    PickFromTray,
    RejectionCode,
    ReturnHand,
    SendHand,
    decode_log,
)
from wassal_solver.engine.model import TripOutcome, TripStatus
from wassal_solver.engine.replay import ReplayReason, ReplayRefused, replay
from wassal_solver.engine.validation import RefusalCode

PARAMS = default_params()


def trip(*, no_fights: bool = False) -> TripDefinition:
    """p1 (A_r) pays 1000 at 1 s for a 700 fare; the fare reaches the tray at 1023 + 34 * 33 =
    2145. The trip finishes at gamaa, 30 s."""
    return (
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1)
        .rules(no_fights_required=no_fights)
        .build()
    )


def live() -> Trip:
    run = start_trip(trip())
    run.step_to(2145)
    for piece in (100, 100, 100):
        ok(run, PickFromTray(piece))
    ok(run, SendHand("p1"))
    step_to_seconds(run, 40)
    return run


def test_a_live_runs_log_replays_to_the_live_result() -> None:
    run = live()
    assert run.status == TripStatus.FINISHED
    assert run.result is not None
    replayed = replay(trip(), 1, PARAMS, run.command_log)
    assert replayed == run.result
    assert replayed.to_json() == run.result.to_json()
    assert replayed.command_log_hash == command_log_hash(run.command_log)
    assert replayed.stars == 3


def test_the_log_replays_the_same_from_its_wire_form() -> None:
    run = live()
    assert run.result is not None
    wire = json.loads(json.dumps([entry.to_json() for entry in run.command_log]))
    assert replay(trip(), 1, PARAMS, decode_log(wire)).to_json() == run.result.to_json()


def test_a_log_entry_the_engine_rejects_is_refused_with_its_index() -> None:
    log = [LoggedCommand(0, PickFromTray(100)), LoggedCommand(33, SendHand("p9"))]
    with pytest.raises(ReplayRefused) as refused:
        replay(trip(), 1, PARAMS, log)
    assert refused.value.reason == ReplayReason.ENTRY_REJECTED
    assert refused.value.index == 1
    assert refused.value.rejection is not None
    assert refused.value.rejection.code == RejectionCode.NOT_ABOARD
    assert refused.value.message == "SendHand was rejected: not_aboard"


def test_a_log_whose_t_ms_goes_down_is_refused() -> None:
    log = [LoggedCommand(66, PickFromTray(100)), LoggedCommand(33, ReturnHand())]
    with pytest.raises(ReplayRefused) as refused:
        replay(trip(), 1, PARAMS, log)
    assert refused.value.reason == ReplayReason.T_MS_GOES_DOWN
    assert refused.value.index == 1
    assert refused.value.message == "t_ms goes down along the log"


def test_an_entry_after_the_trip_has_ended_is_refused() -> None:
    with pytest.raises(ReplayRefused) as refused:
        replay(trip(), 1, PARAMS, [LoggedCommand(39996, PickFromTray(100))])
    assert refused.value.reason == ReplayReason.CLOCK_STOPPED
    assert refused.value.index == 0
    assert refused.value.message == "the clock stopped at 30030, before 39996"


def test_a_refused_trip_is_refused_with_its_problems_and_no_index() -> None:
    with pytest.raises(ReplayRefused) as refused:
        replay(trip(), 0, PARAMS, [])
    assert refused.value.reason == ReplayReason.TRIP_REFUSED
    assert refused.value.index is None
    assert refused.value.message == "the trip is refused"
    assert RefusalCode.BAD_SEED in [r.code for r in refused.value.refusals]


def test_a_log_that_ends_with_the_trip_failed_returns_the_failed_result() -> None:
    # No change is sent: one fight at gamaa fails a no-fights trip.
    log = [LoggedCommand(0, PickFromTray(100))]
    result = replay(trip(no_fights=True), 1, PARAMS, log)
    assert result.outcome == TripOutcome.FAILED
    assert result.stars == 0
    assert result.duration_ms == 30030
    assert result.command_log_hash == command_log_hash(log)


def test_an_empty_log_steps_to_the_end() -> None:
    result = replay(trip(), 1, PARAMS, [])
    assert result.outcome == TripOutcome.FINISHED
    assert result.duration_ms == 30030
    assert result.lost_fares == 0
    assert result.fights == 1
