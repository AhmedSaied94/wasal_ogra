"""The trip shell: starting, the clock, the log, the cap, the status table and the failure check
(RULES.md §2 to §4, §10.2), ported from `engine_shell_test.dart`.

Pausing isn't mirrored (research R3): `paused` is set directly where a test needs it.
"""

from __future__ import annotations

import pytest
from wassal_content.models import BoosterId

from tests.support.builders import TripBuilder, default_params
from tests.support.scripts import ok, rejects, start_trip
from wassal_solver.engine import TripRefused, start
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
from wassal_solver.engine.model import Alertness, Presence, TripStatus
from wassal_solver.engine.money import Pieces
from wassal_solver.engine.rules.command_handlers import COMMAND_CAP, allowed_statuses

DEFINITION = (
    TripBuilder()
    .station("kobri", 30)
    .passenger("p1", seat="A_r", dest="kobri", payment=[500, 100, 100])
    .tray({100: 4, 50: 4})
    .build()
)


class TestStarting:
    def test_an_invalid_trip_raises_trip_refused(self) -> None:
        with pytest.raises(TripRefused):
            start_trip(DEFINITION, seed=0)

    def test_a_valid_trip_starts_running_at_0_with_reputation_100_and_its_tray(self) -> None:
        trip = start_trip(DEFINITION)
        assert trip.status == TripStatus.RUNNING
        assert trip.t_ms == 0
        assert trip.state.reputation == 100
        assert trip.state.tray == Pieces.of({100: 4, 50: 4})
        assert trip.state.hand.is_empty
        assert trip.result is None
        assert trip.command_log == ()
        assert trip.seed == 1

    def test_the_seed_can_be_any_valid_one(self) -> None:
        assert start_trip(DEFINITION, seed=99).seed == 99

    def test_who_is_aboard_or_waiting_and_their_alertness(self) -> None:
        definition = (
            TripBuilder()
            .station("kobri", 30)
            .station("gamaa", 60)
            .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], archetype="sleeper")
            .passenger("p2", seat="A_m", dest="gamaa", payment=[1000], archetype="headphones")
            .passenger("p3", seat="A_l", dest="gamaa", payment=[1000], board="kobri")
            .passenger("p4", seat="B_r", dest="gamaa", payment=[1000], archetype="hajja")
            .passenger("p5", seat="B_m", dest="gamaa", payment=[1000])
            .event("roadside_pickup", 10, passengers=["p5"])
            .build()
        )
        state = start_trip(definition).state
        assert [(p.passenger_id, p.presence, p.alertness) for p in state.passengers] == [
            ("p1", Presence.ABOARD, Alertness.ASLEEP),
            ("p2", Presence.ABOARD, Alertness.MUTED),
            ("p3", Presence.WAITING, Alertness.AWAKE),
            ("p4", Presence.ABOARD, Alertness.AWAKE),
            ("p5", Presence.WAITING, Alertness.AWAKE),
        ]
        assert [(s.station_id, s.at_ms, s.warned) for s in state.schedule] == [
            ("kobri", 30000, False),
            ("gamaa", 60000, False),
        ]
        assert state.events_fired == [False]

    def test_the_trip_is_built_from_content_kit_definitions(self) -> None:
        trip = start(DEFINITION, default_params(DEFINITION.line_id), DEFINITION.seed)
        assert [station.at_ms for station in trip.state.schedule] == [30000]


class TestTheClock:
    def test_step_advances_33_ms(self) -> None:
        trip = start_trip(DEFINITION)
        trip.step()
        assert trip.t_ms == 33
        trip.step()
        assert trip.t_ms == 66

    def test_step_to_stops_at_the_first_step_at_or_after_t_and_never_goes_back(self) -> None:
        trip = start_trip(DEFINITION)
        trip.step_to(330)
        assert trip.t_ms == 330
        trip.step_to(100)
        assert trip.t_ms == 330
        trip.step_to(340)
        assert trip.t_ms == 363

    def test_step_to_stops_when_the_trip_leaves_running(self) -> None:
        trip = start_trip(DEFINITION)
        trip.step_to(330)
        trip.state.reputation = 0
        trip.step_to(10_000_000)
        assert trip.status == TripStatus.FAILED
        assert trip.t_ms == 363
        assert trip.result is not None

    def test_a_trip_that_is_not_running_does_not_move(self) -> None:
        for status in (TripStatus.PAUSED, TripStatus.FINISHED, TripStatus.ABANDONED):
            trip = start_trip(DEFINITION)
            trip.state.status = status
            before = trip.state.to_json()
            trip.step()
            trip.step_to(5000)
            assert trip.state.to_json() == before


class TestTheLog:
    def test_an_accepted_command_is_logged_at_the_current_t_ms(self) -> None:
        trip = start_trip(DEFINITION)
        trip.step_to(330)
        ok(trip, PickFromTray(100))
        assert [entry.to_json() for entry in trip.command_log] == [[330, "PickFromTray", 100]]
        assert trip.state.commands_accepted == 1
        assert isinstance(trip.command_log, tuple)

    def test_a_rejected_command_is_not_logged_and_changes_nothing(self) -> None:
        trip = start_trip(DEFINITION)
        rejects(trip, PickFromTray(1000), RejectionCode.TRAY_EMPTY)
        rejects(trip, PickFromTray(300), RejectionCode.BAD_ARGUMENT)
        rejects(trip, ReturnHand(), RejectionCode.HAND_EMPTY)
        assert trip.command_log == ()
        assert trip.state.commands_accepted == 0

    def test_the_1201st_command_is_rejected_with_command_limit(self) -> None:
        trip = start_trip(DEFINITION)
        for _ in range(600):
            ok(trip, PickFromTray(100))
            ok(trip, ReturnHand())
        assert len(trip.command_log) == COMMAND_CAP == 1200
        rejects(trip, PickFromTray(100), RejectionCode.COMMAND_LIMIT)
        trip.step()
        assert trip.t_ms == 33, "the trip still runs"

    def test_abandon_is_still_accepted_at_the_cap(self) -> None:
        trip = start_trip(DEFINITION)
        for _ in range(600):
            ok(trip, PickFromTray(100))
            ok(trip, ReturnHand())
        ok(trip, Abandon())
        assert trip.status == TripStatus.ABANDONED
        assert len(trip.command_log) == 1201
        assert trip.state.commands_accepted == 1201

    def test_a_failed_trip_at_the_cap_can_be_abandoned_not_revived(self) -> None:
        trip = start_trip(DEFINITION)
        trip.state.commands_accepted = COMMAND_CAP
        trip.state.status = TripStatus.FAILED
        rejects(trip, Revive(), RejectionCode.COMMAND_LIMIT)
        ok(trip, Abandon())
        assert trip.status == TripStatus.ABANDONED


class TestStatusChecks:
    def test_the_commands_table(self) -> None:
        running = {TripStatus.RUNNING}
        choices = {TripStatus.RUNNING, TripStatus.PAUSED}
        table: list[tuple[Command, set[TripStatus]]] = [
            (PickFromTray(100), running),
            (ReturnHand(), running),
            (SendHand("p1"), running),
            (UndoLastSend(), running),
            (Tap("p1"), running),
            (ResolveClaim("p1", insist=True), choices),
            (ResolveDispute(0, "p1"), choices),
            (ResolveChangeRequest("p1", agree=True), choices),
            (RequestBreak(1000), running),
            (CollectDropped(1), running),
            (UseBooster(BoosterId.CHANGE_BAG), choices),
            (Revive(), {TripStatus.FAILED}),
            (Abandon(), {TripStatus.RUNNING, TripStatus.PAUSED, TripStatus.FAILED}),
        ]
        for command, statuses in table:
            assert allowed_statuses(command) == statuses, command.name

    def test_a_command_outside_its_statuses_is_rejected_with_wrong_status(self) -> None:
        paused = start_trip(DEFINITION)
        paused.state.status = TripStatus.PAUSED
        rejects(paused, PickFromTray(100), RejectionCode.WRONG_STATUS)
        rejects(paused, Tap("p1"), RejectionCode.WRONG_STATUS)
        rejects(paused, Revive(), RejectionCode.WRONG_STATUS)
        rejects(start_trip(DEFINITION), Revive(), RejectionCode.WRONG_STATUS)
        for status in (TripStatus.FINISHED, TripStatus.ABANDONED):
            ended = start_trip(DEFINITION)
            ended.state.status = status
            rejects(ended, Abandon(), RejectionCode.WRONG_STATUS)
            rejects(ended, UseBooster(BoosterId.CHANGE_BAG), RejectionCode.WRONG_STATUS)

    def test_wrong_status_comes_before_the_cap(self) -> None:
        trip = start_trip(DEFINITION)
        trip.state.commands_accepted = COMMAND_CAP
        trip.state.status = TripStatus.FINISHED
        rejects(trip, Abandon(), RejectionCode.WRONG_STATUS)


class TestFailure:
    def test_reputation_driven_to_0_fails_the_trip_at_the_next_check(self) -> None:
        trip = start_trip(DEFINITION)
        trip.step_to(330)
        trip.state.reputation = 0
        trip.step()
        assert trip.status == TripStatus.FAILED
        assert trip.t_ms == 363
        assert trip.state.revivable
        result = trip.result
        assert result is not None
        assert result.to_json()["outcome"] == "failed"
        assert result.stars == 0
        assert result.earnings_jenehat == 0
        trip.step()
        assert trip.t_ms == 363, "the clock stops"
        rejects(trip, PickFromTray(100), RejectionCode.WRONG_STATUS)

    def test_a_positive_reputation_never_fails(self) -> None:
        trip = start_trip(DEFINITION)
        trip.state.reputation = 1
        trip.step()
        assert trip.status == TripStatus.RUNNING

    def test_a_failed_trip_revives_once(self) -> None:
        trip = start_trip(DEFINITION)
        trip.state.reputation = 0
        trip.step()
        ok(trip, Revive())
        assert trip.status == TripStatus.RUNNING
        assert trip.state.reputation == default_params().rep_revive_to
        assert trip.state.revived
        assert trip.result is None
        trip.state.reputation = 0
        trip.step()
        assert trip.result is not None
        assert trip.result.outcome == "failed"
        rejects(trip, Revive(), RejectionCode.NOT_REVIVABLE)
