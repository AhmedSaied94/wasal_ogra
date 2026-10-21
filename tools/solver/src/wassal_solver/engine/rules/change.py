"""Judging change that reaches a passenger (RULES.md §6.5).

Mirrors `packages/trip_engine/lib/src/rules/change.dart`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.model import (
    DRIVER,
    Mistake,
    MistakeKind,
    MoneyToken,
    Presence,
    RepCause,
    TokenKind,
)
from wassal_solver.engine.money import Pieces, fewest_pieces
from wassal_solver.engine.rules.reputation import gain_reputation, lose_reputation

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip


def judge_change(tx: Trip, token: MoneyToken) -> None:
    """A `change` or `redirect` `token` of total A reached its target."""
    p = tx.course.passenger_index[token.target]
    if token.kind is TokenKind.CHANGE and _redirect(tx, p, token):
        return
    state = tx.state.passengers[p]
    amount = token.pieces.total
    honest = tx.course.archetype[p] == "honest"
    if not state.fare_sent or state.balance <= 0:
        _mistake(tx, state.passenger_id, MistakeKind.NOT_OWED, amount)
        if honest:
            _give_back(tx, p, token.pieces)
        else:
            tx.state.counters.overpaid_piasters += amount
        return
    if amount == state.balance:
        state.balance = 0
        gain_reputation(tx, RepCause.EXACT_CHANGE, tx.params.rep_exact_change)
    elif amount < state.balance:
        state.balance -= amount
        lose_reputation(tx, RepCause.SHORT_CHANGE, tx.params.rep_short_change)
    else:
        excess = amount - state.balance
        state.balance = 0
        _mistake(tx, state.passenger_id, MistakeKind.OVER, excess)
        if honest:
            _give_back(tx, p, fewest_pieces(excess))
        else:
            tx.state.counters.overpaid_piasters += excess


def _redirect(tx: Trip, member: int, token: MoneyToken) -> bool:
    """§6.5.1: change that reaches a group member goes on to their payer in a `redirect` token,
    if the payer is still aboard to receive it. Otherwise it is judged at the member, who is owed
    nothing."""
    payer = tx.course.payer_of[member]
    if payer is None or tx.state.passengers[payer].presence is not Presence.ABOARD:
        return False
    payer_id = tx.state.passengers[payer].passenger_id
    tx.state.new_token(TokenKind.REDIRECT, token.pieces, payer_id, payer_id, token.target)
    return True


def _mistake(tx: Trip, passenger_id: str, kind: MistakeKind, amount: int) -> None:
    tx.state.mistakes.append(Mistake(passenger_id, kind, amount))


def _give_back(tx: Trip, p: int, pieces: Pieces) -> None:
    """An honest passenger sends `pieces` back to the driver."""
    passenger_id = tx.state.passengers[p].passenger_id
    tx.state.new_token(TokenKind.RETURNED, pieces, passenger_id, DRIVER, passenger_id)
