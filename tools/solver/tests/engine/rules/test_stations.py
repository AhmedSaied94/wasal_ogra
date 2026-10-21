"""Stations (RULES.md §9.2 to §9.5) and the end of the trip (§11), ported from
`test/rules/stations_test.dart`.

The mirror has no events (research R3): the warning shows as the station's `warned` flag, getting
off as each passenger's `presence` and `outcome`, boarding as `presence`, and the end as the
status and the result. Who the warning names and what passengers say aren't mirrored.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, start_trip, step_to_seconds
from wassal_solver.engine.commands import PickFromTray, SendHand
from wassal_solver.engine.model import AlightOutcome, Presence, RepCause, TripOutcome, TripStatus

EXACT = [500, 100, 100, 100, 50]


def trip() -> TripBuilder:
    """At kobri (30 s, fare 850): p1 owed 150, p2 settled, p4 never pays. p3 rides on to gamaa."""
    return (
        TripBuilder()
        .station("kobri", 30, fare=850)
        .station("gamaa", 60, fare=850)
        .passenger("p1", seat="A_r", dest="kobri", payment=[1000], pays_at=0)
        .passenger("p2", seat="B_r", dest="kobri", payment=EXACT, pays_at=0)
        .passenger("p3", seat="C_r", dest="gamaa", payment=EXACT, pays_at=0)
        .passenger("p4", seat="A_m", dest="kobri", payment=[1000])
    )


def test_the_warning_comes_trip_station_warning_ms_before_the_station() -> None:
    run = start_trip(trip().build())
    run.step_to(21978)
    assert not run.state.schedule[0].warned
    run.step()
    assert run.t_ms == 22011
    assert run.state.schedule[0].warned
    assert not run.state.schedule[1].warned
    # Who alights, who is owed and p1's `stop_near` are in Dart's StationWarning and speech only.
    assert run.state.schedule[0].at_ms == 30000


def test_getting_off_fight_thanked_and_left_unpaid() -> None:
    run = start_trip(trip().build())
    run.step_to(29997)
    # p1, owed since 1.2 s, has already run out of patience.
    assert run.state.reputation_lost == {RepCause.IMPATIENT: 5}
    reputation = run.state.reputation
    run.step()
    assert run.t_ms == 30030
    outcomes = {p.passenger_id: (p.presence, p.outcome) for p in run.state.passengers}
    assert outcomes == {
        "p1": (Presence.GONE, AlightOutcome.FIGHT),
        "p2": (Presence.GONE, AlightOutcome.THANKED),
        "p3": (Presence.ABOARD, None),
        "p4": (Presence.GONE, AlightOutcome.LEFT_UNPAID),
    }
    assert run.state.reputation == reputation - 30
    assert run.state.reputation_lost == {RepCause.IMPATIENT: 5, RepCause.FIGHT: 30}
    assert run.state.counters.fights == 1
    assert run.state.counters.lost_fares == 1
    assert [m.to_json() for m in run.state.mistakes] == [
        {"passenger_id": "p1", "kind": "unreturned", "amount_piasters": 150}
    ]
    assert run.state.next_station_index == 1
    assert run.state.schedule[run.state.next_station_index].station_id == "gamaa"


class TestBoarding:
    def test_at_a_station_whose_seat_is_free(self) -> None:
        run = start_trip(
            trip().passenger("p5", seat="C_l", dest="gamaa", board="kobri", payment=[1000]).build()
        )
        assert passenger(run, "p5").presence is Presence.WAITING
        run.step_to(29997)
        assert passenger(run, "p5").presence is Presence.WAITING
        run.step()
        assert run.t_ms == 30030
        p5 = passenger(run, "p5")
        assert (p5.presence, p5.seat_id, p5.pickup_due) == (Presence.ABOARD, "C_l", False)

    def test_into_the_seat_of_someone_getting_off_at_the_same_station(self) -> None:
        run = start_trip(
            trip().passenger("p5", seat="A_r", dest="gamaa", board="kobri", payment=[1000]).build()
        )
        run.step_to(30030)
        assert passenger(run, "p5").presence is Presence.ABOARD
        assert passenger(run, "p1").presence is Presence.GONE

    def test_later_the_moment_the_seat_is_freed(self) -> None:
        run = start_trip(
            TripBuilder()
            .station("kobri", 10)
            .station("gamaa", 20)
            .station("souq", 30)
            .passenger("p1", seat="B_m", dest="gamaa", payment=EXACT, pays_at=0)
            .passenger("p2", seat="B_m", dest="souq", board="kobri", payment=[1000])
            .build()
        )
        step_to_seconds(run, 15)
        assert passenger(run, "p2").presence is Presence.WAITING
        assert passenger(run, "p2").pickup_due
        run.step_to(19998)
        assert passenger(run, "p2").presence is Presence.WAITING
        run.step_to(20031)
        assert passenger(run, "p2").presence is Presence.ABOARD
        assert passenger(run, "p1").presence is Presence.GONE

    def test_never_after_their_destination_has_passed(self) -> None:
        run = start_trip(
            TripBuilder()
            .station("kobri", 10)
            .station("gamaa", 20)
            .station("souq", 30)
            .passenger("p1", seat="B_m", dest="gamaa", payment=EXACT, pays_at=0)
            .passenger("p2", seat="B_m", dest="gamaa", board="kobri", payment=[1000])
            .build()
        )
        step_to_seconds(run, 40)
        assert passenger(run, "p2").presence is Presence.WAITING
        assert run.status is TripStatus.FINISHED


def test_the_last_station_finishes_the_trip_after_money_in_transit_is_settled() -> None:
    run = start_trip(
        TripBuilder()
        .station("kobri", 1)
        .passenger("p1", seat="C_r", dest="kobri", payment=[1000], pays_at=0)
        .passenger("p2", seat="A_r", dest="kobri", payment=EXACT)
        .build()
    )
    ok(run, PickFromTray(100))
    ok(run, SendHand("p2"))
    step_to_seconds(run, 5)
    assert run.status is TripStatus.FINISHED
    assert run.t_ms == 1023
    assert run.state.tokens == {}
    assert run.state.tray.count(1000) == 1, "p1's fare arrived"
    assert passenger(run, "p1").paid_in == 1000
    assert run.state.tray.count(100) == 4, "the change came back"
    result = run.result
    assert result is not None
    assert result.outcome is TripOutcome.FINISHED
    assert result.duration_ms == 1023
    before = run.state.to_json()
    run.step()
    assert run.state.to_json() == before
