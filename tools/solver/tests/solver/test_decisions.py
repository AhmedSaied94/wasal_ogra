"""The idealized player's decisions (contracts/solver.md §2, research R7)."""

from __future__ import annotations

import pytest

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, start_trip
from tests.support.solving import settings_with
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import (
    Abandon,
    CollectDropped,
    PickFromTray,
    RequestBreak,
    ResolveChangeRequest,
    ResolveClaim,
    ResolveDispute,
    Revive,
    SendHand,
    Tap,
    UndoLastSend,
    UseBooster,
)
from wassal_solver.engine.model import ChangeRequest, Claim, Dispute, PendingBreak
from wassal_solver.engine.money import Pieces
from wassal_solver.engine.trip import start
from wassal_solver.settings import load_settings
from wassal_solver.solver.decisions import (
    Decision,
    DecisionKind,
    Timing,
    certain_loss,
    compositions,
    possible_decisions,
    round_to_step,
)
from wassal_solver.solver.search import _Branch, _Is, _Search
from wassal_solver.tunables import bundled_params

K = DecisionKind


def trip_of(builder: TripBuilder) -> Trip:
    return start_trip(builder.build())


def two_riders(*, archetype: str = "regular", tray: dict[int, int] | None = None) -> Trip:
    """p1 (A_r) to gamaa at 30 s and p2 (A_l) to souq at 60 s, both paying 1000."""
    builder = (
        TripBuilder()
        .station("gamaa", 30)
        .station("souq", 60)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], archetype=archetype)
        .passenger("p2", seat="A_l", dest="souq", payment=[1000])
    )
    if tray is not None:
        builder.tray(tray)
    return trip_of(builder)


def kinds(trip: Trip) -> list[tuple[DecisionKind, str | None]]:
    return [(d.kind, d.passenger_id) for d in possible_decisions(trip)]


def paid(trip: Trip, passenger_id: str) -> Trip:
    """`passenger_id` has paid: a tap, then the fare reaches the tray."""
    ok(trip, Tap(passenger_id))
    trip.step_to(trip.t_ms + 3000)
    return trip


# --- Timing ---------------------------------------------------------------------------------


def test_the_times_round_up_to_whole_steps() -> None:
    assert Timing.of(load_settings()) == Timing(627, 198)
    assert Timing.of(settings_with(reaction_ms=100, tap_ms=0)) == Timing(132, 0)
    assert round_to_step(0) == 0
    assert round_to_step(33) == 33
    assert round_to_step(34) == 66


def test_a_decision_waits_a_reaction_time_after_the_last_and_after_it_became_possible() -> None:
    timing = Timing(627, 198)
    assert timing.first_command_at(0, 0) == 627
    assert timing.first_command_at(1000, 2000) == 2627
    assert timing.first_command_at(3000, 2000) == 3627


# --- One case per row of the decisions table ---------------------------------------------


def test_collect_fare_is_a_tap_on_an_able_passenger_who_has_not_paid() -> None:
    trip = two_riders()
    assert kinds(trip) == [(K.COLLECT_FARE, "p1"), (K.COLLECT_FARE, "p2")]
    assert Decision(K.COLLECT_FARE, "p1").commands() == (Tap("p1"),)
    paid(trip, "p1")
    assert (K.COLLECT_FARE, "p1") not in kinds(trip)


def test_collect_fare_waits_for_an_open_claim() -> None:
    trip = two_riders()
    trip.state.claims["p1"] = Claim(truthful=False)
    assert (K.COLLECT_FARE, "p1") not in kinds(trip)


def test_collect_rest_is_a_tap_on_a_passenger_who_owes_the_driver() -> None:
    trip = two_riders()
    rider = passenger(trip, "p1")
    rider.fare_sent = True
    rider.balance = -100
    assert (K.COLLECT_REST, "p1") in kinds(trip)
    assert Decision(K.COLLECT_REST, "p1").commands() == (Tap("p1"),)


def test_wake_is_a_tap_on_a_sleeper() -> None:
    trip = two_riders(archetype="sleeper")
    assert kinds(trip)[0] == (K.WAKE, "p1")
    assert (K.COLLECT_FARE, "p1") not in kinds(trip)
    assert Decision(K.WAKE, "p1").commands() == (Tap("p1"),)


def test_call_is_two_taps_on_a_passenger_in_headphones() -> None:
    trip = two_riders(archetype="headphones")
    assert kinds(trip)[0] == (K.CALL, "p1")
    assert Decision(K.CALL, "p1").commands() == (Tap("p1"), Tap("p1"))


def test_give_change_picks_each_piece_largest_first_then_sends() -> None:
    decision = Decision(K.GIVE_CHANGE, "p1", pieces=Pieces.of({500: 1, 100: 2}))
    assert decision.commands() == (
        PickFromTray(500),
        PickFromTray(100),
        PickFromTray(100),
        SendHand("p1"),
    )


def test_give_change_offers_only_exact_change_from_the_tray() -> None:
    trip = paid(two_riders(), "p1")
    owed = passenger(trip, "p1").balance
    changes = [d for d in possible_decisions(trip) if d.kind is K.GIVE_CHANGE]
    assert changes
    for decision in changes:
        assert decision.passenger_id == "p1"
        assert decision.pieces is not None
        assert decision.pieces.total == owed
        assert trip.state.tray.contains(decision.pieces)
    assert [d.pieces for d in changes] == list(compositions(owed, trip.state.tray))


def test_give_change_needs_an_empty_hand_and_no_change_on_its_way() -> None:
    trip = paid(two_riders(), "p1")
    ok(trip, PickFromTray(100))
    assert K.GIVE_CHANGE not in [d.kind for d in possible_decisions(trip)]
    ok(trip, PickFromTray(100))
    ok(trip, PickFromTray(100))
    ok(trip, SendHand("p1"))
    assert K.GIVE_CHANGE not in [d.kind for d in possible_decisions(trip)]


def test_give_change_is_never_for_a_passenger_who_is_not_owed() -> None:
    trip = two_riders()
    assert K.GIVE_CHANGE not in [d.kind for d in possible_decisions(trip)]
    exact = trip_of(
        TripBuilder()
        .station("gamaa", 30, fare=500)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500])
    )
    paid(exact, "p1")
    assert passenger(exact, "p1").fare_sent
    assert K.GIVE_CHANGE not in [d.kind for d in possible_decisions(exact)]


def test_request_break_comes_while_the_tray_cannot_make_someones_change() -> None:
    trip = paid(two_riders(tray={500: 2}), "p1")
    assert trip.state.tray.count(1000) == 1
    breaks = [d for d in possible_decisions(trip) if d.kind is K.REQUEST_BREAK]
    assert breaks == [Decision(K.REQUEST_BREAK, denomination=1000)]
    assert breaks[0].commands() == (RequestBreak(1000),)


def test_request_break_waits_for_a_pending_break_and_stops_when_none_are_left() -> None:
    trip = paid(two_riders(tray={500: 2}), "p1")
    trip.state.pending_breaks.append(PendingBreak(1000, trip.t_ms + 1000))
    assert K.REQUEST_BREAK not in [d.kind for d in possible_decisions(trip)]
    trip.state.pending_breaks.clear()
    trip.state.breaks_used = 2
    assert K.REQUEST_BREAK not in [d.kind for d in possible_decisions(trip)]


def test_request_break_is_not_offered_while_change_can_be_made() -> None:
    trip = paid(two_riders(), "p1")
    assert K.REQUEST_BREAK not in [d.kind for d in possible_decisions(trip)]


def test_pick_up_collects_a_dropped_token() -> None:
    trip = two_riders()
    ok(trip, Tap("p1"))
    trip.step()
    trip.step()
    token = next(iter(trip.state.tokens.values()))
    token.hop_to = None
    token.dropped_until_ms = trip.t_ms + 3000
    decision = Decision(K.PICK_UP, token_id=token.token_id)
    assert decision in possible_decisions(trip)
    assert decision.commands() == (CollectDropped(token.token_id),)


@pytest.mark.parametrize("truthful", [True, False])
def test_answer_claim_insists_exactly_when_the_claim_is_false(truthful: bool) -> None:
    trip = two_riders()
    trip.state.claims["p1"] = Claim(truthful=truthful)
    decision = possible_decisions(trip)[0]
    assert decision == Decision(K.ANSWER_CLAIM, "p1", answer=not truthful)
    assert decision.commands() == (ResolveClaim("p1", insist=not truthful),)


def test_answer_dispute_names_the_passenger_who_sent_their_fare() -> None:
    trip = two_riders()
    trip.state.disputes[0] = Dispute(a="p1", b="p2")
    assert K.ANSWER_DISPUTE not in [d.kind for d in possible_decisions(trip)]
    ok(trip, Tap("p2"))
    decision = possible_decisions(trip)[0]
    assert decision == Decision(K.ANSWER_DISPUTE, dispute_id=0, answer="p2")
    assert decision.commands() == (ResolveDispute(0, "p2"),)
    ok(trip, Tap("p1"))
    assert K.ANSWER_DISPUTE not in [d.kind for d in possible_decisions(trip)]


def test_answer_change_request_agrees_first_when_the_tray_can() -> None:
    trip = two_riders()
    trip.state.change_requests["p1"] = ChangeRequest(1000)
    answers = [d for d in possible_decisions(trip) if d.kind is K.ANSWER_CHANGE_REQUEST]
    assert answers == [
        Decision(K.ANSWER_CHANGE_REQUEST, "p1", answer=True),
        Decision(K.ANSWER_CHANGE_REQUEST, "p1", answer=False),
    ]
    assert answers[0].commands() == (ResolveChangeRequest("p1", agree=True),)
    trip.state.tray = Pieces.of({500: 1})
    answers = [d for d in possible_decisions(trip) if d.kind is K.ANSWER_CHANGE_REQUEST]
    assert answers == [Decision(K.ANSWER_CHANGE_REQUEST, "p1", answer=False)]


# --- Ordering -----------------------------------------------------------------------------


def test_compositions_are_ordered_by_pieces_then_small_pieces_left_then_largest_first() -> None:
    tray = Pieces.of({1000: 1, 500: 2, 100: 1, 50: 2})
    assert [c.to_list() for c in compositions(1100, tray)] == [
        [100, 1000],
        [100, 500, 500],
        [50, 50, 1000],
        [50, 50, 500, 500],
    ]
    tray = Pieces.of({2000: 1, 1000: 3, 500: 2})
    assert [c.to_list() for c in compositions(3000, tray)][:3] == [
        [1000, 2000],
        [500, 500, 2000],
        [1000, 1000, 1000],
    ]
    assert compositions(0, tray) == ()
    assert compositions(50, tray) == ()


def test_forced_answers_come_first_then_passengers_by_their_soonest_stop() -> None:
    trip = trip_of(
        TripBuilder()
        .station("gamaa", 30)
        .station("souq", 60)
        .passenger("p1", seat="A_r", dest="souq", payment=[1000])
        .passenger("p2", seat="A_l", dest="gamaa", payment=[1000])
        .passenger("p3", seat="A_m", dest="gamaa", payment=[1000])
    )
    trip.state.claims["p3"] = Claim(truthful=False)
    assert kinds(trip) == [
        (K.ANSWER_CLAIM, "p3"),
        (K.COLLECT_FARE, "p2"),
        (K.COLLECT_FARE, "p1"),
    ]


def test_breaks_come_after_the_passengers_and_change_requests_last() -> None:
    trip = paid(two_riders(tray={500: 2}), "p1")
    trip.state.change_requests["p2"] = ChangeRequest(1000)
    assert [kind for kind, _ in kinds(trip)] == [
        K.COLLECT_FARE,
        K.REQUEST_BREAK,
        K.ANSWER_CHANGE_REQUEST,
        K.ANSWER_CHANGE_REQUEST,
    ]


# --- What the player never does -----------------------------------------------------------


def test_no_decision_uses_an_aid() -> None:
    every = [
        Decision(K.COLLECT_FARE, "p1"),
        Decision(K.COLLECT_REST, "p1"),
        Decision(K.WAKE, "p1"),
        Decision(K.CALL, "p1"),
        Decision(K.GIVE_CHANGE, "p1", pieces=Pieces.of({100: 1})),
        Decision(K.REQUEST_BREAK, denomination=1000),
        Decision(K.PICK_UP, token_id=1),
        Decision(K.ANSWER_CLAIM, "p1", answer=True),
        Decision(K.ANSWER_DISPUTE, dispute_id=0, answer="p1"),
        Decision(K.ANSWER_CHANGE_REQUEST, "p1", answer=False),
    ]
    assert {d.kind for d in every} == set(DecisionKind)
    aids = (UseBooster, Revive, UndoLastSend, Abandon)
    for decision in every:
        assert not any(isinstance(command, aids) for command in decision.commands())


def test_a_decision_missing_its_fields_is_an_error() -> None:
    with pytest.raises(ValueError, match="give_change"):
        Decision(K.GIVE_CHANGE, "p1").commands()


def test_a_command_rejected_partway_through_a_decision_drops_the_branch() -> None:
    definition = (
        TripBuilder()
        .station("gamaa", 30)
        .tray({500: 2})
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000])
        .build()
    )
    trip = start(definition, bundled_params(definition.line_id), definition.seed)
    search = _Search(load_settings())
    branch = _Branch(trip)
    search.observe(branch)
    decision = Decision(K.GIVE_CHANGE, "p1", pieces=Pieces.of({500: 1, 50: 1}))
    assert search.decide(branch, decision, prune=True) is _Is.DROPPED
    assert [entry.command for entry in trip.command_log] == [PickFromTray(500)]


def test_decisions_describe_themselves() -> None:
    decision = Decision(K.GIVE_CHANGE, "p1", pieces=Pieces.of({100: 3}))
    assert decision.to_json() == {"kind": "give_change", "passenger_id": "p1", "pieces": {"100": 3}}
    assert Decision(K.ANSWER_DISPUTE, dispute_id=2, answer="p4").to_json() == {
        "kind": "answer_dispute",
        "dispute_id": 2,
        "answer": "p4",
    }
    assert Decision(K.REQUEST_BREAK, denomination=1000).to_json() == {
        "kind": "request_break",
        "denomination": 1000,
    }
    assert Decision(K.PICK_UP, token_id=3).to_json() == {"kind": "pick_up", "token_id": 3}


# --- A certain loss (contracts/solver.md §3) -------------------------------------------------


def stuck(**rules: int) -> Trip:
    """p1 owes nothing yet; p2 is owed 300 that a tray of 500s can't make."""
    builder = (
        TripBuilder()
        .station("gamaa", 30)
        .tray({500: 2})
        .rules(max_break_requests=rules.get("breaks", 0))
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100])
        .passenger("p2", seat="A_l", dest="gamaa", payment=[1000])
    )
    trip = trip_of(builder)
    paid(trip, "p1")
    return paid(trip, "p2")


def test_a_passenger_owed_change_that_can_never_be_made_is_a_certain_loss() -> None:
    trip = stuck()
    assert certain_loss(trip) == ("p2", round_to_step(30_000))


def test_a_break_left_to_ask_for_is_a_way_out() -> None:
    trip = stuck(breaks=1)
    assert trip.state.tray.count(1000) == 1
    assert certain_loss(trip) is None


def test_money_in_transit_or_in_the_hand_is_a_way_out() -> None:
    trip = stuck()
    ok(trip, PickFromTray(500))
    assert certain_loss(trip) is None
    ok(trip, SendHand("p1"))
    assert certain_loss(trip) is None


def test_a_passenger_still_to_pay_or_an_event_still_to_fire_is_a_way_out() -> None:
    trip = trip_of(
        TripBuilder()
        .station("gamaa", 30)
        .tray({500: 2})
        .rules(max_break_requests=0)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000])
        .passenger("p2", seat="A_l", dest="gamaa", payment=[1000])
        .event("traffic", 20, seconds=5)
    )
    paid(trip, "p1")
    assert certain_loss(trip) is None
    paid(trip, "p2")
    assert certain_loss(trip) is None
    trip.step_to(20_100)
    assert certain_loss(trip) is not None
