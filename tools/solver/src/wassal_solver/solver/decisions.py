"""The idealized player's decisions (contracts/solver.md §2, data-model.md "Decision", research R7).

A decision is one player move, carried out by one or more commands a tap time apart. The player
knows the whole state, answers claims and disputes with the truth, gives only exact change, and
never uses an aid (spec FR-016).
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from typing import TYPE_CHECKING

from wassal_solver.engine.clock import STEP_MS
from wassal_solver.engine.commands import (
    CollectDropped,
    Command,
    PickFromTray,
    RequestBreak,
    ResolveChangeRequest,
    ResolveClaim,
    ResolveDispute,
    SendHand,
    Tap,
)
from wassal_solver.engine.model import Alertness, Presence, TokenKind
from wassal_solver.engine.money import (
    DENOMINATIONS,
    Pieces,
    break_down,
    change_request_pieces,
)

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip
    from wassal_solver.settings import SolverSettings

__all__ = [
    "Decision",
    "DecisionKind",
    "Timing",
    "certain_loss",
    "compositions",
    "possible_decisions",
    "round_to_step",
]

_SMALL = (0, 1)
"""The indexes of 50 and 100 in DENOMINATIONS: the pieces a tray runs short of."""
_CHANGE_KINDS = frozenset({TokenKind.CHANGE, TokenKind.REDIRECT})


class DecisionKind(StrEnum):
    COLLECT_FARE = "collect_fare"
    COLLECT_REST = "collect_rest"
    WAKE = "wake"
    CALL = "call"
    GIVE_CHANGE = "give_change"
    REQUEST_BREAK = "request_break"
    PICK_UP = "pick_up"
    ANSWER_CLAIM = "answer_claim"
    ANSWER_DISPUTE = "answer_dispute"
    ANSWER_CHANGE_REQUEST = "answer_change_request"


@dataclass(frozen=True, slots=True)
class Decision:
    """One move. Only the fields of its kind are set (data-model.md "Decision")."""

    kind: DecisionKind
    passenger_id: str | None = None
    pieces: Pieces | None = None
    """`give_change`: the exact change, taken from the tray."""
    denomination: int | None = None
    """`request_break`: the note."""
    token_id: int | None = None
    """`pick_up`: the dropped token."""
    dispute_id: int | None = None
    answer: bool | str | None = None
    """`answer_claim` and `answer_change_request`: insist or agree. `answer_dispute`: who paid."""

    def commands(self) -> tuple[Command, ...]:
        """The commands that carry the decision out, in order."""
        passenger_id = self.passenger_id or ""
        match self.kind:
            case DecisionKind.CALL:
                return (Tap(passenger_id), Tap(passenger_id))
            case DecisionKind.COLLECT_FARE | DecisionKind.COLLECT_REST | DecisionKind.WAKE:
                return (Tap(passenger_id),)
            case DecisionKind.GIVE_CHANGE if self.pieces is not None:
                picks = [PickFromTray(d) for d in reversed(self.pieces.to_list())]
                return (*picks, SendHand(passenger_id))
            case DecisionKind.REQUEST_BREAK if self.denomination is not None:
                return (RequestBreak(self.denomination),)
            case DecisionKind.PICK_UP if self.token_id is not None:
                return (CollectDropped(self.token_id),)
            case DecisionKind.ANSWER_CLAIM:
                return (ResolveClaim(passenger_id, insist=self.answer is True),)
            case DecisionKind.ANSWER_DISPUTE if self.dispute_id is not None and isinstance(
                self.answer, str
            ):
                return (ResolveDispute(self.dispute_id, self.answer),)
            case DecisionKind.ANSWER_CHANGE_REQUEST:
                return (ResolveChangeRequest(passenger_id, agree=self.answer is True),)
        raise ValueError(f"{self.kind.value} is missing its fields: {self}")

    def to_json(self) -> dict[str, object]:
        out: dict[str, object] = {"kind": self.kind.value}
        if self.passenger_id is not None:
            out["passenger_id"] = self.passenger_id
        if self.pieces is not None:
            out["pieces"] = self.pieces.to_json()
        if self.denomination is not None:
            out["denomination"] = self.denomination
        if self.token_id is not None:
            out["token_id"] = self.token_id
        if self.dispute_id is not None:
            out["dispute_id"] = self.dispute_id
        if self.answer is not None:
            out["answer"] = self.answer
        return out


def round_to_step(ms: int) -> int:
    """`ms` rounded up to the next whole step: 600 → 627."""
    return (ms + STEP_MS - 1) // STEP_MS * STEP_MS


@dataclass(frozen=True, slots=True)
class Timing:
    """The player's pace (contracts/solver.md §2): `reaction_ms` before each decision and
    `tap_ms` between its commands, both rounded up to whole steps."""

    reaction_ms: int
    tap_ms: int

    @staticmethod
    def of(settings: SolverSettings) -> Timing:
        return Timing(round_to_step(settings.reaction_ms), round_to_step(settings.tap_ms))

    def first_command_at(self, last_end_ms: int, possible_since_ms: int) -> int:
        """The earliest step for a decision's first command: one reaction time after the end
        of the decision before it, and after the step at which it became possible."""
        return max(last_end_ms, possible_since_ms) + self.reaction_ms


def compositions(amount: int, tray: Pieces) -> tuple[Pieces, ...]:
    """Every way to pay exactly `amount` from `tray`: the fewest pieces first, then the most 50s
    and 100s left in the tray, then the largest pieces first."""
    if amount <= 0:
        return ()
    return _compositions(amount, tray.counts)


@lru_cache(maxsize=4096)
def _compositions(amount: int, counts: tuple[int, ...]) -> tuple[Pieces, ...]:
    found: list[tuple[int, ...]] = []
    chosen = [0] * len(DENOMINATIONS)

    def search(i: int, rest: int) -> None:
        if rest == 0:
            found.append(tuple(chosen))
            return
        if i < 0:
            return
        denomination = DENOMINATIONS[i]
        most = min(counts[i], rest // denomination)
        for n in range(most, -1, -1):
            chosen[i] = n
            search(i - 1, rest - n * denomination)
        chosen[i] = 0

    search(len(DENOMINATIONS) - 1, amount)
    found.sort(key=_composition_order)
    return tuple(Pieces(c, amount) for c in found)


def _composition_order(counts: tuple[int, ...]) -> tuple[int, int, tuple[int, ...]]:
    used_small = sum(counts[i] for i in _SMALL)
    return sum(counts), used_small, tuple(-n for n in reversed(counts))


def possible_decisions(tx: Trip) -> tuple[Decision, ...]:
    """The decisions possible in `tx`'s state, in the search order of contracts/solver.md §3:
    the forced answers, then each passenger's by their soonest stop, then breaks, then change
    requests."""
    state = tx.state
    course = tx.course
    passengers = state.passengers
    out: list[Decision] = []
    # 1. Forced answers: claims, disputes, dropped money.
    for passenger_id, claim in state.claims.items():
        out.append(Decision(DecisionKind.ANSWER_CLAIM, passenger_id, answer=not claim.truthful))
    for dispute_id, dispute in state.disputes.items():
        a = passengers[course.passenger_index[dispute.a]].fare_sent
        b = passengers[course.passenger_index[dispute.b]].fare_sent
        if a != b:
            paid = dispute.a if a else dispute.b
            out.append(Decision(DecisionKind.ANSWER_DISPUTE, dispute_id=dispute_id, answer=paid))
    for token in state.tokens.values():
        if token.dropped_until_ms is not None:
            out.append(Decision(DecisionKind.PICK_UP, token_id=token.token_id))
    # 2. Each aboard passenger, by their soonest stop.
    in_flight = {
        token.owner
        for token in state.tokens.values()
        if token.kind in _CHANGE_KINDS and token.dropped_until_ms is None
    }
    hand_empty = state.hand.is_empty
    short = False
    for q in _by_stop(tx):
        passenger = passengers[q]
        passenger_id = passenger.passenger_id
        alertness = passenger.alertness
        if alertness is Alertness.ASLEEP:
            out.append(Decision(DecisionKind.WAKE, passenger_id))
        elif alertness is Alertness.MUTED:
            out.append(Decision(DecisionKind.CALL, passenger_id))
        if course.payer_of[q] is not None or passenger_id in state.claims:
            continue
        able = passenger.is_able
        if not passenger.fare_sent:
            if able and not passenger.never_pays:
                out.append(Decision(DecisionKind.COLLECT_FARE, passenger_id))
            continue
        if passenger.balance < 0:
            if able:
                out.append(Decision(DecisionKind.COLLECT_REST, passenger_id))
            continue
        if passenger.balance == 0 or passenger_id in in_flight:
            continue
        ways = compositions(passenger.balance, state.tray)
        if not ways:
            short = True
        elif hand_empty:
            out.extend(Decision(DecisionKind.GIVE_CHANGE, passenger_id, pieces=w) for w in ways)
    # 3. Breaks, larger notes first, while the tray can't make someone's change and no break is
    # pending.
    requests = state.change_requests
    if not short:
        short = any(
            change_request_pieces(request.note_piasters, state.tray) is None
            for request in requests.values()
        )
    if short and not state.pending_breaks and state.breaks_used < course.max_break_requests:
        for note in reversed(DENOMINATIONS):
            if (
                note >= tx.params.trip_break_min_piasters
                and state.tray.count(note) > 0
                and break_down(note) is not None
            ):
                out.append(Decision(DecisionKind.REQUEST_BREAK, denomination=note))
    # 4. Change requests: agree first, when the tray can, then decline.
    for passenger_id, request in requests.items():
        if change_request_pieces(request.note_piasters, state.tray) is not None:
            out.append(Decision(DecisionKind.ANSWER_CHANGE_REQUEST, passenger_id, answer=True))
        out.append(Decision(DecisionKind.ANSWER_CHANGE_REQUEST, passenger_id, answer=False))
    return tuple(out)


def _by_stop(tx: Trip) -> list[int]:
    """The aboard passengers, by the current time of their stop, then in definition order."""
    state = tx.state
    schedule = state.schedule
    dest = tx.course.dest_index
    aboard = [q for q, p in enumerate(state.passengers) if p.presence is Presence.ABOARD]
    aboard.sort(key=lambda q: (schedule[dest[q]].at_ms, q))
    return aboard


def certain_loss(tx: Trip) -> tuple[str, int] | None:
    """A passenger who will certainly get off owed, and the step of their stop, or None.

    That is someone owed change the tray can't make, when nothing can bring the tray new pieces:
    no break left to ask for or pending, no money in transit or in the hand, nobody left to pay
    or owing the rest, and no authored event still to fire. Short or over-change would cost a star
    too, so the branch can only lose one (contracts/solver.md §3).
    """
    state = tx.state
    course = tx.course
    if (
        state.tokens
        or not state.hand.is_empty
        or state.pending_breaks
        or not all(state.events_fired)
    ):
        return None
    if state.breaks_used < course.max_break_requests and any(
        note >= tx.params.trip_break_min_piasters
        and state.tray.count(note) > 0
        and break_down(note) is not None
        for note in DENOMINATIONS
    ):
        return None
    doomed: tuple[str, int] | None = None
    for q, passenger in enumerate(state.passengers):
        if passenger.presence is Presence.GONE or course.payer_of[q] is not None:
            continue
        if passenger.balance < 0 or (not passenger.fare_sent and not passenger.never_pays):
            return None
        if (
            doomed is None
            and passenger.presence is Presence.ABOARD
            and passenger.is_owed
            and not compositions(passenger.balance, state.tray)
        ):
            stop = round_to_step(state.schedule[course.dest_index[q]].at_ms)
            doomed = (passenger.passenger_id, stop)
    return doomed
