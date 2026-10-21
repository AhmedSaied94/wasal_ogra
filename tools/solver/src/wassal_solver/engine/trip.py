"""The trip shell: starting, stepping and applying commands (contracts/mirror.md §1).

Mirrors `TripEngine` in `packages/trip_engine/lib/src/engine.dart` and `initialState` in
`rules/transition.dart`, without pause, resume or rebuild (research R3). The state is changed in
place; `clone()` gives the solver an independent copy.
"""

from __future__ import annotations

from wassal_content.models import TripDefinition

from wassal_solver.engine.clock import MS_PER_SECOND
from wassal_solver.engine.commands import (
    Command,
    LoggedCommand,
    Rejection,
    command_log_hash,
)
from wassal_solver.engine.model import (
    Counters,
    PassengerState,
    Presence,
    StationState,
    TripResult,
    TripState,
    TripStatus,
)
from wassal_solver.engine.money import EMPTY, Pieces
from wassal_solver.engine.params import TripParams
from wassal_solver.engine.rules.command_handlers import apply_command
from wassal_solver.engine.rules.course import Course
from wassal_solver.engine.rules.passengers import initial_alertness
from wassal_solver.engine.rules.reputation import MAX_REPUTATION
from wassal_solver.engine.rules.step import step_trip
from wassal_solver.engine.validation import TripRefused, validate


class Trip:
    """One trip in progress: its fixed course and params, its state and its accepted commands."""

    __slots__ = ("_log", "course", "params", "seed", "state")

    def __init__(
        self,
        course: Course,
        params: TripParams,
        seed: int,
        state: TripState,
        log: list[LoggedCommand],
    ) -> None:
        self.course = course
        self.params = params
        self.seed = seed
        """The seed the trip started from. The PRNG itself isn't mirrored (research R3)."""
        self.state = state
        self._log = log

    @property
    def definition(self) -> TripDefinition:
        return self.course.definition

    @property
    def status(self) -> TripStatus:
        return self.state.status

    @property
    def t_ms(self) -> int:
        return self.state.t_ms

    @property
    def result(self) -> TripResult | None:
        """Set when the trip finishes, fails or is abandoned."""
        return self.state.result

    @property
    def command_log(self) -> tuple[LoggedCommand, ...]:
        """The accepted commands."""
        return tuple(self._log)

    def step(self) -> None:
        """Advances one 33 ms logic step. Nothing happens unless the trip is running."""
        if self.state.status is TripStatus.RUNNING:
            step_trip(self)

    def step_to(self, t_ms: int) -> None:
        """Steps until the clock reaches `t_ms` or the trip stops running."""
        state = self.state
        while state.status is TripStatus.RUNNING and state.t_ms < t_ms:
            step_trip(self)

    def apply(self, command: Command) -> Rejection | None:
        """Applies `command` at the current clock (RULES.md §4). Returns None when it is accepted
        and logged as `[t_ms, *command]`, else the rejection, with nothing changed."""
        # The result a command builds fingerprints the log with that command in it.
        self._log.append(LoggedCommand(self.state.t_ms, command))
        rejection = apply_command(self, command)
        if rejection is not None:
            self._log.pop()
        return rejection

    def log_hash(self) -> str:
        """The fingerprint of the command log so far."""
        return command_log_hash(self._log)

    def clone(self) -> Trip:
        """An independent copy, for the solver's branches. The course and params are shared:
        they never change."""
        return Trip(self.course, self.params, self.seed, self.state.clone(), list(self._log))


def start(definition: TripDefinition, params: TripParams, seed: int) -> Trip:
    """Starts a trip. Raises TripRefused listing every problem (RULES.md §2)."""
    refusals = validate(definition, params, seed)
    if refusals:
        raise TripRefused(refusals)
    course = Course(definition)
    return Trip(course, params, seed, initial_state(course), [])


def initial_state(course: Course) -> TripState:
    """The first state of a trip (RULES.md §2.2 to §2.5)."""
    definition = course.definition
    return TripState(
        t_ms=0,
        status=TripStatus.RUNNING,
        reputation=MAX_REPUTATION,
        tray=Pieces.from_json(definition.initial_tray),
        hand=EMPTY,
        passengers=[
            PassengerState(
                passenger_id=spec.passenger_id,
                presence=Presence.ABOARD
                if spec.board_station_id is None and i not in course.picked_up
                else Presence.WAITING,
                seat_id=spec.seat_id,
                alertness=initial_alertness(course.archetype[i]),
            )
            for i, spec in enumerate(definition.passengers)
        ],
        tokens={},
        next_token_id=1,
        schedule=[
            StationState(
                station_id=station.station_id,
                at_ms=station.at_seconds * MS_PER_SECOND,
                fare_piasters=station.fare_piasters,
            )
            for station in definition.stations
        ],
        next_station_index=0,
        events_fired=[False] * len(definition.events),
        fare_increase_piasters=0,
        old_fare_payers=set(),
        traffic_active=False,
        claims={},
        disputes={},
        change_requests={},
        pending_breaks=[],
        breaks_used=0,
        ledger_peek_until_ms=None,
        last_send=None,
        counters=Counters(),
        mistakes=[],
        reputation_lost={},
        boosters_used=[],
        revived=False,
        revivable=True,
        commands_accepted=0,
        result=None,
    )
