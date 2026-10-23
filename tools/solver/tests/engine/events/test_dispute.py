"""payment_dispute (RULES.md §4.7, §6.2, §8), ported from `dispute_test.dart`: two passengers each
say they paid; the driver names the one who did. It needs a liar: exactly one of the two has paid
when it fires, and it closes if the other pays.
"""

from __future__ import annotations

import pytest

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
from wassal_solver.engine.commands import RejectionCode, ResolveDispute, Tap
from wassal_solver.engine.model import Dispute, RepCause, TokenKind, TripStatus


def started(*, p1_pays: bool = True, p2_pays: bool = False) -> Trip:
    """p1 pays at 1 s unless `p1_pays` is false; p2 only when `p2_pays`. The dispute is at 5 s."""
    return start_trip(
        TripBuilder()
        .station("kobri", 10)
        .station("gamaa", 40)
        .passenger(
            "p1",
            seat="A_r",
            dest="gamaa",
            payment=[500, 100, 100],
            pays_at=1 if p1_pays else None,
        )
        .passenger(
            "p2",
            seat="A_m",
            dest="gamaa",
            payment=[500, 100, 100],
            pays_at=2 if p2_pays else None,
        )
        .passenger("p3", seat="A_l", dest="kobri", payment=[500, 100, 100], pays_at=3)
        .event("payment_dispute", 5, passengers=["p1", "p2"])
        .build()
    )


def disputed() -> Trip:
    """The dispute open between p1, who paid, and p2, who didn't."""
    trip = started()
    step_to_seconds(trip, 6)
    return trip


def test_it_opens_under_its_event_index() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 40)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1)
        .passenger("p2", seat="A_m", dest="gamaa", payment=[1000])
        .event("payment_dispute", 5, passengers=["p1", "p2"])
        .build()
    )
    step_to_seconds(trip, 6)
    # Dart also checks that both passengers speak, which isn't mirrored.
    assert trip.state.disputes == {0: Dispute(a="p1", b="p2")}


def test_the_right_answer_the_other_pays_and_the_liar_is_caught() -> None:
    trip = disputed()
    set_reputation(trip, 80)
    tokens = set(trip.state.tokens)
    ok(trip, ResolveDispute(0, "p1"))
    new = [token for key, token in trip.state.tokens.items() if key not in tokens]
    assert [(token.kind, token.owner) for token in new] == [(TokenKind.FARE, "p2")]
    assert passenger(trip, "p2").fare_sent
    assert trip.state.reputation == 90
    assert trip.state.counters.caught_liars == 1
    assert trip.state.counters.fights == 0
    assert trip.state.disputes == {}


def test_a_wrong_answer_is_a_false_accusation_against_the_other() -> None:
    trip = disputed()
    ok(trip, ResolveDispute(0, "p2"))
    # Dart names the accused passenger from its FalseAccusation event and their speech; the state
    # keeps the fight and the penalty, and the accused doesn't pay again.
    assert trip.state.counters.fights == 1
    assert trip.state.counters.caught_liars == 0
    assert trip.state.reputation_lost == {
        RepCause.FALSE_ACCUSATION: trip.params.rep_false_accusation
    }
    assert passenger(trip, "p1").fare_sent
    assert trip.state.disputes == {}


@pytest.mark.parametrize(
    ("p1_pays", "p2_pays"),
    [(True, True), (False, False)],
    ids=["both have paid", "neither has paid"],
)
def test_with_no_liar_it_is_skipped(p1_pays: bool, p2_pays: bool) -> None:
    trip = started(p1_pays=p1_pays, p2_pays=p2_pays)
    step_to_seconds(trip, 6)
    # Dart also checks EventSkipped and that no one says `dispute`, which aren't mirrored.
    assert trip.state.events_fired[0]
    assert trip.state.disputes == {}
    rejects(trip, ResolveDispute(0, "p1"), RejectionCode.NO_CHOICE)


def test_it_closes_when_the_other_pays() -> None:
    trip = disputed()
    ok(trip, Tap("p2"))
    assert passenger(trip, "p2").fare_sent
    assert trip.state.disputes == {}
    assert trip.state.counters.caught_liars == 0
    assert trip.state.counters.fights == 0
    rejects(trip, ResolveDispute(0, "p1"), RejectionCode.NO_CHOICE)


def test_a_third_passenger_is_a_bad_argument() -> None:
    rejects(disputed(), ResolveDispute(0, "p3"), RejectionCode.BAD_ARGUMENT)


def test_once_resolved_there_is_no_choice() -> None:
    trip = disputed()
    ok(trip, ResolveDispute(0, "p1"))
    rejects(trip, ResolveDispute(0, "p1"), RejectionCode.NO_CHOICE)
    rejects(trip, ResolveDispute(7, "p1"), RejectionCode.NO_CHOICE)


def test_it_is_dropped_when_either_passenger_gets_off() -> None:
    trip = start_trip(
        TripBuilder()
        .station("kobri", 10)
        .station("gamaa", 40)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
        .passenger("p2", seat="A_m", dest="kobri", payment=[500, 100, 100])
        .event("payment_dispute", 5, passengers=["p1", "p2"])
        .build()
    )
    step_to_seconds(trip, 6)
    assert list(trip.state.disputes) == [0]
    step_to_seconds(trip, 12)
    assert trip.state.disputes == {}
    # Not resolved: no one is caught or accused.
    assert trip.state.counters.caught_liars == 0
    assert RepCause.FALSE_ACCUSATION not in trip.state.reputation_lost
    rejects(trip, ResolveDispute(0, "p1"), RejectionCode.NO_CHOICE)


def test_it_may_be_resolved_while_paused() -> None:
    trip = disputed()
    trip.state.status = TripStatus.PAUSED
    assert trip.apply(ResolveDispute(0, "p1")) is None
    assert trip.status == TripStatus.PAUSED
