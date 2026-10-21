"""Helpers for the solver's tests: the sample and fault trips, and solving with changed settings."""

from __future__ import annotations

import dataclasses
import json
from functools import cache
from typing import Any

from wassal_content.models import TripDefinition

from tests.paths import FAULTS, SAMPLE
from tests.support.builders import definition_of
from wassal_solver.settings import SolverSettings, load_settings
from wassal_solver.solver import SolverResult, solve
from wassal_solver.tunables import bundled_params


def settings_with(**changes: Any) -> SolverSettings:
    """The packaged settings with `changes`."""
    return dataclasses.replace(load_settings(), **changes)


def fault(name: str) -> TripDefinition:
    """A crafted trip of SC-004, from `tests/data/faults/<name>.json`."""
    return definition_of(json.loads((FAULTS / f"{name}.json").read_text(encoding="utf-8")))


@cache
def _sample_documents() -> tuple[str, ...]:
    paths = sorted((SAMPLE / "trips").rglob("*.json"))
    return tuple(path.read_text(encoding="utf-8") for path in paths)


def sample_documents() -> list[dict[str, Any]]:
    """The sample pack's trips as JSON data, in trip id order, fresh each call."""
    return [json.loads(text) for text in _sample_documents()]


def sample_trips() -> list[TripDefinition]:
    return [definition_of(document) for document in sample_documents()]


SAMPLE_IDS = [document["trip_id"] for document in sample_documents()]


def sample_trip(trip_id: str) -> TripDefinition:
    return next(trip for trip in sample_trips() if trip.trip_id == trip_id)


def solve_trip(definition: TripDefinition, **changes: Any) -> SolverResult:
    """Solves `definition` with its line's bundled params and the settings with `changes`."""
    return solve(definition, bundled_params(definition.line_id), settings_with(**changes))
