"""Groups (RULES.md §4.5, §6.1, §6.5.1, §7.2), ported from `group_test.dart`: the payer pays for
everyone and receives the group's change.

The events are checked as the state they leave; speech isn't mirrored (research R3).
"""

from __future__ import annotations

from tests.engine.archetypes.watch import hops
from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, set_alertness, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, SendHand, Tap
from wassal_solver.engine.model import Alertness, AlightOutcome, MistakeKind, Presence


def _group(
    *,
    size: int = 2,
    payment: tuple[int, ...] = (2000,),
    pays_at: int | None = 1,
    member_dest: str = "gamaa",
) -> TripBuilder:
    """The payer p1 and a listed member p2 on an 850 stop. `size` counts the payer, so a size of 3
    leaves one member unlisted."""
    return (
        TripBuilder()
        .station("kobri", 20)
        .station("gamaa", 50, fare=850)
        .passenger(
            "p1",
            seat="A_r",
            dest="gamaa",
            payment=list(payment),
            pays_at=pays_at,
            archetype="group_payer",
            group="g1",
            group_size=size,
        )
        .passenger("p2", seat="A_m", dest=member_dest, payment=[1000], group="g1", group_size=size)
    )


def _payer_leaves_at_kobri(payment: list[int], *, gamaa_fare: int = 700) -> TripBuilder:
    return (
        TripBuilder()
        .station("kobri", 20)
        .station("gamaa", 50, fare=gamaa_fare)
        .passenger(
            "p1",
            seat="A_r",
            dest="kobri",
            payment=payment,
            pays_at=1,
            archetype="group_payer",
            group="g1",
            group_size=2,
        )
        .passenger("p2", seat="A_m", dest="gamaa", payment=[1000], group="g1", group_size=2)
    )


def _give(trip: Trip, passenger_id: str, pieces: list[int]) -> None:
    for piece in pieces:
        ok(trip, PickFromTray(piece))
    ok(trip, SendHand(passenger_id))


def test_the_group_fare_counts_unlisted_members_at_the_base_fare() -> None:
    trip = start_trip(_group(size=3, payment=(5000,)).build())
    trip.step_to(1023)
    payer = passenger(trip, "p1")
    assert payer.fare_piasters == 850 * 3
    assert payer.balance == 2450


def test_a_tap_on_a_member_acts_on_the_payer() -> None:
    trip = start_trip(_group(pays_at=None).build())
    ok(trip, Tap("p2"))
    (fare,) = trip.state.tokens.values()
    assert fare.owner == "p1"
    assert passenger(trip, "p1").fare_sent
    # Dart also checks that p1 says `pays_group`.


def test_members_never_pay_or_claim() -> None:
    trip = start_trip(_group().build())
    claimed: set[str] = set()
    while trip.t_ms < 60000 and trip.result is None:
        trip.step()
        claimed.update(trip.state.claims)
    assert passenger(trip, "p1").fare_sent
    assert trip.state.next_token_id == 2, "one fare token, p1's"
    assert claimed == set()
    assert not passenger(trip, "p2").fare_sent


def test_a_members_change_goes_on_to_the_payer_in_one_600_ms_hop() -> None:
    trip = start_trip(_group().build())
    step_to_seconds(trip, 3)
    _give(trip, "p2", [100, 100, 100])
    assert hops(trip, 6000)[-1] == ("p2>p1", 600)
    assert passenger(trip, "p1").balance == 0, "exact change"
    assert trip.state.mistakes == []


def test_with_the_payer_gone_a_members_change_is_not_owed() -> None:
    trip = start_trip(_payer_leaves_at_kobri([500, 100, 100, 500, 100, 100]).build())
    step_to_seconds(trip, 25)
    _give(trip, "p2", [100])
    step_to_seconds(trip, 30)
    assert [m.kind for m in trip.state.mistakes] == [MistakeKind.NOT_OWED]


def test_members_get_off_thanked_or_with_a_missed_stop_if_asleep() -> None:
    thanked = start_trip(_group(member_dest="kobri").build())
    step_to_seconds(thanked, 25)
    assert passenger(thanked, "p2").outcome == AlightOutcome.THANKED
    asleep = start_trip(_group(member_dest="kobri").build())
    set_alertness(asleep, "p2", Alertness.ASLEEP)
    step_to_seconds(asleep, 25)
    assert passenger(asleep, "p2").outcome == AlightOutcome.MISSED_STOP
    assert asleep.state.counters.lost_fares == 0


def test_change_to_a_member_whose_payer_has_left_is_judged_not_owed() -> None:
    # The payer p1 gets off at kobri; change sent to p2 after that stays with p2, who is owed
    # nothing.
    trip = start_trip(_payer_leaves_at_kobri([2000], gamaa_fare=850).build())
    step_to_seconds(trip, 21)
    assert passenger(trip, "p1").presence == Presence.GONE
    _give(trip, "p2", [100])
    step_to_seconds(trip, 25)
    assert trip.state.tokens == {}
    mistake = trip.state.mistakes[-1]
    assert (mistake.passenger_id, mistake.kind) == ("p2", MistakeKind.NOT_OWED)
