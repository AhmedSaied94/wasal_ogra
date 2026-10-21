"""The 13 player commands, their wire form `[t_ms, "Name", ...args]`, and how a command is
refused (M01 replay-and-fixtures.md §1, engine-api.md).

Mirrors `packages/trip_engine/lib/src/commands.dart`. As in Dart, `decode` checks the shape of an
entry but not that a denomination is one of glossary §3.2: the engine rejects that with
`bad_argument`. `decode_untrusted` adds that check, for replays of untrusted logs (research R6).
"""

from __future__ import annotations

import hashlib
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from typing import ClassVar

from wassal_content.canonical import canonical_bytes
from wassal_content.models import BoosterId

from wassal_solver.engine.clock import STEP_MS
from wassal_solver.engine.money import is_denomination
from wassal_solver.engine.wire import by_wire


class CommandFormatError(ValueError):
    """A logged command that doesn't decode."""


class RejectionCode(StrEnum):
    """Why a command was refused (engine-api.md), in M01's order."""

    WRONG_STATUS = "wrong_status"
    COMMAND_LIMIT = "command_limit"
    BAD_ARGUMENT = "bad_argument"
    TRAY_EMPTY = "tray_empty"
    HAND_EMPTY = "hand_empty"
    NOT_ABOARD = "not_aboard"
    UNDO_UNAVAILABLE = "undo_unavailable"
    NO_EFFECT = "no_effect"
    NO_CHOICE = "no_choice"
    CANNOT_MAKE_CHANGE = "cannot_make_change"
    BREAK_LIMIT = "break_limit"
    BOOSTER_LIMIT = "booster_limit"
    NOT_REVIVABLE = "not_revivable"


@dataclass(frozen=True, slots=True)
class Rejection:
    """A refused command. The message is English and for developers only."""

    code: RejectionCode
    message: str

    def __str__(self) -> str:
        return f"{self.code.value}: {self.message}"


@dataclass(frozen=True, slots=True)
class PickFromTray:
    """Moves one piece of `denomination` from the tray to the hand."""

    denomination: int
    name: ClassVar[str] = "PickFromTray"

    @property
    def arguments(self) -> tuple[object, ...]:
        return (self.denomination,)


@dataclass(frozen=True, slots=True)
class ReturnHand:
    """Puts the hand back in the tray."""

    name: ClassVar[str] = "ReturnHand"

    @property
    def arguments(self) -> tuple[object, ...]:
        return ()


@dataclass(frozen=True, slots=True)
class SendHand:
    """Sends the hand as change to `passenger_id`."""

    passenger_id: str
    name: ClassVar[str] = "SendHand"

    @property
    def arguments(self) -> tuple[object, ...]:
        return (self.passenger_id,)


@dataclass(frozen=True, slots=True)
class UndoLastSend:
    name: ClassVar[str] = "UndoLastSend"

    @property
    def arguments(self) -> tuple[object, ...]:
        return ()


@dataclass(frozen=True, slots=True)
class Tap:
    passenger_id: str
    name: ClassVar[str] = "Tap"

    @property
    def arguments(self) -> tuple[object, ...]:
        return (self.passenger_id,)


@dataclass(frozen=True, slots=True)
class ResolveClaim:
    """Answers `passenger_id`'s claim: insist they haven't paid, or accept it."""

    passenger_id: str
    insist: bool
    name: ClassVar[str] = "ResolveClaim"

    @property
    def arguments(self) -> tuple[object, ...]:
        return (self.passenger_id, self.insist)


@dataclass(frozen=True, slots=True)
class ResolveDispute:
    """Answers dispute `dispute_id` (its event index): `paid_passenger_id` is the one who paid."""

    dispute_id: int
    paid_passenger_id: str
    name: ClassVar[str] = "ResolveDispute"

    @property
    def arguments(self) -> tuple[object, ...]:
        return (self.dispute_id, self.paid_passenger_id)


@dataclass(frozen=True, slots=True)
class ResolveChangeRequest:
    passenger_id: str
    agree: bool
    name: ClassVar[str] = "ResolveChangeRequest"

    @property
    def arguments(self) -> tuple[object, ...]:
        return (self.passenger_id, self.agree)


@dataclass(frozen=True, slots=True)
class RequestBreak:
    """«حد معاه فكة؟»: breaks one `denomination` note into smaller pieces."""

    denomination: int
    name: ClassVar[str] = "RequestBreak"

    @property
    def arguments(self) -> tuple[object, ...]:
        return (self.denomination,)


@dataclass(frozen=True, slots=True)
class CollectDropped:
    token_id: int
    name: ClassVar[str] = "CollectDropped"

    @property
    def arguments(self) -> tuple[object, ...]:
        return (self.token_id,)


@dataclass(frozen=True, slots=True)
class UseBooster:
    """Uses an in-trip booster: `change_bag`, `wake_all`, `ledger_peek` or `traffic_jam`."""

    booster: BoosterId
    name: ClassVar[str] = "UseBooster"

    @property
    def arguments(self) -> tuple[object, ...]:
        return (self.booster.value,)


@dataclass(frozen=True, slots=True)
class Revive:
    name: ClassVar[str] = "Revive"

    @property
    def arguments(self) -> tuple[object, ...]:
        return ()


@dataclass(frozen=True, slots=True)
class Abandon:
    name: ClassVar[str] = "Abandon"

    @property
    def arguments(self) -> tuple[object, ...]:
        return ()


Command = (
    PickFromTray
    | ReturnHand
    | SendHand
    | UndoLastSend
    | Tap
    | ResolveClaim
    | ResolveDispute
    | ResolveChangeRequest
    | RequestBreak
    | CollectDropped
    | UseBooster
    | Revive
    | Abandon
)


@dataclass(frozen=True, slots=True)
class LoggedCommand:
    """One entry of the command log: a command and the clock when it applied."""

    t_ms: int
    command: Command

    def to_json(self) -> list[object]:
        return [self.t_ms, self.command.name, *self.command.arguments]

    def __str__(self) -> str:
        return str(self.to_json())


COMMAND_NAMES = (
    "PickFromTray",
    "ReturnHand",
    "SendHand",
    "UndoLastSend",
    "Tap",
    "ResolveClaim",
    "ResolveDispute",
    "ResolveChangeRequest",
    "RequestBreak",
    "CollectDropped",
    "UseBooster",
    "Revive",
    "Abandon",
)
"""The 13 wire names."""


def _command(name: str, args: list[object]) -> Command | None:
    """The command `name` with `args`, or None for the wrong arguments. A bool is not an int."""
    match name, args:
        case "PickFromTray", [int() as denomination] if type(denomination) is int:
            return PickFromTray(denomination)
        case "ReturnHand", []:
            return ReturnHand()
        case "SendHand", [str() as passenger]:
            return SendHand(passenger)
        case "UndoLastSend", []:
            return UndoLastSend()
        case "Tap", [str() as passenger]:
            return Tap(passenger)
        case "ResolveClaim", [str() as passenger, bool() as insist]:
            return ResolveClaim(passenger, insist=insist)
        case "ResolveDispute", [int() as dispute, str() as paid] if type(dispute) is int:
            return ResolveDispute(dispute, paid)
        case "ResolveChangeRequest", [str() as passenger, bool() as agree]:
            return ResolveChangeRequest(passenger, agree=agree)
        case "RequestBreak", [int() as denomination] if type(denomination) is int:
            return RequestBreak(denomination)
        case "CollectDropped", [int() as token] if type(token) is int:
            return CollectDropped(token)
        case "UseBooster", [wire]:
            booster = by_wire(BoosterId, wire)
            return None if booster is None else UseBooster(booster)
        case "Revive", []:
            return Revive()
        case "Abandon", []:
            return Abandon()
    return None


def decode(entry: object) -> LoggedCommand:
    """Decodes `[t_ms, "Name", ...args]`. Raises CommandFormatError for an unknown name, the wrong
    arguments, or a `t_ms` that isn't a non-negative multiple of 33."""
    if not isinstance(entry, list) or len(entry) < 2:
        raise CommandFormatError(f'a logged command is [t_ms, "Name", ...args]: {entry!r}')
    t_ms = entry[0]
    if type(t_ms) is not int or t_ms < 0 or t_ms % STEP_MS != 0:
        raise CommandFormatError(f"t_ms must be a non-negative multiple of {STEP_MS}: {entry!r}")
    name = entry[1]
    if type(name) is not str or name not in COMMAND_NAMES:
        raise CommandFormatError(f"unknown command: {entry!r}")
    command = _command(name, entry[2:])
    if command is None:
        raise CommandFormatError(f"bad arguments for {name}: {entry!r}")
    return LoggedCommand(t_ms, command)


def decode_untrusted(entry: object) -> LoggedCommand:
    """`decode`, also refusing a denomination outside glossary §3.2 (research R6)."""
    logged = decode(entry)
    command = logged.command
    if isinstance(command, PickFromTray | RequestBreak) and not is_denomination(
        command.denomination
    ):
        raise CommandFormatError(f"{command.denomination} is not a denomination: {entry!r}")
    return logged


def decode_log(log: object) -> list[LoggedCommand]:
    """Decodes a whole command log. Raises CommandFormatError."""
    if not isinstance(log, list):
        raise CommandFormatError("a command log is a list")
    return [decode(entry) for entry in log]


def command_log_hash(log: Sequence[LoggedCommand]) -> str:
    """`lowercase_hex(sha256(utf8(canonical_json(log))))` (M01 replay-and-fixtures.md §3)."""
    return hashlib.sha256(canonical_bytes([entry.to_json() for entry in log])).hexdigest()
