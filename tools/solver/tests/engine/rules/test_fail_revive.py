"""Failing and reviving (RULES.md §4.12, §10, M01 clarification 3), ported from
`test/rules/fail_revive_test.dart`.

Dart's `TripFailed` and `TripRevived` events are read from the state: the status, the result and
`reputation_lost`. Pausing isn't mirrored (research R3): `paused` is set directly where a test
needs it, and Dart's `resume()` after a failure, a no-op, is left out.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder, default_params
from tests.support.scripts import ok, rejects, set_reputation, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import (
    PickFromTray,
    RejectionCode,
    ResolveChangeRequest,
    ResolveClaim,
    Revive,
    SendHand,
    Tap,
)
from wassal_solver.engine.model import RepCause, TripOutcome, TripStatus
from wassal_solver.engine.replay import replay


def status(run: Trip) -> TripStatus:
    """The trip's status, read through a call so the type checker doesn't narrow it."""
    return run.status


def trip(*, no_fights: bool = False) -> TripBuilder:
    """p1 pays 1000 at 1 s; short change of 200 reaches him at 3300. p2 is a false claimer whose
    claim stays open."""
    return (
        TripBuilder()
        .station("gamaa", 40)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1)
        .passenger(
            "p2", seat="A_m", dest="gamaa", payment=[1000], pays_at=1, archetype="false_claimer"
        )
        .rules(no_fights_required=no_fights)
    )


def failed(*, no_fights: bool = False) -> Trip:
    """Fails the trip at 3300 with short change at reputation 5."""
    run = start_trip(trip(no_fights=no_fights).build())
    run.step_to(2145)
    set_reputation(run, 5)
    ok(run, PickFromTray(100))
    ok(run, PickFromTray(100))
    ok(run, SendHand("p1"))
    run.step_to(3300)
    return run


def test_reputation_at_0_fails_the_trip_at_once_and_the_clock_stops() -> None:
    run = failed()
    assert run.status is TripStatus.FAILED
    assert run.t_ms == 3300
    before = run.state.to_json()
    run.step()
    step_to_seconds(run, 20)
    assert run.state.to_json() == before
    assert run.t_ms == 3300
    assert list(run.state.claims) == ["p2"]
    assert run.state.revivable


def test_the_failure_carries_the_breakdown_short_change_included() -> None:
    run = failed()
    assert run.state.reputation_lost == {RepCause.SHORT_CHANGE: 5}
    assert run.result is not None
    assert run.result.to_json()["reputation_lost"] == {"short_change": 5}
    assert run.state.revivable


def test_a_failed_result_has_0_stars_and_no_earnings() -> None:
    result = failed().result
    assert result is not None
    assert result.outcome is TripOutcome.FAILED
    assert (result.stars, result.earnings_jenehat) == (0, 0)
    assert not result.star_flags.reached


def test_a_revive_goes_on_at_rep_revive_to_from_the_same_point() -> None:
    run = failed()
    ok(run, Revive())
    assert run.state.reputation == 40
    assert status(run) is TripStatus.RUNNING
    assert run.result is None
    assert run.t_ms == 3300
    assert run.state.reputation_lost == {RepCause.SHORT_CHANGE: 5}, "a revive isn't a loss"
    step_to_seconds(run, 50)
    assert run.result is not None
    assert run.result.revived
    assert run.result.outcome is TripOutcome.FINISHED


def test_a_second_revive_is_not_revivable() -> None:
    run = failed()
    ok(run, Revive())
    set_reputation(run, 1)
    ok(run, PickFromTray(50))
    ok(run, SendHand("p1"))
    step_to_seconds(run, 6)
    assert run.status is TripStatus.FAILED
    rejects(run, Revive(), RejectionCode.NOT_REVIVABLE)


def test_a_revive_while_running_is_wrong_status() -> None:
    rejects(start_trip(trip().build()), Revive(), RejectionCode.WRONG_STATUS)


def test_in_a_no_fights_trip_the_first_fight_fails_it_for_good() -> None:
    run = start_trip(trip(no_fights=True).build())
    step_to_seconds(run, 41)
    assert run.status is TripStatus.FAILED
    assert run.result is not None
    assert run.result.fights == 1
    assert not run.state.revivable
    rejects(run, Revive(), RejectionCode.NOT_REVIVABLE)


def test_so_does_the_first_false_accusation() -> None:
    run = start_trip(trip(no_fights=True).build())
    step_to_seconds(run, 5)
    ok(run, Tap("p1"))
    ok(run, ResolveClaim("p1", insist=True))
    assert run.status is TripStatus.FAILED
    assert not run.state.revivable


def test_a_reputation_failure_there_with_no_fight_is_revivable() -> None:
    run = failed(no_fights=True)
    assert run.status is TripStatus.FAILED
    assert run.state.revivable


class TestFailingWhilePaused:
    def test_an_answer_that_ends_the_trip_goes_from_paused_to_failed(self) -> None:
        run = start_trip(trip(no_fights=True).build())
        step_to_seconds(run, 5)
        ok(run, Tap("p1"))
        run.state.status = TripStatus.PAUSED
        at = run.t_ms
        ok(run, ResolveClaim("p1", insist=True))
        assert (status(run), run.t_ms) == (TripStatus.FAILED, at)
        assert run.result is not None
        replayed = replay(run.definition, run.seed, run.params, run.command_log)
        assert replayed.to_json() == run.result.to_json()
        assert replayed.duration_ms == at

    def test_so_does_a_declined_change_request_that_takes_reputation_to_0(self) -> None:
        run = start_trip(trip().event("change_request", 5, passengers=["p1"], amount=1000).build())
        step_to_seconds(run, 6)
        set_reputation(run, default_params().rep_change_request_declined)
        run.state.status = TripStatus.PAUSED
        ok(run, ResolveChangeRequest("p1", agree=False))
        assert status(run) is TripStatus.FAILED
        assert run.state.revivable
