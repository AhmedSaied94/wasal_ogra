"""Money tokens and the passing chain (RULES.md §5).

Mirrors `packages/trip_engine/lib/src/rules/chain.dart`. A holder is `DRIVER` or a passenger id.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.clock import STEP_MS
from wassal_solver.engine.model import DRIVER, TOWARD_DRIVER, MoneyToken, TokenKind
from wassal_solver.engine.money import Pieces, scale
from wassal_solver.engine.rules.change import judge_change
from wassal_solver.engine.rules.course import LAST_NEAR_ROW

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip


def can_act(tx: Trip, holder: str) -> bool:
    """Whether `holder` can pass or take money: the driver, or an able passenger."""
    return holder == DRIVER or tx.state.passengers[tx.course.passenger_index[holder]].is_able


def next_holder(tx: Trip, token: MoneyToken) -> str:
    """Who `token` goes to next from where it is (§5.2), worked out each time a hop is about to
    start."""
    if token.kind is TokenKind.REDIRECT:
        return token.target
    if token.kind in TOWARD_DRIVER:
        return _ahead(tx, token.holder)
    return _behind(tx, token.holder, token.target)


def _ahead(tx: Trip, holder: str) -> str:
    """Toward the driver: the nearest occupied seat ahead in the same column, or the driver from
    rows front and A."""
    row, col = _place(tx, holder)
    for r in range(row - 1, LAST_NEAR_ROW - 1, -1):
        occupant = _occupant(tx, r, col)
        if occupant is not None:
            return occupant
    return DRIVER


def _behind(tx: Trip, holder: str, target: str) -> str:
    """Toward passenger `target`: the next occupied seat of their column between the holder and
    them, or the target."""
    row, col = _place(tx, target)
    first = LAST_NEAR_ROW if holder == DRIVER else _place(tx, holder)[0] + 1
    for r in range(first, row):
        occupant = _occupant(tx, r, col)
        if occupant is not None:
            return occupant
    return target


def _place(tx: Trip, passenger_id: str) -> tuple[int, str]:
    seat = tx.state.passengers[tx.course.passenger_index[passenger_id]].seat_id
    return tx.course.seat_row.get(seat, 0), tx.course.seat_col.get(seat, "r")


def _occupant(tx: Trip, row: int, col: str) -> str | None:
    seat = tx.course.seat_at.get((row, col))
    if seat is None:
        return None
    passenger = tx.state.occupant(seat)
    return None if passenger is None else tx.state.passengers[passenger].passenger_id


def hop_duration(tx: Trip, token: MoneyToken, holder: str) -> int:
    """How long a hop from `holder` takes (§5.4)."""
    params = tx.params
    if token.kind is TokenKind.REDIRECT:
        return params.trip_group_redirect_hop_ms
    duration = params.trip_hop_ms
    if holder == DRIVER:
        return duration
    index = tx.course.passenger_index[holder]
    if tx.course.archetype[index] == "hajja":
        duration = scale(duration, params.trip_hop_pct_hajja)
    if _chatty_row(tx, tx.course.seat_row.get(tx.state.passengers[index].seat_id)):
        duration = scale(duration, params.trip_hop_pct_chatty_row)
    return duration


def _chatty_row(tx: Trip, row: int | None) -> bool:
    """Whether an able chatty passenger sits in `row`."""
    archetype = tx.course.archetype
    seat_row = tx.course.seat_row
    for q, passenger in enumerate(tx.state.passengers):
        if (
            archetype[q] == "chatty"
            and passenger.is_able
            and seat_row.get(passenger.seat_id) == row
        ):
            return True
    return False


def try_start_hop(tx: Trip, token: MoneyToken) -> None:
    """Starts `token`'s next hop if both ends can act, otherwise marks it blocked (§5.3)."""
    holder = token.holder
    to = next_holder(tx, token)
    blocker = holder if not can_act(tx, holder) else to if not can_act(tx, to) else None
    if blocker is not None:
        token.blocked_by = blocker
        return
    token.blocked_by = None
    token.hop_to = to
    token.hop_elapsed_ms = 0
    token.hop_duration_ms = hop_duration(tx, token, holder)


def move_tokens(tx: Trip) -> None:
    """Phase 5 of a step (§3): the tokens that exist at its start, in id order, hop on, arrive,
    and are delivered. Tokens made here move next step."""
    tokens = tx.state.tokens
    if not tokens:
        return
    for token_id in list(tokens):
        token = tokens.get(token_id)
        if token is None or token.dropped_until_ms is not None:
            continue
        to = token.hop_to
        if to is not None:
            elapsed = token.hop_elapsed_ms + STEP_MS
            if elapsed < token.hop_duration_ms:
                token.hop_elapsed_ms = elapsed
                continue
            token.holder = to
            token.hops_done += 1
            _end_hop(token)
            if to == token.target:
                deliver(tx, token)
                continue
        try_start_hop(tx, token)


def _end_hop(token: MoneyToken) -> None:
    token.hop_to = None
    token.hop_elapsed_ms = 0
    token.hop_duration_ms = 0


def deliver(tx: Trip, token: MoneyToken) -> None:
    """`token` reached its target (§5.5)."""
    kind = token.kind
    if kind in TOWARD_DRIVER:
        at_driver(tx, token)
    elif kind is TokenKind.CHANGE or kind is TokenKind.REDIRECT:
        del tx.state.tokens[token.token_id]
        judge_change(tx, token)
    else:  # break_out: the passenger hands back their note.
        del tx.state.tokens[token.token_id]
        tx.state.new_token(
            TokenKind.BREAK_IN,
            Pieces.of({token.pieces.total: 1}),
            token.owner,
            DRIVER,
            token.target,
        )


def at_driver(tx: Trip, token: MoneyToken) -> None:
    """`token`'s pieces enter the tray at the driver. A fare counts as paid in."""
    state = tx.state
    state.tokens.pop(token.token_id, None)
    state.tray = state.tray.plus(token.pieces)
    if token.kind is TokenKind.FARE:
        state.passengers[tx.course.passenger_index[token.owner]].paid_in += token.pieces.total


def drop_mid_hop(tx: Trip) -> None:
    """The bump (§8): every mid-hop token drops to the floor, in id order."""
    state = tx.state
    until = state.t_ms + tx.params.trip_bump_collect_ms
    for token in list(state.tokens.values()):
        if token.hop_to is None:
            continue
        _end_hop(token)
        token.dropped_until_ms = until


def drop_deadlines(tx: Trip) -> None:
    """Phase 2.5 (§3): dropped tokens whose time is up are lost, in id order."""
    state = tx.state
    if not state.tokens:
        return
    for token in list(state.tokens.values()):
        until = token.dropped_until_ms
        if until is not None and until <= state.t_ms:
            lose_dropped(tx, token)


def collect_dropped(tx: Trip, token: MoneyToken) -> None:
    """`CollectDropped` (§5.7): a fare arrives at the driver; anything else goes into the tray,
    and a `break_in` completes its request."""
    if token.kind is TokenKind.FARE:
        at_driver(tx, token)
    else:
        to_tray(tx, token)


def lose_dropped(tx: Trip, token: MoneyToken) -> None:
    """A dropped token is lost (§5.7). A lost fare never reaches the driver and a lost return is
    overpaid; any other money is simply gone."""
    state = tx.state
    del state.tokens[token.token_id]
    if token.kind is TokenKind.RETURNED:
        state.counters.overpaid_piasters += token.pieces.total


def to_tray(tx: Trip, token: MoneyToken) -> None:
    """`token`'s pieces go back into the tray."""
    state = tx.state
    del state.tokens[token.token_id]
    state.tray = state.tray.plus(token.pieces)


def hand_over_tokens(tx: Trip, passenger: int) -> None:
    """Passenger `passenger` gets off (§5.8): tokens they hold, or that are hopping to them on the
    way elsewhere, are handed to the driver; tokens for them go back to the tray. Dropped tokens
    stay on the floor."""
    state = tx.state
    holder = state.passengers[passenger].passenger_id
    for token in list(state.tokens.values()):
        if token.dropped_until_ms is not None:
            continue
        if token.target == holder:
            to_tray(tx, token)
        elif token.holder == holder or token.hop_to == holder:
            if token.kind is TokenKind.FARE:
                at_driver(tx, token)
            else:
                to_tray(tx, token)
