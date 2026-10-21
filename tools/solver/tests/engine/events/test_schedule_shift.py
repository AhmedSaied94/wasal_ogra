"""traffic and open_road (RULES.md §8, §9.1), ported from `schedule_shift_test.dart`: the schedule
shifts from the next station on, and events keep the unshifted trip clock.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import passenger, start_trip, step_to_seconds
from wassal_solver.engine import Trip


def base() -> TripBuilder:
    return (
        TripBuilder()
        .station("kobri", 30)
        .station("gamaa", 40)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1)
    )


def stations(trip: Trip) -> list[int]:
    return [station.at_ms for station in trip.state.schedule]


def test_traffic_moves_the_next_station_and_every_later_one() -> None:
    trip = start_trip(base().event("traffic", 5, seconds=10).build())
    step_to_seconds(trip, 5)
    assert stations(trip) == [40000, 50000]
    assert trip.state.traffic_active


def test_traffic_stays_active_until_the_next_station_and_drains_patience_faster() -> None:
    trip = start_trip(base().event("traffic", 5, seconds=10).build())
    step_to_seconds(trip, 5)
    before = passenger(trip, "p1").patience_ms
    assert before is not None
    trip.step()
    assert passenger(trip, "p1").patience_ms == before - 49
    trip.step_to(39996)
    assert trip.state.traffic_active
    trip.step_to(40029)
    assert not trip.state.traffic_active


def test_open_road_moves_them_sooner() -> None:
    trip = start_trip(base().event("open_road", 5, seconds=10).build())
    step_to_seconds(trip, 5)
    assert stations(trip) == [20000, 30000]
    assert not trip.state.traffic_active


def test_open_road_never_brings_the_next_station_closer_than_the_warning() -> None:
    trip = start_trip(base().event("open_road", 15, seconds=10).build())
    step_to_seconds(trip, 15)
    # At 15015, kobri can come no sooner than 15015 + 8000.
    assert stations(trip) == [23015, 33015]


def test_shifts_add_up() -> None:
    trip = start_trip(
        base()
        .event("traffic", 2, seconds=10)
        .event("traffic", 4, seconds=5)
        .event("open_road", 6, seconds=3)
        .build()
    )
    step_to_seconds(trip, 7)
    assert stations(trip) == [42000, 52000]


def test_events_run_on_the_unshifted_trip_clock() -> None:
    trip = start_trip(base().event("traffic", 2, seconds=10).event("bump", 25).build())
    trip.step_to(1980)
    assert trip.state.events_fired == [False, False]
    trip.step()
    assert (trip.t_ms, trip.state.events_fired) == (2013, [True, False])
    trip.step_to(24981)
    assert trip.state.events_fired == [True, False]
    trip.step()
    assert (trip.t_ms, trip.state.events_fired) == (25014, [True, True])
