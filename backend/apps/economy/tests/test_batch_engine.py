"""The batch engine with fake operations (B03 tasks.md T015, research R5).

The operations here are registered by the test, so the engine's own rules (order, idempotency,
expiry, validation, atomicity, the state version) are checked apart from any real operation.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import timedelta
from typing import Any

import pytest
import time_machine
from django.db import DataError
from django.utils import timezone
from pytest_django import Settings

from apps.accounts.models import Player
from apps.economy.models import Currency, LedgerEntry, PlayerFlag, ProcessedOp, Wallet
from apps.economy.services import sync
from apps.economy.services.batch import BatchState
from apps.economy.services.payloads import Field
from apps.economy.services.sync import Ctx, Rejected, process_batch
from apps.economy.services.timeline import to_ms
from apps.economy.tests.helpers import as_ops, ledger_sum, op, uuid7_at, wallet_of

CREDIT = "test_credit"
REFUSE = "test_refuse"
SNEAK = "test_sneak"
BREAK = "test_break"
VERSIONED = "test_versioned"

pytestmark = pytest.mark.django_db


def credit(state: BatchState, ctx: Ctx) -> list[dict[str, Any]]:
    state.credit(
        Currency.JENEHAT,
        ctx.payload["amount"],
        LedgerEntry.Reason.TRIP_EARNINGS,
        ref_type="test",
        ref_id=str(ctx.client_txn_id),
    )
    return [{"jenehat_after": state.jenehat, "t_ms": ctx.t_ms}]


def refuse(state: BatchState, ctx: Ctx) -> None:
    raise Rejected("insufficient_funds")


def sneak(state: BatchState, ctx: Ctx) -> None:
    state.credit(Currency.JENEHAT, 1, LedgerEntry.Reason.TRIP_EARNINGS)
    raise Rejected("insufficient_funds")


def break_flush(state: BatchState, ctx: Ctx) -> None:
    # Longer than the column: accepted in memory, refused by PostgreSQL at the flush.
    state.add_ownership("item", "x" * 100, "", ctx.t)


@pytest.fixture(autouse=True)
def fake_ops() -> Iterator[None]:
    amount = {"amount": Field("int", minimum=1, maximum=1000)}
    sync.register(CREDIT, payload={**amount, "note": Field("str", required=False)})(credit)
    sync.register(REFUSE, payload={})(refuse)
    sync.register(SNEAK, payload={})(sneak)
    sync.register(BREAK, payload={})(break_flush)
    sync.register(
        VERSIONED, payload={"content_version": sync.CONTENT_VERSION}, content_version=True
    )(refuse)
    yield
    for op_type in (CREDIT, REFUSE, SNEAK, BREAK, VERSIONED):
        sync.unregister(op_type)


def run(player: Player, *envelopes: dict[str, Any], base: int = 0) -> sync.BatchResult:
    return process_batch(player, base, as_ops(envelopes))


def statuses(result: sync.BatchResult) -> list[tuple[str, str]]:
    return [(r.outcome.status, r.outcome.reason) for r in result.results]


# -- the wallet ------------------------------------------------------------------------------------


def test_the_wallet_is_created_on_first_use(player: Player, settings: Settings) -> None:
    assert not Wallet.objects.filter(pk=player.pk).exists()
    result = run(player)
    wallet = wallet_of(player)
    assert (wallet.jenehat, wallet.bonat, wallet.state_version) == (0, 0, 0)
    assert wallet.fuel == settings.ECONOMY_FUEL_MAX
    assert result.state_version == 0
    assert result.wallet["fuel"] == settings.ECONOMY_FUEL_MAX
    assert wallet.last_active_at is not None


def test_a_batch_holds_at_most_100_operations(player: Player) -> None:
    with pytest.raises(ValueError, match="at most 100"):
        run(player, *[op(CREDIT, {"amount": 1}) for _ in range(101)])


# -- order and rejection ---------------------------------------------------------------------------


def test_operations_run_in_order_and_a_rejection_does_not_stop_the_batch(player: Player) -> None:
    first, refused, last = op(CREDIT, {"amount": 5}), op(REFUSE, {}), op(CREDIT, {"amount": 7})
    result = run(player, first, refused, last)
    assert statuses(result) == [
        ("accepted", ""),
        ("rejected", "insufficient_funds"),
        ("accepted", ""),
    ]
    assert [r.client_txn_id for r in result.results] == as_ids(first, refused, last)
    assert result.results[0].outcome.granted[0]["jenehat_after"] == 5
    assert result.results[2].outcome.granted[0]["jenehat_after"] == 12
    assert wallet_of(player).jenehat == 12 == ledger_sum(player, Currency.JENEHAT)
    entries = LedgerEntry.objects.filter(player=player).order_by("delta")
    assert [(e.delta, e.op_id) for e in entries] == [
        (5, result.results[0].client_txn_id),
        (7, result.results[2].client_txn_id),
    ]
    stored = ProcessedOp.objects.get(client_txn_id=result.results[1].client_txn_id)
    assert (stored.status, stored.reason, stored.op_type) == (
        "rejected",
        "insufficient_funds",
        REFUSE,
    )
    assert ProcessedOp.objects.filter(player=player).count() == 3


def as_ids(*envelopes: dict[str, Any]) -> list[Any]:
    return [o.client_txn_id for o in as_ops(envelopes)]


def test_a_handler_that_changes_and_then_rejects_is_a_bug(player: Player) -> None:
    with pytest.raises(RuntimeError, match="changed the state and then rejected"):
        run(player, op(CREDIT, {"amount": 5}), op(SNEAK, {}))
    assert not LedgerEntry.objects.filter(player=player).exists()
    assert not ProcessedOp.objects.filter(player=player).exists()


# -- idempotency -----------------------------------------------------------------------------------


def test_a_repeated_batch_returns_the_stored_outcomes_and_applies_nothing(player: Player) -> None:
    envelopes = (op(CREDIT, {"amount": 5}), op(REFUSE, {}))
    first = run(player, *envelopes)
    again = run(player, *envelopes, base=first.state_version)
    assert statuses(again) == statuses(first)
    assert again.results[0].outcome.granted == first.results[0].outcome.granted
    assert again.state_version == first.state_version == 1
    assert not again.state_stale
    assert wallet_of(player).jenehat == 5
    assert LedgerEntry.objects.filter(player=player).count() == 1
    assert ProcessedOp.objects.filter(player=player).count() == 2


def test_the_same_id_twice_in_one_batch_applies_once(player: Player) -> None:
    once = op(CREDIT, {"amount": 5})
    result = run(player, once, once)
    assert statuses(result) == [("accepted", ""), ("accepted", "")]
    assert result.results[1].outcome == result.results[0].outcome
    assert wallet_of(player).jenehat == 5
    assert ProcessedOp.objects.filter(player=player).count() == 1


@pytest.mark.parametrize(
    "changed",
    [
        {"op_type": CREDIT, "payload": {"amount": 9}},
        {"op_type": REFUSE, "payload": {}},
    ],
    ids=["payload", "type"],
)
def test_another_payload_under_a_stored_id_gets_the_stored_outcome_and_a_flag(
    player: Player, changed: dict[str, Any]
) -> None:
    original = op(CREDIT, {"amount": 5})
    run(player, original)
    result = run(player, {**original, **changed})
    assert statuses(result) == [("accepted", "")]
    assert result.results[0].outcome.granted[0]["jenehat_after"] == 5
    assert wallet_of(player).jenehat == 5
    flag = PlayerFlag.objects.get(player=player, kind=PlayerFlag.Kind.TXN_PAYLOAD_MISMATCH)
    assert flag.details == {"client_txn_id": original["client_txn_id"], "count": 1}
    # A flag isn't a change of the player's state.
    assert wallet_of(player).state_version == 1


def test_the_same_payload_with_keys_in_another_order_is_not_a_mismatch(player: Player) -> None:
    original = op(CREDIT, {"amount": 5, "note": "x"})
    run(player, original)
    run(player, {**original, "payload": {"note": "x", "amount": 5}})
    assert not PlayerFlag.objects.filter(player=player).exists()


# -- the common checks -----------------------------------------------------------------------------


def test_an_id_older_than_the_retention_or_from_tomorrow_is_expired(
    player: Player, settings: Settings
) -> None:
    now = timezone.now()
    old = uuid7_at(now - timedelta(days=settings.SYNC_OP_RETENTION_DAYS, minutes=1))
    ahead = uuid7_at(now + timedelta(days=1, minutes=1))
    fine = uuid7_at(now - timedelta(days=settings.SYNC_OP_RETENTION_DAYS - 1))
    result = run(
        player,
        op(CREDIT, {"amount": 1}, txn=old),
        op(CREDIT, {"amount": 1}, txn=ahead),
        op(CREDIT, {"amount": 1}, txn=fine),
    )
    assert statuses(result) == [
        ("rejected", "op_expired"),
        ("rejected", "op_expired"),
        ("accepted", ""),
    ]


def test_an_unregistered_type_is_unknown(player: Player) -> None:
    result = run(player, op("no_such_op", {"amount": 1}))
    assert statuses(result) == [("rejected", "unknown_op_type")]
    assert ProcessedOp.objects.get(player=player).op_type == "no_such_op"


@pytest.mark.parametrize(
    ("payload", "field"),
    [
        ({"amount": 1.0}, "amount"),
        ({"amount": 2.5}, "amount"),
        ({"amount": True}, "amount"),
        ({"amount": "1"}, "amount"),
        ({"amount": 0}, "amount"),
        ({"amount": 1001}, "amount"),
        ({}, "amount"),
        ({"amount": 1, "extra": 1}, "payload"),  # an unknown key is never named
        ({"amount": 1, "note": ""}, "note"),
        ({"amount": 1, "note": "x" * 65}, "note"),
    ],
)
def test_a_payload_of_the_wrong_shape_is_a_validation_error(
    player: Player, payload: dict[str, Any], field: str
) -> None:
    result = run(player, op(CREDIT, payload), op(CREDIT, {"amount": 2}))
    assert statuses(result) == [("rejected", "validation_error"), ("accepted", "")]
    assert result.results[0].outcome.details == {"field": field}
    stored = ProcessedOp.objects.get(client_txn_id=result.results[0].client_txn_id)
    assert (stored.reason, stored.result) == ("validation_error", {"details": {"field": field}})


def test_an_unknown_content_version_is_refused_before_the_handler(player: Player) -> None:
    result = run(player, op(VERSIONED, {"content_version": 999}))
    assert statuses(result) == [("rejected", "unknown_content_version")]


def test_the_checks_run_in_order(player: Player, settings: Settings) -> None:
    old = uuid7_at(timezone.now() - timedelta(days=settings.SYNC_OP_RETENTION_DAYS + 1))
    # Expired comes before an unknown type, and an unknown type before the payload.
    result = run(player, op("no_such_op", {"x": 1.5}, txn=old), op("no_such_op", {"x": 1.5}))
    assert statuses(result) == [("rejected", "op_expired"), ("rejected", "unknown_op_type")]


def test_registering_a_type_twice_or_a_version_without_its_field_fails() -> None:
    with pytest.raises(ValueError, match="registered twice"):
        sync.register(CREDIT, payload={})(credit)
    with pytest.raises(ValueError, match="lacks"):
        sync.register("test_other", payload={}, content_version=True)(credit)
    assert CREDIT in sync.registered()


# -- time ------------------------------------------------------------------------------------------


def test_the_effective_time_never_goes_back_or_past_now(player: Player, settings: Settings) -> None:
    now = timezone.now()
    # The timeline starts at the wallet's creation (contracts/fuel.md "The effective time").
    with time_machine.travel(now - timedelta(hours=1), tick=False):
        run(player)
    later, earlier = now - timedelta(minutes=1), now - timedelta(minutes=10)
    future = now + timedelta(hours=2)
    result = run(
        player,
        op(CREDIT, {"amount": 1}, at=later),
        op(CREDIT, {"amount": 1}, at=earlier),
        op(CREDIT, {"amount": 1}, at=future, txn=uuid7_at(now)),
    )
    times = [r.outcome.granted[0]["t_ms"] for r in result.results]
    assert times[0] == to_ms(later)
    assert times[1] == to_ms(later)  # clamped forward to the timeline
    assert to_ms(now) <= times[2] <= to_ms(timezone.now())  # clamped back to the server's now
    wallet = wallet_of(player)
    assert to_ms(wallet.timeline_at) == times[2]
    # Ten minutes back is under the flag's threshold; two hours ahead is over it.
    assert settings.SYNC_CLOCK_CLAMP_FLAG_MINUTES > 9
    flag = PlayerFlag.objects.get(player=player)
    assert flag.kind == PlayerFlag.Kind.CLOCK_CLAMPED
    assert flag.details["count"] == 1
    assert flag.details["moved_ms"] >= 7_100_000


def test_a_rejected_operation_does_not_move_the_timeline(player: Player) -> None:
    run(player)
    before = wallet_of(player).timeline_at
    run(player, op(REFUSE, {}, at=timezone.now() - timedelta(seconds=1)))
    assert wallet_of(player).timeline_at == before


# -- the state version and atomicity ---------------------------------------------------------------


def test_the_state_version_moves_once_per_batch_that_changed_something(player: Player) -> None:
    changed = run(player, *[op(CREDIT, {"amount": 1}) for _ in range(3)])
    assert changed.state_version == 1
    unchanged = run(player, op(REFUSE, {}), base=1)
    assert unchanged.state_version == 1
    assert not unchanged.state_stale
    stale = run(player, op(CREDIT, {"amount": 1}), base=0)
    assert stale.state_stale
    assert stale.state_version == 2


def test_a_flush_that_fails_stores_nothing(player: Player) -> None:
    run(player, op(CREDIT, {"amount": 3}))
    before = wallet_of(player)
    with pytest.raises(DataError):
        run(player, op(CREDIT, {"amount": 5}), op(REFUSE, {}), op(BREAK, {}), base=1)
    after = wallet_of(player)
    assert (after.jenehat, after.state_version) == (before.jenehat, before.state_version)
    assert ledger_sum(player, Currency.JENEHAT) == 3
    assert ProcessedOp.objects.filter(player=player).count() == 1
