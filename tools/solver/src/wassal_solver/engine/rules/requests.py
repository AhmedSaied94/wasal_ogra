"""Payment disputes and change requests (RULES.md §4.7, §4.8): the choices authored events open.

Mirrors `packages/trip_engine/lib/src/rules/requests.dart`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.model import DRIVER, Dispute, RepCause, TokenKind
from wassal_solver.engine.money import Pieces
from wassal_solver.engine.rules.claims import catch_liar, false_accusation
from wassal_solver.engine.rules.fares import pay_now
from wassal_solver.engine.rules.reputation import lose_reputation

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip


def resolve_dispute(tx: Trip, dispute_id: int, dispute: Dispute, paid_id: str) -> None:
    """`ResolveDispute` naming `paid_id` as the one who paid (§4.7). The answer is right when
    they sent their fare and the other didn't."""
    index = tx.course.passenger_index
    passengers = tx.state.passengers
    paid = index[paid_id]
    other = index[dispute.b if paid_id == dispute.a else dispute.a]
    right = passengers[paid].fare_sent and not passengers[other].fare_sent
    del tx.state.disputes[dispute_id]
    if right:
        catch_liar(tx, other)
        pay_now(tx, other)
    else:
        false_accusation(tx, other)


def agree_change_request(tx: Trip, q: int, pieces: Pieces) -> None:
    """`ResolveChangeRequest` agreeing (§4.8): `pieces` for the note leave the tray in a
    `break_out` token to `q`."""
    state = tx.state
    passenger_id = state.passengers[q].passenger_id
    state.tray = state.tray.minus(pieces)
    state.new_token(TokenKind.BREAK_OUT, pieces, passenger_id, passenger_id, DRIVER)
    del state.change_requests[passenger_id]


def decline_change_request(tx: Trip, q: int) -> None:
    """`q`'s change request is declined, by the player or by `q` getting off unanswered (§4.8,
    §9.3.1)."""
    lose_reputation(tx, RepCause.CHANGE_REQUEST_DECLINED, tx.params.rep_change_request_declined)
    del tx.state.change_requests[tx.state.passengers[q].passenger_id]
