"""Replaying a command log (contracts/mirror.md §3, M01 replay-and-fixtures.md §2 to §4).

Mirrors `replay`, `startReplay` and `playLog` in `packages/trip_engine/lib/src/replay.dart`, with
the same reasons and messages.
"""

from __future__ import annotations

from collections.abc import Sequence
from enum import StrEnum
from typing import Any, cast

from wassal_content.findings import Finding
from wassal_content.loader import MAX_DEPTH, SAFE_INTEGER, ContentLoadError, load_json_bytes
from wassal_content.models import TripDefinition, parse
from wassal_content.validate import document_findings

from wassal_solver.engine.commands import (
    CommandFormatError,
    LoggedCommand,
    Rejection,
    decode_untrusted,
)
from wassal_solver.engine.model import TripResult, TripStatus
from wassal_solver.engine.params import ParamsError, TripParams
from wassal_solver.engine.trip import Trip, start
from wassal_solver.engine.validation import Refusal, TripRefused


class ReplayReason(StrEnum):
    """Why a replay was refused. The first four are Dart's; the rest are the untrusted input's
    (research R6)."""

    TRIP_REFUSED = "trip_refused"
    T_MS_GOES_DOWN = "t_ms_goes_down"
    CLOCK_STOPPED = "clock_stopped"
    ENTRY_REJECTED = "entry_rejected"
    BAD_INPUT = "bad_input"
    BAD_DEFINITION = "bad_definition"
    BAD_PARAMS = "bad_params"
    BAD_LOG = "bad_log"


class ReplayRefused(Exception):
    """A replay the mirror can't follow: the input is malformed, the trip is refused, the log goes
    back in time, an entry comes after the trip stopped, or an entry is rejected."""

    def __init__(
        self,
        reason: ReplayReason,
        message: str,
        *,
        index: int | None = None,
        refusals: Sequence[Refusal] = (),
        rejection: Rejection | None = None,
        findings: Sequence[Finding] = (),
    ) -> None:
        self.reason = reason
        self.message = message
        self.index = index
        """The log entry refused, or None when the input or the trip is."""
        self.refusals = tuple(refusals)
        """The trip's problems, when it is refused at the start."""
        self.rejection = rejection
        self.findings = tuple(findings)
        """The content findings, for `bad_definition`."""
        where = "" if index is None else f" (log entry {index})"
        super().__init__(f"{reason.value}: {message}{where}")


def replay(
    definition: TripDefinition,
    seed: int,
    params: TripParams,
    command_log: Sequence[LoggedCommand],
) -> TripResult:
    """Replays `command_log` to its end: each command at its time, then steps until the trip
    finishes, fails or is abandoned. Raises ReplayRefused."""
    trip = start_replay(definition, params, seed)
    play_log(trip, command_log)
    state = trip.state
    while state.status is TripStatus.RUNNING:
        trip.step()
    result = trip.result
    if result is None:
        raise AssertionError("a replayed trip always ends with a result")
    return result


def start_replay(definition: TripDefinition, params: TripParams, seed: int) -> Trip:
    """Starts a trip to replay, refusing it as a ReplayRefused."""
    try:
        return start(definition, params, seed)
    except TripRefused as refused:
        raise ReplayRefused(
            ReplayReason.TRIP_REFUSED, "the trip is refused", refusals=refused.refusals
        ) from None


def play_log(trip: Trip, command_log: Sequence[LoggedCommand]) -> None:
    """Steps `trip` to each entry of `command_log` and applies it. Every entry must be accepted
    at exactly its `t_ms`."""
    for i, entry in enumerate(command_log):
        if i > 0 and entry.t_ms < command_log[i - 1].t_ms:
            raise ReplayRefused(
                ReplayReason.T_MS_GOES_DOWN, "t_ms goes down along the log", index=i
            )
        trip.step_to(entry.t_ms)
        if trip.t_ms != entry.t_ms:
            raise ReplayRefused(
                ReplayReason.CLOCK_STOPPED,
                f"the clock stopped at {trip.t_ms}, before {entry.t_ms}",
                index=i,
            )
        rejection = trip.apply(entry.command)
        if rejection is not None:
            raise ReplayRefused(
                ReplayReason.ENTRY_REJECTED,
                f"{entry.command.name} was rejected: {rejection.code.value}",
                index=i,
                rejection=rejection,
            )


INPUT_KEYS = ("command_log", "definition", "params", "seed")
MAX_LOG_ENTRIES = 1201
"""The cap of 1,200 accepted commands, plus the `Abandon` it exempts."""
MAX_T_MS = 1_500_000
"""The longest trip (M01 data-model "TripParams"): stations up to 600 s, ten 60 s traffic events
and five 60 s traffic jams."""
MAX_INPUT_BYTES = 256 * 1024
"""The most JSON text read: over three times the longest trip's tuple with a full log, indented
(77 KB), so the parse costs no more than a replay."""


def replay_untrusted(document: object) -> TripResult:
    """Replays a `{definition, seed, params, command_log}` tuple that came from outside, such as a
    player's run (contracts/mirror.md §4, research R6).

    `document` is the JSON text (bytes or str), read strictly, or the value it parsed to. Every
    check runs before any stepping, in this order, and the first that fails refuses: the shape
    (`bad_input`), the definition (`bad_definition`), the params (`bad_params`), the log
    (`bad_log`), then `replay`'s own reasons. Nothing but ReplayRefused is raised.
    """
    value = _parsed(document)
    problem = _json_problem(value)
    if problem is not None:
        raise ReplayRefused(ReplayReason.BAD_INPUT, problem)
    if not isinstance(value, dict):
        raise ReplayRefused(ReplayReason.BAD_INPUT, "the input must be an object")
    keys = sorted(value)
    if keys != list(INPUT_KEYS):
        raise ReplayRefused(
            ReplayReason.BAD_INPUT, f"the input has exactly the keys {list(INPUT_KEYS)}, not {keys}"
        )
    seed = value["seed"]
    if type(seed) is not int:
        raise ReplayRefused(ReplayReason.BAD_INPUT, "seed must be an integer")
    definition = _definition(value["definition"])
    params = _params(value["params"])
    command_log = _log(value["command_log"])
    return replay(definition, seed, params, command_log)


def _parsed(document: object) -> object:
    if isinstance(document, str):
        _check_size(len(document))  # a character is at least one byte
        document = document.encode("utf-8", "surrogatepass")
    if not isinstance(document, bytes):
        return document
    _check_size(len(document))
    try:
        return load_json_bytes(document)
    except ContentLoadError as error:
        raise ReplayRefused(ReplayReason.BAD_INPUT, f"not strict JSON: {error}") from None


def _check_size(size: int) -> None:
    if size > MAX_INPUT_BYTES:
        raise ReplayRefused(ReplayReason.BAD_INPUT, f"the input is over {MAX_INPUT_BYTES} bytes")


def _json_problem(value: object) -> str | None:
    """Why `value` isn't a JSON value with integer numbers only, or None. Walked without
    recursion, so no nesting can exhaust the stack."""
    stack: list[tuple[object, str, int]] = [(value, "$", 0)]
    while stack:
        item, path, depth = stack.pop()
        if depth > MAX_DEPTH:
            return f"{path}: nested more than {MAX_DEPTH} levels deep"
        kind = type(item)
        if item is None or kind is bool or kind is str:
            continue
        if kind is int:
            if not -SAFE_INTEGER <= cast(int, item) <= SAFE_INTEGER:
                return f"{path}: an integer outside ±(2^53 - 1)"
            continue
        if kind is float:
            return f"{path}: a number that isn't an integer"
        if kind is list:
            items = cast(list[object], item)
            stack.extend((child, f"{path}[{i}]", depth + 1) for i, child in enumerate(items))
            continue
        if kind is dict:
            for key, child in cast(dict[object, object], item).items():
                if type(key) is not str:
                    return f"{path}: a key that isn't a string"
                stack.append((child, f"{path}.{key}", depth + 1))
            continue
        return f"{path}: a {kind.__name__} is not a JSON value"
    return None


def _definition(document: Any) -> TripDefinition:
    findings = [f for f in document_findings("trip", document) if f.severity == "error"]
    if findings:
        raise ReplayRefused(
            ReplayReason.BAD_DEFINITION,
            f"the definition has {len(findings)} error(s): "
            f"{findings[0].path} {findings[0].message}",
            findings=findings,
        )
    definition = parse("trip", document)
    if not isinstance(definition, TripDefinition):
        raise AssertionError("parse('trip') returns a TripDefinition")
    return definition


def _params(document: Any) -> TripParams:
    if not isinstance(document, dict):
        raise ReplayRefused(ReplayReason.BAD_PARAMS, "params must be an object")
    try:
        params = TripParams.from_json(document)
    except ParamsError as error:
        raise ReplayRefused(ReplayReason.BAD_PARAMS, str(error)) from None
    problems = params.problems()
    if problems:
        raise ReplayRefused(
            ReplayReason.BAD_PARAMS, "; ".join(f"{p.key}: {p.message}" for p in problems)
        )
    return params


def _log(document: Any) -> list[LoggedCommand]:
    if not isinstance(document, list):
        raise ReplayRefused(ReplayReason.BAD_LOG, "the command log must be a list")
    if len(document) > MAX_LOG_ENTRIES:
        raise ReplayRefused(
            ReplayReason.BAD_LOG, f"the command log has more than {MAX_LOG_ENTRIES} entries"
        )
    log: list[LoggedCommand] = []
    for index, entry in enumerate(document):
        try:
            logged = decode_untrusted(entry)
        except CommandFormatError as error:
            raise ReplayRefused(ReplayReason.BAD_LOG, str(error), index=index) from None
        if logged.t_ms > MAX_T_MS:
            raise ReplayRefused(
                ReplayReason.BAD_LOG, f"t_ms {logged.t_ms} is past {MAX_T_MS}", index=index
            )
        log.append(logged)
    return log
