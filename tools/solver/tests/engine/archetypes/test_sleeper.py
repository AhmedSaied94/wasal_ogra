"""The sleeper (RULES.md §2.4, §3 step 2, §4.5, §9.3, M01 clarification 5), ported from
`sleeper_test.dart`. line_gamaa: hop 1100 ms, `trip_wake_ms` 1000, `trip_sleeper_awake_ms` 15000.

The events are checked as the state they leave; speech isn't mirrored (research R3).
"""

from __future__ import annotations

import pytest

from tests.engine.archetypes.watch import first_t
from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, rejects, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, RejectionCode, SendHand, Tap
from wassal_solver.engine.model import Alertness, AlightOutcome, RepCause


def _sleeper(payment: tuple[int, ...] = (500, 100, 100)) -> Trip:
    return start_trip(
        TripBuilder()
        .station("gamaa", 40)
        .passenger(
            "p1", seat="A_r", dest="gamaa", payment=list(payment), pays_at=1, archetype="sleeper"
        )
        .build()
    )


def test_he_starts_asleep_and_a_tap_wakes_him_after_trip_wake_ms() -> None:
    trip = _sleeper()
    assert passenger(trip, "p1").alertness == Alertness.ASLEEP
    step_to_seconds(trip, 2)
    assert trip.t_ms == 2013
    ok(trip, Tap("p1"))
    assert passenger(trip, "p1").alertness == Alertness.WAKING
    assert passenger(trip, "p1").alert_until_ms == 3013
    rejects(trip, Tap("p1"), RejectionCode.NO_EFFECT)
    trip.step_to(3003)
    assert passenger(trip, "p1").alertness == Alertness.WAKING
    trip.step()
    assert trip.t_ms == 3036
    assert passenger(trip, "p1").alertness == Alertness.AWAKE
    assert passenger(trip, "p1").alert_until_ms == 3036 + 15000


def test_he_pays_at_the_first_step_he_is_able_after_his_pays_at_seconds() -> None:
    trip = _sleeper()
    step_to_seconds(trip, 2)
    assert not passenger(trip, "p1").fare_sent
    ok(trip, Tap("p1"))
    assert first_t(trip, lambda t: passenger(t, "p1").fare_sent, 5000) == 3036


def test_he_falls_asleep_again_15_s_after_waking_even_when_settled() -> None:
    trip = _sleeper()
    step_to_seconds(trip, 2)
    ok(trip, Tap("p1"))
    trip.step_to(18018)
    assert not passenger(trip, "p1").is_owed
    assert passenger(trip, "p1").alertness == Alertness.AWAKE
    trip.step()
    assert trip.t_ms == 18051
    assert passenger(trip, "p1").alertness == Alertness.ASLEEP
    assert passenger(trip, "p1").alert_until_ms is None


def test_asleep_as_a_middle_holder_he_blocks_the_chain_until_woken() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 40)
        .passenger("p1", seat="C_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
        .passenger("p2", seat="B_r", dest="gamaa", payment=[500, 100, 100], archetype="sleeper")
        .build()
    )
    step_to_seconds(trip, 2)
    (fare,) = trip.state.tokens.values()
    assert (fare.holder, fare.blocked_by, fare.hop_to) == ("p1", "p2", None)
    ok(trip, Tap("p2"))
    trip.step_to(3003)
    assert (fare.blocked_by, fare.hop_to) == ("p2", None), "still asleep at 3003"
    trip.step()
    assert trip.t_ms == 3036
    assert (fare.blocked_by, fare.hop_to, fare.hop_elapsed_ms) == (None, "p2", 0)


class TestAsleepAsTheTargetThenAtHisStop:
    @pytest.fixture
    def trip(self) -> Trip:
        # Woken at 0, he pays 1000 at 1023 and falls asleep at 16038. The change sent at 17 s
        # waits for him and he sleeps through gamaa.
        trip = _sleeper(payment=(1000,))
        ok(trip, Tap("p1"))
        step_to_seconds(trip, 17)
        for piece in (100, 100, 100):
            ok(trip, PickFromTray(piece))
        ok(trip, SendHand("p1"))
        return trip

    def test_the_change_is_blocked_by_him(self, trip: Trip) -> None:
        step_to_seconds(trip, 30)
        (change,) = trip.state.tokens.values()
        assert (change.holder, change.blocked_by) == ("DRIVER", "p1")
        assert passenger(trip, "p1").balance == 300, "not delivered"
        step_to_seconds(trip, 60)
        assert passenger(trip, "p1").balance == 300

    def test_he_misses_his_stop_reputation_a_count_and_an_unreturned_mistake(
        self, trip: Trip
    ) -> None:
        step_to_seconds(trip, 60)
        result = trip.result
        assert result is not None
        lost = dict(result.reputation_lost)
        assert lost[RepCause.MISSED_STOP] == trip.params.rep_missed_stop
        assert result.missed_stops == 1
        assert [m.to_json() for m in result.mistakes] == [
            {"passenger_id": "p1", "kind": "unreturned", "amount_piasters": 300}
        ]
        assert passenger(trip, "p1").outcome == AlightOutcome.MISSED_STOP

    def test_a_missed_stop_is_not_a_fight(self, trip: Trip) -> None:
        step_to_seconds(trip, 60)
        assert trip.result is not None
        assert trip.result.fights == 0
        # Dart also checks the speech: no `fight`, and `missed_stop` naming gamaa.


def test_unpaid_and_asleep_at_his_stop_he_is_a_lost_fare_as_well() -> None:
    trip = _sleeper()
    step_to_seconds(trip, 60)
    result = trip.result
    assert result is not None
    assert result.missed_stops == 1
    assert result.lost_fares == 1
    assert result.mistakes == ()
    assert result.reputation == 100 - trip.params.rep_missed_stop
