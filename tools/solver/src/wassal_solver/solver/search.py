"""The depth-first search over decisions (contracts/solver.md §2 and §3, research R8 and R9).

The search plays the idealized player on clones of the mirror. A node is a step at which some
decision is ready. Its children are the ready decisions in search order, then `wait`. A branch is
cut at its first star loss, and a 3-star finish ends the search.

Nothing here reads a clock except the safety cap, which is its own end (research R9). No set is
iterated, and the visited table is matched by digest, so `PYTHONHASHSEED` changes nothing.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from enum import StrEnum
from time import monotonic

from wassal_content.canonical import canonical_bytes

from wassal_solver.engine.clock import STEP_MS
from wassal_solver.engine.commands import LoggedCommand
from wassal_solver.engine.model import AlightOutcome, MistakeKind, Presence, TripStatus
from wassal_solver.engine.trip import Trip
from wassal_solver.settings import SolverSettings
from wassal_solver.solver.decisions import (
    Decision,
    DecisionKind,
    Timing,
    certain_loss,
    possible_decisions,
    round_to_step,
)
from wassal_solver.solver.timeline import Loss, TimelineEntry, entry_for

__all__ = ["End", "Run", "SearchOutcome", "Taken", "run_search"]

SAFETY_CHECK_STEPS = 1024
"""The safety cap is checked every this many steps."""
_SAFETY_MASK = SAFETY_CHECK_STEPS - 1
_NEVER = 1 << 62
"""Later than any trip time."""
_DIGEST_BYTES = 16


class End(StrEnum):
    """How a search ended (research R8)."""

    FOUND = "found"
    EXHAUSTED = "exhausted"
    BUDGET_SPENT = "budget_spent"
    SAFETY_CAP = "safety_cap"
    INTERNAL_ERROR = "internal_error"
    REFUSED = "refused"


@dataclass(frozen=True, slots=True)
class Taken:
    """A decision as carried out: its commands, one tap time apart, and its timeline entry."""

    decision: Decision
    commands: tuple[LoggedCommand, ...]
    entry: TimelineEntry


@dataclass(frozen=True, slots=True)
class Run:
    """A branch played to its end."""

    trip: Trip
    taken: tuple[Taken, ...]
    loss: Loss | None
    stars: int

    @property
    def rank(self) -> tuple[int, int]:
        """The best run has the most stars, then the latest first loss."""
        return self.stars, _NEVER if self.loss is None else self.loss.t_ms


@dataclass(frozen=True, slots=True)
class SearchOutcome:
    end: End
    run: Run | None
    """The 3-star run when `found`, else the best run, if any branch was played."""
    effort_steps: int


class _Stop(Exception):
    def __init__(self, end: End) -> None:
        super().__init__(end.value)
        self.end = end


class _Is(StrEnum):
    """What advancing a branch led to."""

    NODE = "node"
    FOUND = "found"
    CUT = "cut"
    """It lost a star (or, played on, it ended)."""
    DROPPED = "dropped"
    """A command of its decision was rejected."""


_WAIT = None
"""The `wait` option, after the ready decisions."""


class _Branch:
    """One line of play: the trip, and what the player's timing depends on."""

    __slots__ = (
        "doomed",
        "last_end",
        "loss",
        "next_ready",
        "possible",
        "signature",
        "since",
        "taken",
        "trip",
    )

    def __init__(self, trip: Trip) -> None:
        self.trip = trip
        self.since: dict[Decision, int] = {}
        """Each possible decision, in search order, and the step it became possible."""
        self.possible: tuple[Decision, ...] = ()
        self.signature: object = None
        self.last_end = 0
        """The `t_ms` of the last command of the decision before, or 0 at the start."""
        self.next_ready: int | None = None
        """The soonest step at which a possible decision is ready."""
        self.taken: tuple[Taken, ...] = ()
        self.loss: Loss | None = None
        self.doomed: tuple[str, int] | None = None
        """A passenger who will certainly get off owed, and the step of their stop."""

    def clone(self) -> _Branch:
        copy = _Branch(self.trip.clone())
        copy.since = dict(self.since)
        copy.possible = self.possible
        copy.signature = self.signature
        copy.last_end = self.last_end
        copy.next_ready = self.next_ready
        copy.taken = self.taken
        copy.loss = self.loss
        copy.doomed = self.doomed
        return copy

    def ready_at(self, decision: Decision, reaction_ms: int) -> int:
        since = self.since[decision]
        return (since if since > self.last_end else self.last_end) + reaction_ms

    def ready(self, reaction_ms: int) -> tuple[Decision, ...]:
        t = self.trip.state.t_ms
        if self.next_ready is None or t < self.next_ready:
            return ()
        return tuple(d for d in self.possible if self.ready_at(d, reaction_ms) <= t)


def _signature(tx: Trip) -> object:
    """What the possible decisions depend on. Only when it changes are they worked out again."""
    state = tx.state
    return (
        state.tray.counts,
        state.hand.total,
        state.next_token_id,
        len(state.tokens),
        tuple(state.claims),
        tuple(state.disputes),
        tuple(state.change_requests),
        state.breaks_used,
        state.next_station_index,
        state.events_fired.count(True),
        tuple(
            [
                (p.presence, p.alertness, p.fare_sent, p.balance, p.never_pays)
                for p in state.passengers
            ]
        ),
    )


def _first_loss(tx: Trip) -> Loss | None:
    """The star loss in `tx`'s state, if any: a failure, a fight, then a mistake."""
    state = tx.state
    t = state.t_ms
    if state.status is TripStatus.FAILED:
        return Loss("failed", t, None, None, "the reputation fell to 0")
    if state.counters.fights:
        for q, passenger in enumerate(state.passengers):
            if passenger.outcome is AlightOutcome.FIGHT:
                owed = sum(
                    m.amount_piasters
                    for m in state.mistakes
                    if m.passenger_id == passenger.passenger_id
                )
                return Loss(
                    "fight", t, passenger.passenger_id, _station_of(tx, q), f"left owed {owed}"
                )
        return Loss("fight", t, None, None, "a false accusation")
    if state.mistakes:
        mistake = state.mistakes[0]
        q = tx.course.passenger_index[mistake.passenger_id]
        detail = _MISTAKES[mistake.kind].format(mistake.amount_piasters)
        return Loss("mistake", t, mistake.passenger_id, _station_of(tx, q), detail)
    return None


_MISTAKES = {
    MistakeKind.OVER: "given {} too much change",
    MistakeKind.NOT_OWED: "given {} they weren't owed",
    MistakeKind.UNRETURNED: "got off still owed {}",
}


def _station_of(tx: Trip, q: int) -> str | None:
    """The stop of passenger `q`, if they have got off."""
    if tx.state.passengers[q].presence is not Presence.GONE:
        return None
    return tx.state.schedule[tx.course.dest_index[q]].station_id


@dataclass(slots=True)
class _Frame:
    branch: _Branch
    options: tuple[Decision | None, ...]
    next: int = 0


class _Search:
    def __init__(self, settings: SolverSettings) -> None:
        self.settings = settings
        self.timing = Timing.of(settings)
        self.effort = 0
        self.started = monotonic()
        self.visited: set[bytes] = set()
        """Digests of the nodes seen. Only membership is read."""
        self.best: Run | None = None
        self.enforce_budget = True

    # --- Stepping and watching ---------------------------------------------------------------

    def step(self, branch: _Branch) -> None:
        if self.enforce_budget and self.effort >= self.settings.effort_budget_steps:
            raise _Stop(End.BUDGET_SPENT)
        branch.trip.step()
        self.effort += 1
        if (
            self.effort & _SAFETY_MASK == 0
            and monotonic() - self.started >= self.settings.safety_cap_seconds
        ):
            raise _Stop(End.SAFETY_CAP)
        self.observe(branch)

    def observe(self, branch: _Branch) -> None:
        """After a step or a command: the possible decisions, and the first loss."""
        tx = branch.trip
        signature = _signature(tx)
        if signature != branch.signature:
            branch.signature = signature
            t = tx.state.t_ms
            old = branch.since
            possible = possible_decisions(tx)
            branch.possible = possible
            branch.since = {d: old.get(d, t) for d in possible}
            self.refresh(branch)
            if branch.doomed is None:
                branch.doomed = certain_loss(tx)
        if branch.loss is None:
            branch.loss = _first_loss(tx)

    def refresh(self, branch: _Branch) -> None:
        reaction = self.timing.reaction_ms
        branch.next_ready = min(
            (branch.ready_at(d, reaction) for d in branch.possible), default=None
        )

    # --- Moving a branch on ------------------------------------------------------------------

    def settle(self, branch: _Branch, *, prune: bool) -> _Is:
        """What the branch is now, if it isn't a node or still moving."""
        state = branch.trip.state
        if prune and (branch.loss is not None or branch.doomed is not None):
            return _Is.CUT
        if state.status is not TripStatus.RUNNING:
            ok = state.status is TripStatus.FINISHED and branch.loss is None
            return _Is.FOUND if ok else _Is.CUT
        return _Is.NODE

    def advance(self, branch: _Branch, *, prune: bool) -> _Is:
        """Steps until a decision is ready, or the branch ends."""
        while True:
            outcome = self.settle(branch, prune=prune)
            if outcome is not _Is.NODE:
                return outcome
            ready = branch.next_ready
            if ready is not None and branch.trip.state.t_ms >= ready:
                return _Is.NODE
            self.step(branch)

    def decide(self, branch: _Branch, decision: Decision, *, prune: bool) -> _Is:
        """Carries `decision` out, a tap time between its commands, then advances."""
        tx = branch.trip
        logged: list[LoggedCommand] = []
        for i, command in enumerate(decision.commands()):
            if i:
                for _ in range(self.timing.tap_ms // STEP_MS):
                    self.step(branch)
                    outcome = self.settle(branch, prune=prune)
                    if outcome is not _Is.NODE:
                        return outcome
            t = tx.state.t_ms
            if tx.apply(command) is not None:
                return _Is.DROPPED
            logged.append(LoggedCommand(t, command))
            self.observe(branch)
        branch.last_end = logged[-1].t_ms
        entry = entry_for(tx, decision, logged[0].t_ms)
        branch.taken = (*branch.taken, Taken(decision, tuple(logged), entry))
        self.refresh(branch)
        return self.advance(branch, prune=prune)

    def wait(self, branch: _Branch, before: tuple[Decision, ...], *, prune: bool) -> _Is:
        """Steps to the next change in the ready decisions, or to a timing point."""
        point = self.timing_point(branch, before)
        reaction = self.timing.reaction_ms
        while True:
            self.step(branch)
            outcome = self.settle(branch, prune=prune)
            if outcome is not _Is.NODE:
                return outcome
            ready = branch.ready(reaction)
            if ready != before or (point is not None and branch.trip.state.t_ms >= point):
                return _Is.NODE if ready else self.advance(branch, prune=prune)

    def timing_point(self, branch: _Branch, ready: tuple[Decision, ...]) -> int | None:
        """The soonest step after now at which a ready `wake` or `call` is latest: when it still
        makes its passenger able as the next token reaches them or as their stop comes."""
        tx = branch.trip
        state = tx.state
        t = state.t_ms
        params = tx.params
        points: list[int] = []
        for decision in ready:
            if decision.kind is DecisionKind.WAKE:
                lead = params.trip_wake_ms
            elif decision.kind is DecisionKind.CALL:
                lead = self.timing.tap_ms
            else:
                continue
            passenger_id = decision.passenger_id
            q = tx.course.passenger_index[passenger_id or ""]
            needs = [round_to_step(state.schedule[tx.course.dest_index[q]].at_ms)]
            needs.extend(
                t + round_to_step(token.hop_duration_ms - token.hop_elapsed_ms)
                for token in state.tokens.values()
                if token.hop_to == passenger_id and token.target != passenger_id
            )
            points.extend(
                latest for need in needs if (latest := (need - lead) // STEP_MS * STEP_MS) > t
            )
        return min(points, default=None)

    # --- The search --------------------------------------------------------------------------

    def visit(self, branch: _Branch) -> bool:
        """Whether this node is new. The table stops growing at `transposition_cap`."""
        reaction = self.timing.reaction_ms
        key = [
            branch.trip.state.to_json(),
            [[d.to_json(), branch.ready_at(d, reaction)] for d in branch.possible],
        ]
        digest = hashlib.blake2b(canonical_bytes(key), digest_size=_DIGEST_BYTES).digest()
        if digest in self.visited:
            return False
        if len(self.visited) < self.settings.transposition_cap:
            self.visited.add(digest)
        return True

    def run(self, trip: Trip) -> SearchOutcome:
        root = _Branch(trip)
        self.observe(root)
        stack: list[_Frame] = []
        current = root
        try:
            outcome = self.advance(root, prune=True)
            if outcome is _Is.FOUND:
                return self.found(root)
            if outcome is _Is.CUT:
                self.consider(root)
                return self.outcome(End.EXHAUSTED)
            self.visit(root)
            stack.append(self.frame(root))
            while stack:
                frame = stack[-1]
                if frame.next >= len(frame.options):
                    stack.pop()
                    continue
                option = frame.options[frame.next]
                frame.next += 1
                current = child = frame.branch.clone()
                if option is _WAIT:
                    ready = tuple(d for d in frame.options if d is not None)
                    outcome = self.wait(child, ready, prune=True)
                else:
                    outcome = self.decide(child, option, prune=True)
                if outcome is _Is.FOUND:
                    return self.found(child)
                if outcome is _Is.CUT:
                    self.consider(child)
                elif outcome is _Is.NODE and self.visit(child):
                    stack.append(self.frame(child))
            return self.outcome(End.EXHAUSTED)
        except _Stop as stop:
            end = stop.end
            if end is End.BUDGET_SPENT and self.best is None:
                # No branch was played to its end: play on from the deepest node. The safety
                # cap still applies.
                start = stack[-1].branch.clone() if stack else current
                try:
                    self.best = self.play_on(start)
                except _Stop as late:
                    end = late.end
            return self.outcome(end)

    def frame(self, branch: _Branch) -> _Frame:
        return _Frame(branch, (*branch.ready(self.timing.reaction_ms), _WAIT))

    def found(self, branch: _Branch) -> SearchOutcome:
        run = Run(branch.trip, branch.taken, None, self.stars(branch))
        return SearchOutcome(End.FOUND, run, self.effort)

    def outcome(self, end: End) -> SearchOutcome:
        return SearchOutcome(end, self.best, self.effort)

    @staticmethod
    def stars(branch: _Branch) -> int:
        result = branch.trip.result
        return 0 if result is None else result.stars

    def consider(self, branch: _Branch) -> None:
        """A cut branch: played on to its end if it could beat the best run. A certain loss comes
        at the doomed passenger's stop at the latest, and leaves at most 2 stars."""
        loss = branch.loss
        if loss is not None:
            bound = (0 if loss.kind == "failed" else 1 if loss.kind == "fight" else 2, loss.t_ms)
        elif branch.doomed is not None:
            bound = (2, branch.doomed[1])
        else:
            return
        best = self.best
        if best is not None and bound <= best.rank:
            return
        run = self.play_on(branch)
        if best is None or run.rank > best.rank:
            self.best = run

    def play_on(self, branch: _Branch) -> Run:
        """Plays `branch` to its end with the same ordering, without cutting it. Its steps count
        as effort, but the budget doesn't stop it: a trip has an end."""
        enforce = self.enforce_budget
        self.enforce_budget = False
        try:
            outcome = self.advance(branch, prune=False)
            while outcome is _Is.NODE:
                ready = branch.ready(self.timing.reaction_ms)
                for option in (*ready, _WAIT):
                    child = branch.clone()
                    if option is _WAIT:
                        outcome = self.wait(child, ready, prune=False)
                    else:
                        outcome = self.decide(child, option, prune=False)
                    if outcome is not _Is.DROPPED:
                        branch = child
                        break
            return Run(branch.trip, branch.taken, branch.loss, self.stars(branch))
        finally:
            self.enforce_budget = enforce


def run_search(trip: Trip, settings: SolverSettings) -> SearchOutcome:
    """Searches `trip` for a 3-star run, starting from its current state."""
    return _Search(settings).run(trip)
