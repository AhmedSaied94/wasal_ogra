"""Applying one command between steps (RULES.md §4).

Mirrors `packages/trip_engine/lib/src/rules/command_handlers.dart`. Dart drops a rejected
command's transition; here every handler checks everything before it changes anything, so a
rejected command changes nothing.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Any

from wassal_solver.engine.commands import (
    Abandon,
    CollectDropped,
    Command,
    PickFromTray,
    Rejection,
    RejectionCode,
    RequestBreak,
    ResolveChangeRequest,
    ResolveClaim,
    ResolveDispute,
    ReturnHand,
    Revive,
    SendHand,
    Tap,
    UndoLastSend,
    UseBooster,
)
from wassal_solver.engine.model import (
    DRIVER,
    Alertness,
    LastSend,
    Presence,
    TokenKind,
    TripOutcome,
    TripStatus,
)
from wassal_solver.engine.money import EMPTY, change_request_pieces, is_denomination
from wassal_solver.engine.rules.aids import request_break, undo_last_send, use_booster
from wassal_solver.engine.rules.chain import collect_dropped
from wassal_solver.engine.rules.claims import claims_instead_of_paying, open_claim, resolve_claim
from wassal_solver.engine.rules.fares import pay_now, pay_rest
from wassal_solver.engine.rules.passengers import call_muted, start_waking
from wassal_solver.engine.rules.reputation import failure_check
from wassal_solver.engine.rules.requests import (
    agree_change_request,
    decline_change_request,
    resolve_dispute,
)
from wassal_solver.engine.rules.scoring import build_result

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip

COMMAND_CAP = 1200
"""Accepted commands per trip (§4, M01 research R9). `Abandon` is exempt, so the player can always
leave: a log holds at most one more."""

_RUNNING = frozenset({TripStatus.RUNNING})
_CHOICES = frozenset({TripStatus.RUNNING, TripStatus.PAUSED})

_ALLOWED: dict[type[Any], frozenset[TripStatus]] = {
    PickFromTray: _RUNNING,
    ReturnHand: _RUNNING,
    SendHand: _RUNNING,
    UndoLastSend: _RUNNING,
    Tap: _RUNNING,
    RequestBreak: _RUNNING,
    CollectDropped: _RUNNING,
    ResolveClaim: _CHOICES,
    ResolveDispute: _CHOICES,
    ResolveChangeRequest: _CHOICES,
    UseBooster: _CHOICES,
    Revive: frozenset({TripStatus.FAILED}),
    Abandon: frozenset({TripStatus.RUNNING, TripStatus.PAUSED, TripStatus.FAILED}),
}


def allowed_statuses(command: Command) -> frozenset[TripStatus]:
    """The statuses `command` is allowed in (M01 data-model "Commands")."""
    return _ALLOWED[type(command)]


def apply_command(tx: Trip, command: Command) -> Rejection | None:
    """Applies `command` at the trip's clock: None if it is accepted, else the rejection."""
    state = tx.state
    if state.status not in _ALLOWED[type(command)]:
        return Rejection(
            RejectionCode.WRONG_STATUS,
            f"{command.name} is not allowed while {state.status.value}",
        )
    if not isinstance(command, Abandon) and state.commands_accepted >= COMMAND_CAP:
        return Rejection(RejectionCode.COMMAND_LIMIT, f"{COMMAND_CAP} commands already accepted")
    rejection = _HANDLERS[type(command)](tx, command)
    if rejection is not None:
        return rejection
    state.commands_accepted += 1
    failure_check(tx)
    return None


# §4.1
def _pick_from_tray(tx: Trip, command: PickFromTray) -> Rejection | None:
    denomination = command.denomination
    if not is_denomination(denomination):
        return Rejection(RejectionCode.BAD_ARGUMENT, f"{denomination} is not a denomination")
    state = tx.state
    if state.tray.count(denomination) < 1:
        return Rejection(RejectionCode.TRAY_EMPTY, f"no {denomination} in the tray")
    state.tray = state.tray.minus_one(denomination)
    state.hand = state.hand.plus_one(denomination)
    return None


# §4.2
def _return_hand(tx: Trip, command: ReturnHand) -> Rejection | None:
    state = tx.state
    if state.hand.is_empty:
        return Rejection(RejectionCode.HAND_EMPTY, "the hand is empty")
    state.tray = state.tray.plus(state.hand)
    state.hand = EMPTY
    return None


def _aboard(tx: Trip, passenger_id: str) -> int | None:
    """The index of `passenger_id` if they are aboard, or None."""
    index = tx.course.passenger_index.get(passenger_id)
    if index is None or tx.state.passengers[index].presence is not Presence.ABOARD:
        return None
    return index


def _not_aboard(passenger_id: str) -> Rejection:
    return Rejection(RejectionCode.NOT_ABOARD, f"{passenger_id} is not aboard")


# §4.3
def _send_hand(tx: Trip, command: SendHand) -> Rejection | None:
    state = tx.state
    if state.hand.is_empty:
        return Rejection(RejectionCode.HAND_EMPTY, "the hand is empty")
    passenger_id = command.passenger_id
    if _aboard(tx, passenger_id) is None:
        return _not_aboard(passenger_id)
    token = state.new_token(TokenKind.CHANGE, state.hand, passenger_id, passenger_id, DRIVER)
    state.hand = EMPTY
    state.last_send = LastSend(token.token_id, state.t_ms + tx.params.trip_undo_window_ms)
    return None


# §4.4
def _undo_last_send(tx: Trip, command: UndoLastSend) -> Rejection | None:
    return undo_last_send(tx)


# §4.5: the first case that applies wins. Cases 1 to 3 concern the tapped passenger; for 4 to 7,
# a group member stands for their payer.
def _tap(tx: Trip, command: Tap) -> Rejection | None:
    p = _aboard(tx, command.passenger_id)
    if p is None:
        return _not_aboard(command.passenger_id)
    state = tx.state
    alertness = state.passengers[p].alertness
    if alertness is Alertness.ASLEEP:
        start_waking(tx, p)
        return None
    if alertness is Alertness.WAKING:
        return Rejection(RejectionCode.NO_EFFECT, f"{command.passenger_id} is waking up")
    if alertness is Alertness.MUTED:
        call_muted(tx, p)
        return None
    payer_of = tx.course.payer_of[p]
    q = p if payer_of is None else payer_of
    payer = state.passengers[q]
    if payer.presence is not Presence.ABOARD:
        return _not_aboard(payer.passenger_id)
    claim_open = payer.passenger_id in state.claims
    if not payer.fare_sent and not claim_open:
        if payer.never_pays:
            pass  # they say they've paid: speech only
        elif claims_instead_of_paying(tx, q):
            open_claim(tx, q, truthful=False)
        else:
            pay_now(tx, q)
        return None
    if claim_open:
        return Rejection(RejectionCode.NO_EFFECT, f"{payer.passenger_id} has an open claim")
    if payer.balance < 0:
        pay_rest(tx, q)
    elif not payer.claim_resolved:
        open_claim(tx, q, truthful=True)
    # Otherwise they say they've paid: speech only.
    return None


# §4.6
def _resolve_claim(tx: Trip, command: ResolveClaim) -> Rejection | None:
    claim = tx.state.claims.get(command.passenger_id)
    if claim is None:
        return Rejection(RejectionCode.NO_CHOICE, f"{command.passenger_id} has no open claim")
    resolve_claim(tx, tx.course.index_of(command.passenger_id), claim, insist=command.insist)
    return None


# §4.7
def _resolve_dispute(tx: Trip, command: ResolveDispute) -> Rejection | None:
    dispute = tx.state.disputes.get(command.dispute_id)
    if dispute is None:
        return Rejection(RejectionCode.NO_CHOICE, f"no open dispute {command.dispute_id}")
    paid = command.paid_passenger_id
    if paid != dispute.a and paid != dispute.b:
        return Rejection(
            RejectionCode.BAD_ARGUMENT, f"{paid} is not in dispute {command.dispute_id}"
        )
    resolve_dispute(tx, command.dispute_id, dispute, paid)
    return None


# §4.8
def _resolve_change_request(tx: Trip, command: ResolveChangeRequest) -> Rejection | None:
    passenger_id = command.passenger_id
    request = tx.state.change_requests.get(passenger_id)
    if request is None:
        return Rejection(RejectionCode.NO_CHOICE, f"{passenger_id} has no open change request")
    q = tx.course.index_of(passenger_id)
    if not command.agree:
        decline_change_request(tx, q)
        return None
    pieces = change_request_pieces(request.note_piasters, tx.state.tray)
    if pieces is None:
        return Rejection(
            RejectionCode.CANNOT_MAKE_CHANGE, f"the tray cannot make {request.note_piasters}"
        )
    agree_change_request(tx, q, pieces)
    return None


# §4.9
def _request_break(tx: Trip, command: RequestBreak) -> Rejection | None:
    return request_break(tx, command.denomination)


# §4.10
def _collect_dropped(tx: Trip, command: CollectDropped) -> Rejection | None:
    token = tx.state.tokens.get(command.token_id)
    if token is None or token.dropped_until_ms is None:
        return Rejection(RejectionCode.NO_EFFECT, f"token {command.token_id} is not dropped")
    collect_dropped(tx, token)
    return None


# §4.11
def _use_booster(tx: Trip, command: UseBooster) -> Rejection | None:
    return use_booster(tx, command.booster)


# §4.12: once per trip, and never after a fight in a no-fights trip.
def _revive(tx: Trip, command: Revive) -> Rejection | None:
    state = tx.state
    if not state.revivable:
        return Rejection(RejectionCode.NOT_REVIVABLE, "the trip cannot be revived")
    state.reputation = tx.params.rep_revive_to
    state.status = TripStatus.RUNNING
    state.revived = True
    state.revivable = False
    state.result = None
    return None


# §4.13
def _abandon(tx: Trip, command: Abandon) -> Rejection | None:
    result = build_result(tx, TripOutcome.ABANDONED)
    tx.state.status = TripStatus.ABANDONED
    tx.state.result = result
    return None


_HANDLERS: dict[type[Any], Callable[[Trip, Any], Rejection | None]] = {
    PickFromTray: _pick_from_tray,
    ReturnHand: _return_hand,
    SendHand: _send_hand,
    UndoLastSend: _undo_last_send,
    Tap: _tap,
    ResolveClaim: _resolve_claim,
    ResolveDispute: _resolve_dispute,
    ResolveChangeRequest: _resolve_change_request,
    RequestBreak: _request_break,
    CollectDropped: _collect_dropped,
    UseBooster: _use_booster,
    Revive: _revive,
    Abandon: _abandon,
}
