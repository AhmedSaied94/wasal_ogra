"""Judging change (RULES.md §6.5), ported from `test/rules/change_test.dart`: exact, short, over
and not owed, and the honest passenger's returns.

Dart reads the judgement from the `ChangeDelivered` event. The mirror has no events (research R3),
so each case checks what the judgement changes: the balance, the reputation and its causes, the
mistakes, what was overpaid, and any token sent back. Speech isn't mirrored.
"""

from __future__ import annotations

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, set_reputation, start_trip, step_to_seconds
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import PickFromTray, SendHand
from wassal_solver.engine.model import DRIVER, MistakeKind, RepCause, TokenKind
from wassal_solver.engine.money import Pieces


def trip(*, archetype: str = "regular", payment: list[int] | None = None) -> Trip:
    """p1 (A_r) pays 1000 for an 850 fare at 0 s; the fare reaches the tray at 1155 ms. p2 (A_m)
    never pays."""
    run = start_trip(
        TripBuilder()
        .station("gamaa", 60, fare=850)
        .passenger(
            "p1",
            archetype=archetype,
            seat="A_r",
            dest="gamaa",
            payment=[1000] if payment is None else payment,
            pays_at=0,
        )
        .passenger("p2", archetype=archetype, seat="A_m", dest="gamaa", payment=[1000])
        .build()
    )
    run.step_to(1155)
    return run


def give(run: Trip, passenger_id: str, pieces: list[int]) -> int:
    """Picks `pieces`, sends them to `passenger_id`, and steps until the change is judged: its
    token is gone. Returns the token's id."""
    for piece in pieces:
        ok(run, PickFromTray(piece))
    ok(run, SendHand(passenger_id))
    assert run.state.last_send is not None
    token_id = run.state.last_send.token_id
    for _ in range(100):
        if token_id not in run.state.tokens:
            break
        run.step()
    assert token_id not in run.state.tokens, "the change was never judged"
    return token_id


class TestExact:
    def test_settles_the_passenger_and_rewards_rep_exact_change(self) -> None:
        run = trip()
        set_reputation(run, 90)
        give(run, "p1", [100, 50])
        assert passenger(run, "p1").balance == 0
        assert run.state.reputation == 93
        assert run.state.reputation_lost == {}, "a gain isn't recorded"
        assert run.state.mistakes == []
        assert run.state.counters.overpaid_piasters == 0

    def test_the_reward_is_capped_at_100(self) -> None:
        run = trip()
        set_reputation(run, 99)
        give(run, "p1", [100, 50])
        assert run.state.reputation == 100


def test_short_change_costs_rep_short_change_and_a_settling_top_up_is_exact() -> None:
    run = trip()
    give(run, "p1", [100])
    assert passenger(run, "p1").balance == 50
    assert run.state.reputation == 95
    assert run.state.reputation_lost == {RepCause.SHORT_CHANGE: 5}
    give(run, "p1", [50])
    assert passenger(run, "p1").balance == 0
    assert run.state.reputation == 98
    assert run.state.mistakes == []


class TestOver:
    def test_records_the_excess_as_a_mistake_kept_by_a_regular_passenger(self) -> None:
        run = trip()
        give(run, "p1", [100, 100])
        assert passenger(run, "p1").balance == 0
        assert [m.to_json() for m in run.state.mistakes] == [
            {"passenger_id": "p1", "kind": "over", "amount_piasters": 50}
        ]
        assert run.state.counters.overpaid_piasters == 50
        assert run.state.reputation == 100
        assert run.state.tokens == {}

    def test_an_honest_passenger_returns_the_excess_in_the_fewest_pieces_to_the_tray(self) -> None:
        run = trip(archetype="honest")
        give(run, "p1", [100, 100])
        (back,) = run.state.tokens.values()
        assert (back.kind, back.pieces, back.target, back.owner) == (
            TokenKind.RETURNED,
            Pieces.of({50: 1}),
            DRIVER,
            "p1",
        )
        tray = run.state.tray
        step_to_seconds(run, 5)
        assert run.state.tokens == {}
        assert run.state.tray == tray.plus_one(50)
        assert run.state.counters.overpaid_piasters == 0
        assert [m.kind for m in run.state.mistakes] == [MistakeKind.OVER]


class TestNotOwed:
    def test_change_to_a_passenger_who_has_not_paid_is_a_mistake_of_the_whole_token(
        self,
    ) -> None:
        run = trip()
        give(run, "p2", [100])
        assert [m.to_json() for m in run.state.mistakes] == [
            {"passenger_id": "p2", "kind": "not_owed", "amount_piasters": 100}
        ]
        assert run.state.counters.overpaid_piasters == 100
        assert passenger(run, "p2").balance == 0

    def test_change_to_a_passenger_owed_nothing_is_not_owed(self) -> None:
        run = trip(payment=[500, 100, 100, 100, 50])
        give(run, "p1", [50])
        assert [(m.passenger_id, m.kind, m.amount_piasters) for m in run.state.mistakes] == [
            ("p1", MistakeKind.NOT_OWED, 50)
        ]
        assert run.state.counters.overpaid_piasters == 50

    def test_an_honest_passenger_sends_the_same_pieces_back(self) -> None:
        run = trip(archetype="honest")
        give(run, "p2", [100])
        (back,) = run.state.tokens.values()
        assert (back.kind, back.pieces) == (TokenKind.RETURNED, Pieces.of({100: 1}))
        step_to_seconds(run, 5)
        assert run.state.counters.overpaid_piasters == 0
        assert [m.kind for m in run.state.mistakes] == [MistakeKind.NOT_OWED]


def test_two_tokens_to_the_same_passenger_are_judged_in_arrival_order() -> None:
    run = trip()
    ok(run, PickFromTray(100))
    ok(run, SendHand("p1"))
    ok(run, PickFromTray(50))
    ok(run, SendHand("p1"))
    step_to_seconds(run, 5)
    # Token 2 is short (150 owed, 100 given), then token 3 is exact.
    assert passenger(run, "p1").balance == 0
    assert run.state.reputation == 100 - 5 + 3
    assert run.state.reputation_lost == {RepCause.SHORT_CHANGE: 5}
    assert run.state.mistakes == []


def test_tokens_arriving_in_the_same_step_are_judged_in_id_order() -> None:
    # Not in the Dart file: amounts whose order shows in the mistakes. Judged in id order, 200 is
    # 50 over and then 50 isn't owed; the other way, 50 would be short and 200 100 over.
    run = trip()
    ok(run, PickFromTray(100))
    ok(run, PickFromTray(100))
    ok(run, SendHand("p1"))
    ok(run, PickFromTray(50))
    ok(run, SendHand("p1"))
    step_to_seconds(run, 5)
    assert [(m.kind, m.amount_piasters) for m in run.state.mistakes] == [
        (MistakeKind.OVER, 50),
        (MistakeKind.NOT_OWED, 50),
    ]
