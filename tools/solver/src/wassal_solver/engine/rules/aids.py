"""The player's aids (RULES.md §4.4, §4.9, §4.11, §3 steps 2.4 and 2.6): undo, «حد معاه فكة؟»,
and the four in-trip boosters.

Mirrors `packages/trip_engine/lib/src/rules/aids.dart`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_content.models import BoosterId

from wassal_solver.engine.commands import Rejection, RejectionCode
from wassal_solver.engine.model import Alertness, PendingBreak, Presence
from wassal_solver.engine.money import CHANGE_BAG, break_down, is_denomination
from wassal_solver.engine.rules.passengers import wake
from wassal_solver.engine.rules.stations import shift_schedule

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip

IN_TRIP_BOOSTERS = frozenset(
    {BoosterId.CHANGE_BAG, BoosterId.WAKE_ALL, BoosterId.LEDGER_PEEK, BoosterId.TRAFFIC_JAM}
)


def undo_last_send(tx: Trip) -> Rejection | None:
    """`UndoLastSend` (§4.4): the last send's pieces come back to the hand while its window lasts
    and before its first hop ends."""
    state = tx.state
    send = state.last_send
    token = None if send is None else state.tokens.get(send.token_id)
    if (
        send is None
        or token is None
        or state.t_ms > send.until_ms
        or token.dropped_until_ms is not None
        or token.hops_done > 0
    ):
        return Rejection(RejectionCode.UNDO_UNAVAILABLE, "there is no send to undo")
    del state.tokens[token.token_id]
    state.hand = state.hand.plus(token.pieces)
    state.last_send = None
    return None


def request_break(tx: Trip, note: int) -> Rejection | None:
    """`RequestBreak` (§4.9): a note leaves the tray, and its row of §14.1 comes back
    `trip_break_delay_ms` later."""
    state = tx.state
    if not is_denomination(note):
        return Rejection(RejectionCode.BAD_ARGUMENT, f"{note} is not a denomination")
    if note < tx.params.trip_break_min_piasters or break_down(note) is None:
        return Rejection(RejectionCode.BREAK_LIMIT, f"{note} cannot be broken")
    if state.tray.count(note) < 1:
        return Rejection(RejectionCode.TRAY_EMPTY, f"no {note} in the tray")
    if state.breaks_used >= tx.course.max_break_requests:
        return Rejection(RejectionCode.BREAK_LIMIT, "no breaks are left")
    state.tray = state.tray.minus_one(note)
    state.pending_breaks.append(PendingBreak(note, state.t_ms + tx.params.trip_break_delay_ms))
    state.breaks_used += 1
    return None


def complete_breaks(tx: Trip) -> None:
    """Phase 2.6 (§3): pending breaks whose time has come complete, in list order."""
    state = tx.state
    pending = state.pending_breaks
    i = 0
    while i < len(pending):
        request = pending[i]
        if request.completes_at_ms > state.t_ms:
            i += 1
            continue
        pieces = break_down(request.denomination)
        if pieces is None:
            raise AssertionError(f"{request.denomination} was checked on request")
        del pending[i]
        state.tray = state.tray.plus(pieces)


def ledger_peek_timer(tx: Trip) -> None:
    """Phase 2.4 (§3): the ledger peek ends."""
    until = tx.state.ledger_peek_until_ms
    if until is not None and until <= tx.state.t_ms:
        tx.state.ledger_peek_until_ms = None


def use_booster(tx: Trip, booster: BoosterId) -> Rejection | None:
    """`UseBooster` (§4.11)."""
    state = tx.state
    if booster not in IN_TRIP_BOOSTERS:
        return Rejection(RejectionCode.BAD_ARGUMENT, f"{booster.value} is not an in-trip booster")
    if (
        booster is BoosterId.TRAFFIC_JAM
        and state.boosters_used.count(booster) >= tx.params.booster_traffic_jam_max_per_trip
    ):
        return Rejection(RejectionCode.BOOSTER_LIMIT, "no traffic jams are left")
    state.boosters_used.append(booster)
    if booster is BoosterId.CHANGE_BAG:
        state.tray = state.tray.plus(CHANGE_BAG)
    elif booster is BoosterId.WAKE_ALL:
        for q, passenger in enumerate(state.passengers):
            if passenger.presence is Presence.ABOARD and (
                passenger.alertness is Alertness.ASLEEP or passenger.alertness is Alertness.WAKING
            ):
                wake(tx, q)
    elif booster is BoosterId.LEDGER_PEEK:
        state.ledger_peek_until_ms = state.t_ms + tx.params.booster_ledger_peek_ms
    else:
        shift_schedule(tx, tx.params.booster_traffic_jam_ms)
    return None
