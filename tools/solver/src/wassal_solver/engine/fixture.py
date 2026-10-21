"""A parity fixture (M01 replay-and-fixtures.md §5) as a parsed document: its five keys, how a
replay differs from its `expected_result`, and building one for a solver run.

Mirrors `packages/trip_engine/lib/src/fixture.dart`, which has no `dart:io` either: reading and
writing files is in `wassal_solver.fixture_files`, outside the engine (contracts/mirror.md §5).
"""

from __future__ import annotations

import copy
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any, Final

from pydantic import ValidationError
from wassal_content.canonical import canonical_text
from wassal_content.models import TripDefinition, parse

from wassal_solver.engine.commands import CommandFormatError, LoggedCommand, decode_log
from wassal_solver.engine.params import ParamsError, TripParams
from wassal_solver.engine.replay import replay

FIXTURE_KEYS = ("command_log", "definition", "expected_result", "params", "seed")


class FixtureError(ValueError):
    """A fixture document that isn't the five keys, or whose inputs don't parse."""


class _Missing:
    """A key or list item one side doesn't have."""

    def __repr__(self) -> str:
        return "(missing)"


MISSING: Final = _Missing()


@dataclass(frozen=True, slots=True)
class Difference:
    """The first place two JSON values differ: its path and both values."""

    path: str
    expected: object
    actual: object

    def __str__(self) -> str:
        return f"{self.path}: expected {show_value(self.expected)}, got {show_value(self.actual)}"


def show_value(value: object) -> str:
    """A JSON value as canonical text, or `(missing)`."""
    return repr(value) if value is MISSING else canonical_text(value)


@dataclass(frozen=True, slots=True)
class Fixture:
    definition: TripDefinition
    seed: int
    params: TripParams
    command_log: tuple[LoggedCommand, ...]
    expected_result: Mapping[str, Any]


def parse_fixture(document: object) -> Fixture:
    """The fixture of `document`, with exactly the five keys. Raises FixtureError."""
    if not isinstance(document, dict):
        raise FixtureError("a fixture must be an object")
    keys = sorted(document)
    if keys != list(FIXTURE_KEYS):
        raise FixtureError(f"a fixture has exactly the keys {list(FIXTURE_KEYS)}, not {keys}")
    seed = document["seed"]
    if type(seed) is not int:
        raise FixtureError("seed must be an integer")
    expected = document["expected_result"]
    if not isinstance(expected, dict):
        raise FixtureError("expected_result must be an object")
    params = document["params"]
    if not isinstance(params, dict):
        raise FixtureError("params must be an object")
    try:
        definition = parse("trip", document["definition"])
        return Fixture(
            definition=definition,  # type: ignore[arg-type]
            seed=seed,
            params=TripParams.from_json(params),
            command_log=tuple(decode_log(document["command_log"])),
            expected_result=expected,
        )
    except (ValidationError, ParamsError, CommandFormatError) as error:
        raise FixtureError(str(error)) from None


def first_difference(expected: object, actual: object, path: str = "$") -> Difference | None:
    """The first place `actual` differs from `expected`: keys in sorted order, then list items
    in order. A bool is not an int."""
    if type(expected) is not type(actual):
        return Difference(path, expected, actual)
    if isinstance(expected, dict) and isinstance(actual, dict):
        for key in sorted(set(expected) | set(actual)):
            mine = expected.get(key, MISSING)
            theirs = actual.get(key, MISSING)
            found = first_difference(mine, theirs, f"{path}.{key}")
            if found is not None:
                return found
        return None
    if isinstance(expected, list) and isinstance(actual, list):
        for i in range(max(len(expected), len(actual))):
            mine = expected[i] if i < len(expected) else MISSING
            theirs = actual[i] if i < len(actual) else MISSING
            found = first_difference(mine, theirs, f"{path}[{i}]")
            if found is not None:
                return found
        return None
    return None if expected == actual else Difference(path, expected, actual)


def check_fixture(document: object) -> Difference | None:
    """How replaying the fixture's inputs differs from its `expected_result`, or None when it
    holds. Raises FixtureError, or ReplayRefused when the log no longer replays."""
    fixture = parse_fixture(document)
    result = replay(fixture.definition, fixture.seed, fixture.params, fixture.command_log)
    return first_difference(dict(fixture.expected_result), result.to_json())


def build_fixture(
    document: Mapping[str, Any], params: TripParams, run: Sequence[LoggedCommand]
) -> dict[str, Any]:
    """A solver fixture (contracts/mirror.md §6): the trip as given, its own seed, `params`, the
    run, and the result the mirror's replay gives. Python writes only new fixtures; an existing
    `expected_result` is rewritten by Dart's `update` alone."""
    definition = parse("trip", document)
    if not isinstance(definition, TripDefinition):
        raise FixtureError("the definition is not a trip")
    result = replay(definition, definition.seed, params, run)
    return {
        "definition": copy.deepcopy(dict(document)),
        "seed": definition.seed,
        "params": params.to_json(),
        "command_log": [entry.to_json() for entry in run],
        "expected_result": result.to_json(),
    }
