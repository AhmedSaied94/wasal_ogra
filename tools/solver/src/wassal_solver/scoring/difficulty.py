"""The difficulty score (contracts/solver.md §5, research R11).

The inputs are integers read from the trip and its confirmed 3-star run. The mirror has no events
(spec FR-006), so they are read by stepping a fresh trip through the run and watching its state
after every step and command. Each input gives `min(cap, max(0, value - free) * per // unit)`
points, and the score is `min(100, sum of points)`: every term is non-decreasing in its input, so
raising one never lowers the score (FR-025).
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from wassal_content.models import TripDefinition

from wassal_solver.engine.commands import LoggedCommand, PickFromTray, RequestBreak
from wassal_solver.engine.model import DRIVER, MoneyToken, Presence, TokenKind, TripStatus
from wassal_solver.engine.money import EMPTY
from wassal_solver.engine.params import TripParams
from wassal_solver.engine.rules.chain import next_holder
from wassal_solver.engine.trip import Trip, start
from wassal_solver.settings import SCORE_INPUTS, ScoreTable, ScoreTerm, SolverSettings

__all__ = [
    "Band",
    "InputPoints",
    "Observed",
    "Score",
    "in_band",
    "measure",
    "observe_run",
    "points",
    "score_of",
    "score_trip",
]

MAX_SCORE = 100
_BLOCKING = frozenset({"sleeper", "headphones"})
_CHANGE = frozenset({TokenKind.CHANGE, TokenKind.REDIRECT})


@dataclass(frozen=True, slots=True)
class InputPoints:
    """One input's value and the points it gives."""

    value: int
    points: int

    def to_json(self) -> dict[str, int]:
        return {"value": self.value, "points": self.points}


@dataclass(frozen=True, slots=True)
class Score:
    """`value = min(100, sum of points)`. It holds no band: whoever uses it checks the band."""

    value: int
    inputs: tuple[tuple[str, InputPoints], ...]
    """In SCORE_INPUTS order."""

    def to_json(self) -> dict[str, object]:
        return {
            "value": self.value,
            "inputs": {name: points.to_json() for name, points in self.inputs},
        }

    def input(self, name: str) -> InputPoints:
        for key, points in self.inputs:
            if key == name:
                return points
        raise KeyError(name)

    def most(self, count: int = 2) -> tuple[str, ...]:
        """The inputs that give the most points, the first in SCORE_INPUTS order on a tie."""
        ranked = sorted(range(len(self.inputs)), key=lambda i: (-self.inputs[i][1].points, i))
        return tuple(self.inputs[i][0] for i in ranked[:count] if self.inputs[i][1].points > 0)


@dataclass(frozen=True, slots=True)
class Band:
    """A line's `difficulty_band`, both ends included."""

    min: int
    max: int

    def to_json(self) -> list[int]:
        return [self.min, self.max]


def in_band(score: int, band: Band) -> bool:
    """`band.min <= score <= band.max` (contracts/solver.md §5). The caller checks it against the
    line's band as it is now, because a reused result doesn't carry one."""
    return band.min <= score <= band.max


def points(term: ScoreTerm, value: int) -> int:
    """`min(cap, max(0, value - free) * per // unit)`."""
    return min(term.cap, max(0, value - term.free) * term.per // term.unit)


def score_of(values: Mapping[str, int], table: ScoreTable) -> Score:
    """The score of the six input values under `table`."""
    inputs = tuple(
        (name, InputPoints(values[name], points(table.term(name), values[name])))
        for name in SCORE_INPUTS
    )
    return Score(min(MAX_SCORE, sum(p.points for _, p in inputs)), inputs)


def score_trip(
    definition: TripDefinition,
    run: Sequence[LoggedCommand],
    params: TripParams,
    settings: SolverSettings,
) -> Score:
    """The score of `definition` played by `run`, its confirmed 3-star run."""
    return score_of(measure(definition, run, params, settings.score.slack_ref_ms), settings.score)


@dataclass(frozen=True, slots=True)
class Observed:
    """What a run shows when it is played: the inputs that need the mirror's state."""

    owed_at_once: int
    blockers: int
    slacks: tuple[tuple[str, int], ...]
    """(passenger, ms from their change's arrival to their getting off), in arrival order."""


def observe_run(
    definition: TripDefinition, run: Sequence[LoggedCommand], params: TripParams
) -> Observed:
    """Steps a fresh trip through `run` and watches it after every step and command."""
    trip = start(definition, params, definition.seed)
    watch = _Watch(trip)
    for entry in run:
        while trip.status is TripStatus.RUNNING and trip.t_ms < entry.t_ms:
            trip.step()
            watch.observe()
        if trip.apply(entry.command) is not None:
            raise ValueError(f"the run does not replay: {entry} was rejected")
        watch.observe()
    while trip.status is TripStatus.RUNNING:
        trip.step()
        watch.observe()
    slacks = tuple(
        (owner, watch.gone_at[owner] - arrived)
        for owner, arrived in watch.arrivals
        if owner in watch.gone_at
    )
    return Observed(watch.owed_at_once, watch.blockers, slacks)


def measure(
    definition: TripDefinition,
    run: Sequence[LoggedCommand],
    params: TripParams,
    slack_ref_ms: int,
) -> dict[str, int]:
    """The six inputs of contracts/solver.md §5, in SCORE_INPUTS order."""
    observed = observe_run(definition, run, params)
    slacks = [slack for _, slack in observed.slacks]
    return {
        "owed_at_once": observed.owed_at_once,
        "change_pieces": sum(1 for entry in run if isinstance(entry.command, PickFromTray)),
        "blockers": observed.blockers,
        "breaks": sum(1 for entry in run if isinstance(entry.command, RequestBreak)),
        "tightness_ms": max(0, slack_ref_ms - min(slacks)) if slacks else 0,
        "variety": len({p.archetype.value for p in definition.passengers})
        + len({e.event_id.value for e in definition.events}),
    }


class _Watch:
    """What the inputs need from each moment of the run."""

    def __init__(self, trip: Trip) -> None:
        self.trip = trip
        self.owed_at_once = 0
        self.blockers = 0
        self.seen_tokens = 1
        """The next token id not looked at yet."""
        self.payers: dict[str, None] = {}
        """Passengers whose first fare was counted for `blockers`."""
        self.changes: dict[int, tuple[str, bool]] = {}
        """Change on its way: token id → (its passenger, dropped when last seen)."""
        self.arrivals: list[tuple[str, int]] = []
        """(passenger, t_ms) for each change that reached them."""
        self.gone_at: dict[str, int] = {}
        self.observe()

    def observe(self) -> None:
        state = self.trip.state
        t = state.t_ms
        owed = 0
        for passenger in state.passengers:
            if passenger.presence is Presence.ABOARD:
                if passenger.is_owed:
                    owed += 1
            elif passenger.presence is Presence.GONE and passenger.passenger_id not in self.gone_at:
                self.gone_at[passenger.passenger_id] = t
        self.owed_at_once = max(self.owed_at_once, owed)
        tokens = state.tokens
        for token_id in range(self.seen_tokens, state.next_token_id):
            token = tokens.get(token_id)
            if token is None:
                continue
            if token.kind is TokenKind.FARE and token.owner not in self.payers:
                self.payers[token.owner] = None
                self.blockers += self._blockers(token.owner)
            elif token.kind in _CHANGE:
                self.changes[token_id] = (token.target, False)
        self.seen_tokens = state.next_token_id
        for token_id, (owner, dropped) in list(self.changes.items()):
            token = tokens.get(token_id)
            if token is not None:
                self.changes[token_id] = (owner, token.dropped_until_ms is not None)
                continue
            del self.changes[token_id]
            if not dropped:
                self.arrivals.append((owner, t))

    def _blockers(self, payer_id: str) -> int:
        """The sleepers and headphones passengers on `payer_id`'s chain to the driver (§5)."""
        trip = self.trip
        archetype = trip.course.archetype
        index = trip.course.passenger_index
        probe = MoneyToken(0, TokenKind.FARE, EMPTY, payer_id, DRIVER, payer_id)
        count = 0
        while (holder := next_holder(trip, probe)) != DRIVER:
            if archetype[index[holder]] in _BLOCKING:
                count += 1
            probe.holder = holder
        return count
