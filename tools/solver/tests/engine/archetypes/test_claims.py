"""Claims (RULES.md §3 step 4, §4.5 cases 4, 5 and 7, §4.6, §6.3, §7.4, §9.3.1), ported from
`claims_test.dart`: the false claimer, and the truthful claim of a passenger who has paid.

The events are checked as the state they leave; speech isn't mirrored (research R3), so a tap
that "only speaks" is checked as one that changes nothing.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import (
    ok,
    passenger,
    rejects,
    set_reputation,
    start_trip,
    step_to_seconds,
)
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import RejectionCode, ResolveClaim, Tap
from wassal_solver.engine.model import AlightOutcome, RepCause, TripStatus


def _claimer(*, pays_at: int | None = 1) -> Trip:
    return start_trip(
        TripBuilder()
        .station("gamaa", 30)
        .passenger(
            "p1",
            seat="A_r",
            dest="gamaa",
            payment=[1000],
            pays_at=pays_at,
            archetype="false_claimer",
        )
        .build()
    )


def _paid(*, no_fights_required: bool = False) -> Trip:
    """p1 pays exactly at 1 s, so a tap after that opens a truthful claim."""
    builder = (
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
    )
    if no_fights_required:
        builder.rules(no_fights_required=True)
    trip = start_trip(builder.build())
    step_to_seconds(trip, 5)
    return trip


def _assert_tap_changes_nothing(trip: Trip) -> None:
    before = trip.state.to_json()
    ok(trip, Tap("p1"))
    after = trip.state.to_json()
    assert after == {**before, "commands_accepted": after["commands_accepted"]}


class TestAFalseClaimer:
    def test_claims_at_their_payment_time_instead_of_paying(self) -> None:
        trip = _claimer()
        trip.step_to(1023)
        assert list(trip.state.claims) == ["p1"]
        assert not trip.state.claims["p1"].truthful
        assert not passenger(trip, "p1").fare_sent
        assert trip.state.tokens == {}

    def test_claims_when_tapped(self) -> None:
        trip = _claimer(pays_at=None)
        ok(trip, Tap("p1"))
        assert list(trip.state.claims) == ["p1"]
        assert trip.state.tokens == {}

    def test_a_tap_while_the_claim_is_open_has_no_effect(self) -> None:
        trip = _claimer()
        trip.step_to(1023)
        rejects(trip, Tap("p1"), RejectionCode.NO_EFFECT)

    def test_insisting_catches_the_liar_reputation_a_count_and_they_pay(self) -> None:
        trip = _claimer()
        trip.step_to(1023)
        set_reputation(trip, 80)
        ok(trip, ResolveClaim("p1", insist=True))
        assert trip.params.rep_liar_caught == 10
        assert trip.state.reputation == 90
        assert RepCause.LIAR_CAUGHT not in trip.state.reputation_lost, "a gain"
        (fare,) = trip.state.tokens.values()
        assert (fare.owner, fare.pieces.total) == ("p1", 1000)
        assert trip.state.counters.caught_liars == 1
        assert trip.state.claims == {}
        assert passenger(trip, "p1").claim_resolved
        # Dart also checks the speech: caught, then pays.

    def test_believing_them_makes_them_never_pay_and_they_leave_unpaid(self) -> None:
        trip = _claimer()
        trip.step_to(1023)
        ok(trip, ResolveClaim("p1", insist=False))
        assert trip.state.claims == {}
        assert passenger(trip, "p1").never_pays
        _assert_tap_changes_nothing(trip)
        step_to_seconds(trip, 40)
        assert passenger(trip, "p1").outcome == AlightOutcome.LEFT_UNPAID
        assert trip.result is not None
        assert trip.result.lost_fares == 1

    def test_an_open_claim_at_their_stop_counts_as_accepted(self) -> None:
        trip = _claimer()
        trip.step_to(1023)
        while trip.state.next_station_index == 0:
            assert list(trip.state.claims) == ["p1"], f"open until gamaa, at {trip.t_ms}"
            trip.step()
        assert trip.state.claims == {}, "accepted at the step gamaa is reached"
        assert passenger(trip, "p1").never_pays
        step_to_seconds(trip, 40)
        assert passenger(trip, "p1").outcome == AlightOutcome.LEFT_UNPAID
        assert trip.state.claims == {}
        # Dart also checks that `claims_paid` is said once.


class TestATruthfulClaim:
    def test_a_tap_on_a_passenger_who_has_paid_opens_one(self) -> None:
        trip = _paid()
        ok(trip, Tap("p1"))
        assert list(trip.state.claims) == ["p1"]
        assert trip.state.claims["p1"].truthful

    def test_insisting_is_a_false_accusation_reputation_and_a_fight(self) -> None:
        trip = _paid()
        ok(trip, Tap("p1"))
        ok(trip, ResolveClaim("p1", insist=True))
        assert trip.state.reputation_lost == {
            RepCause.FALSE_ACCUSATION: trip.params.rep_false_accusation
        }
        assert trip.state.counters.fights == 1
        step_to_seconds(trip, 40)
        assert trip.result is not None
        assert trip.result.stars == 1
        # Dart also checks that p1 says `accused`.

    def test_a_false_accusation_fails_a_no_fights_trip(self) -> None:
        trip = _paid(no_fights_required=True)
        ok(trip, Tap("p1"))
        ok(trip, ResolveClaim("p1", insist=True))
        assert trip.status == TripStatus.FAILED
        assert not trip.state.revivable

    def test_one_resolved_claim_per_passenger_later_taps_only_speak(self) -> None:
        trip = _paid()
        ok(trip, Tap("p1"))
        ok(trip, ResolveClaim("p1", insist=False))
        _assert_tap_changes_nothing(trip)
        assert trip.state.claims == {}


def test_resolve_claim_with_no_open_claim_is_no_choice() -> None:
    rejects(_paid(), ResolveClaim("p1", insist=True), RejectionCode.NO_CHOICE)
