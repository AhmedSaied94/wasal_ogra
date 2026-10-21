"""The timeline: one entry per decision of a run, in game terms (research R10).

An entry is written right after its decision is carried out, from the mirror state then. For a
run that isn't solved, the timeline stops at the first loss and ends with a `lost_star` entry.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

from wassal_solver.engine.money import Pieces
from wassal_solver.solver.decisions import Decision, DecisionKind

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip

__all__ = ["LOST_STAR", "Loss", "TimelineEntry", "entry_for", "lost_star"]

LOST_STAR = "lost_star"


@dataclass(frozen=True, slots=True)
class Loss:
    """The first thing in a run that cost a star (data-model.md "SolverResult" `first_loss`)."""

    kind: str
    """`fight`, `mistake` or `failed`."""
    t_ms: int
    passenger_id: str | None
    station_id: str | None
    detail: str

    def to_json(self) -> dict[str, object]:
        out: dict[str, object] = {"kind": self.kind, "t_ms": self.t_ms}
        if self.passenger_id is not None:
            out["passenger_id"] = self.passenger_id
        if self.station_id is not None:
            out["station_id"] = self.station_id
        out["detail"] = self.detail
        return out


@dataclass(frozen=True, slots=True)
class TimelineEntry:
    """`{t_ms, decision, passenger_id?, amount_piasters?, pieces?, note?}`."""

    t_ms: int
    decision: str
    passenger_id: str | None = None
    amount_piasters: int | None = None
    pieces: Pieces | None = None
    note: str | None = None

    def to_json(self) -> dict[str, object]:
        out: dict[str, object] = {"t_ms": self.t_ms, "decision": self.decision}
        if self.passenger_id is not None:
            out["passenger_id"] = self.passenger_id
        if self.amount_piasters is not None:
            out["amount_piasters"] = self.amount_piasters
        if self.pieces is not None:
            out["pieces"] = self.pieces.to_json()
        if self.note is not None:
            out["note"] = self.note
        return out


def entry_for(tx: Trip, decision: Decision, t_ms: int) -> TimelineEntry:
    """The entry of `decision`, whose first command was at `t_ms`, read from `tx` just after its
    last command."""
    kind = decision.kind
    passenger_id = decision.passenger_id
    passenger = (
        None
        if passenger_id is None
        else tx.state.passengers[tx.course.passenger_index[passenger_id]]
    )
    amount: int | None = None
    note: str | None = None
    if kind is DecisionKind.COLLECT_FARE and passenger is not None:
        if passenger.fare_sent:
            amount = passenger.fare_piasters
            note = f"pays a fare of {amount}, owed {passenger.balance} in change"
        else:
            note = "says they have paid"
    elif kind is DecisionKind.COLLECT_REST:
        note = "pays the rest of the fare"
    elif kind is DecisionKind.WAKE:
        note = "is woken up"
    elif kind is DecisionKind.CALL:
        note = "is called until they listen"
    elif kind is DecisionKind.GIVE_CHANGE and decision.pieces is not None:
        amount = decision.pieces.total
    elif kind is DecisionKind.REQUEST_BREAK:
        amount = decision.denomination
        note = "asks the passengers for change"
    elif kind is DecisionKind.PICK_UP:
        note = f"picks up dropped money (token {decision.token_id})"
    elif kind is DecisionKind.ANSWER_CLAIM:
        note = "insists: the claim is false" if decision.answer is True else "believes the claim"
    elif kind is DecisionKind.ANSWER_DISPUTE:
        passenger_id = decision.answer if isinstance(decision.answer, str) else None
        note = f"names {passenger_id} as the one who paid (dispute {decision.dispute_id})"
    elif kind is DecisionKind.ANSWER_CHANGE_REQUEST and passenger_id is not None:
        note = "agrees to break the note" if decision.answer is True else "declines"
    return TimelineEntry(
        t_ms=t_ms,
        decision=kind.value,
        passenger_id=passenger_id,
        amount_piasters=amount,
        pieces=decision.pieces,
        note=note,
    )


def lost_star(loss: Loss) -> TimelineEntry:
    """The last entry of a run that isn't solved."""
    return TimelineEntry(
        t_ms=loss.t_ms, decision=LOST_STAR, passenger_id=loss.passenger_id, note=loss.detail
    )


def timeline(entries: tuple[TimelineEntry, ...], loss: Loss | None) -> tuple[TimelineEntry, ...]:
    """A run's timeline: every entry, or for a run that lost a star, the entries up to its first
    loss and then `lost_star`."""
    if loss is None:
        return entries
    kept = tuple(entry for entry in entries if entry.t_ms <= loss.t_ms)
    return (*kept, lost_star(loss))
