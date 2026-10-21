"""The four in-trip boosters (RULES.md §3 step 2.4, §4.11), ported from `boosters_test.dart`. The
events are checked as the state they leave; pausing isn't mirrored (research R3), so `paused` is
set directly.
"""

from __future__ import annotations

import pytest
from wassal_content.models import BoosterId

from tests.support.builders import TripBuilder, params_with
from tests.support.scripts import ok, passenger, rejects, start_trip, step_to_seconds
from wassal_solver.engine.commands import RejectionCode, Tap, UseBooster
from wassal_solver.engine.model import Alertness, TripStatus


def _trip() -> TripBuilder:
    return (
        TripBuilder()
        .station("kobri", 30)
        .station("gamaa", 50)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
    )


def test_change_bag_adds_50x2_100x3_and_500x2() -> None:
    trip = start_trip(_trip().build())
    before = trip.state.tray
    ok(trip, UseBooster(BoosterId.CHANGE_BAG))
    after = trip.state.tray
    assert [after.count(d) - before.count(d) for d in (50, 100, 500)] == [2, 3, 2]
    assert trip.state.boosters_used == [BoosterId.CHANGE_BAG]


def test_wake_all_wakes_every_asleep_or_waking_sleeper_at_once() -> None:
    builder = (
        _trip()
        .passenger("p2", seat="A_m", dest="gamaa", payment=[1000], archetype="sleeper")
        .passenger("p3", seat="A_l", dest="gamaa", payment=[1000], archetype="sleeper")
    )
    trip = start_trip(builder.build())
    ok(trip, Tap("p3"))
    assert passenger(trip, "p3").alertness == Alertness.WAKING
    ok(trip, UseBooster(BoosterId.WAKE_ALL))
    # Dart also checks the PassengerWoke order and p2's speech, which aren't mirrored.
    for passenger_id in ("p2", "p3"):
        state = passenger(trip, passenger_id)
        assert (state.alertness, state.alert_until_ms) == (Alertness.AWAKE, 15000)


def test_ledger_peek_lasts_booster_ledger_peek_ms() -> None:
    trip = start_trip(_trip().build())
    trip.step_to(990)
    ok(trip, UseBooster(BoosterId.LEDGER_PEEK))
    assert trip.state.ledger_peek_until_ms == 10990
    trip.step_to(10989)
    assert trip.state.ledger_peek_until_ms == 10990
    assert trip.t_ms < 10990, "still active"
    trip.step()
    assert trip.t_ms == 11022
    assert trip.state.ledger_peek_until_ms is None


def test_traffic_jam_shifts_the_schedule_by_booster_traffic_jam_ms() -> None:
    trip = start_trip(_trip().build())
    step_to_seconds(trip, 5)
    ok(trip, UseBooster(BoosterId.TRAFFIC_JAM))
    assert [station.at_ms for station in trip.state.schedule] == [40000, 60000]


def test_a_fourth_traffic_jam_is_booster_limit_at_the_default_of_3() -> None:
    trip = start_trip(_trip().build())
    for _ in range(3):
        ok(trip, UseBooster(BoosterId.TRAFFIC_JAM))
    rejects(trip, UseBooster(BoosterId.TRAFFIC_JAM), RejectionCode.BOOSTER_LIMIT)
    assert len(trip.state.boosters_used) == 3


def test_a_limit_of_0_rejects_the_first_traffic_jam() -> None:
    trip = start_trip(_trip().build(), params=params_with({"booster_traffic_jam_max_per_trip": 0}))
    rejects(trip, UseBooster(BoosterId.TRAFFIC_JAM), RejectionCode.BOOSTER_LIMIT)


@pytest.mark.parametrize(
    "booster", [BoosterId.REVIVE, BoosterId.REFUEL_FULL, BoosterId.FUEL_UNLIMITED_1H]
)
def test_an_out_of_trip_booster_is_bad_argument(booster: BoosterId) -> None:
    rejects(start_trip(_trip().build()), UseBooster(booster), RejectionCode.BAD_ARGUMENT)


def test_every_use_is_recorded_and_boosters_work_while_paused() -> None:
    trip = start_trip(_trip().build())
    ok(trip, UseBooster(BoosterId.CHANGE_BAG))
    trip.state.status = TripStatus.PAUSED
    ok(trip, UseBooster(BoosterId.LEDGER_PEEK))
    ok(trip, UseBooster(BoosterId.CHANGE_BAG))
    assert trip.status == TripStatus.PAUSED
    assert trip.state.boosters_used == [
        BoosterId.CHANGE_BAG,
        BoosterId.LEDGER_PEEK,
        BoosterId.CHANGE_BAG,
    ]
    trip.state.status = TripStatus.RUNNING
    step_to_seconds(trip, 60)
    assert trip.result is not None
    assert len(trip.result.boosters_used) == 3
