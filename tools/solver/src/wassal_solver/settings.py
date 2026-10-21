"""The solver settings: one integer-only record in `data/settings.json` (data-model.md
"SolverSettings", research R12).

The settings decide which trips pass validation, and the game never reads them, so they are not
tunables (constitution VIII). `settings_version` is a hash of the record, so nobody bumps it.
"""

from __future__ import annotations

import hashlib
from collections.abc import Mapping
from dataclasses import dataclass
from functools import cache
from importlib import resources
from pathlib import Path
from typing import Any

from wassal_content.canonical import canonical_bytes
from wassal_content.loader import ContentLoadError, load_json_bytes

__all__ = [
    "SCORE_INPUTS",
    "ScoreTable",
    "ScoreTerm",
    "SettingsError",
    "SolverSettings",
    "load_settings",
]

SETTINGS_FILE = "settings.json"
SCORE_INPUTS = (
    "owed_at_once",
    "change_pieces",
    "blockers",
    "breaks",
    "tightness_ms",
    "variety",
)
"""The difficulty score's inputs, in the order they are reported (contracts/solver.md §5)."""
_TERM_KEYS = ("free", "per", "unit", "cap")
_TOP_KEYS = (
    "reaction_ms",
    "tap_ms",
    "effort_budget_steps",
    "safety_cap_seconds",
    "transposition_cap",
    "report_reaction_ms",
    "score",
)


class SettingsError(ValueError):
    """A settings record that is not strict JSON, or doesn't have the record's shape."""


@dataclass(frozen=True, slots=True)
class ScoreTerm:
    """One input's points: `min(cap, max(0, value - free) * per // unit)`."""

    free: int
    per: int
    unit: int
    cap: int

    def to_json(self) -> dict[str, int]:
        return {"free": self.free, "per": self.per, "unit": self.unit, "cap": self.cap}


@dataclass(frozen=True, slots=True)
class ScoreTable:
    """The score's table (contracts/solver.md §5)."""

    slack_ref_ms: int
    terms: tuple[tuple[str, ScoreTerm], ...]
    """One term per input, in SCORE_INPUTS order."""

    def term(self, name: str) -> ScoreTerm:
        for key, term in self.terms:
            if key == name:
                return term
        raise KeyError(name)

    def to_json(self) -> dict[str, Any]:
        out: dict[str, Any] = {"slack_ref_ms": self.slack_ref_ms}
        out.update((name, term.to_json()) for name, term in self.terms)
        return out


@dataclass(frozen=True, slots=True)
class SolverSettings:
    """How the idealized player plays and how long the search may run (research R7, R8)."""

    reaction_ms: int
    tap_ms: int
    effort_budget_steps: int
    safety_cap_seconds: int
    transposition_cap: int
    report_reaction_ms: tuple[int, ...]
    """The balancing report's slower players."""
    score: ScoreTable

    def to_json(self) -> dict[str, Any]:
        return {
            "reaction_ms": self.reaction_ms,
            "tap_ms": self.tap_ms,
            "effort_budget_steps": self.effort_budget_steps,
            "safety_cap_seconds": self.safety_cap_seconds,
            "transposition_cap": self.transposition_cap,
            "report_reaction_ms": list(self.report_reaction_ms),
            "score": self.score.to_json(),
        }

    @property
    def settings_version(self) -> str:
        """The first 16 hex digits of the SHA-256 of the record's canonical JSON."""
        return hashlib.sha256(canonical_bytes(self.to_json())).hexdigest()[:16]

    @classmethod
    def from_json(cls, document: object) -> SolverSettings:
        """Reads a record, refusing unknown keys, missing keys, non-integers and negatives, and a
        budget or safety cap of 0, which would stop every search at once."""
        top = _object(document, "settings", _TOP_KEYS)
        score = _object(top["score"], "score", ("slack_ref_ms", *SCORE_INPUTS))
        return cls(
            reaction_ms=_count(top, "reaction_ms", ""),
            tap_ms=_count(top, "tap_ms", ""),
            effort_budget_steps=_positive(top, "effort_budget_steps"),
            safety_cap_seconds=_positive(top, "safety_cap_seconds"),
            transposition_cap=_count(top, "transposition_cap", ""),
            report_reaction_ms=_counts(top["report_reaction_ms"], "report_reaction_ms"),
            score=ScoreTable(
                slack_ref_ms=_count(score, "slack_ref_ms", "score."),
                terms=tuple((name, _term(score[name], f"score.{name}")) for name in SCORE_INPUTS),
            ),
        )


def _object(value: object, path: str, keys: tuple[str, ...]) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise SettingsError(f"settings: {path} must be an object")
    prefix = "" if path == "settings" else f"{path}."
    for key in value:
        if key not in keys:
            raise SettingsError(f"settings: unknown key {prefix}{key}")
    for key in keys:
        if key not in value:
            raise SettingsError(f"settings: {prefix}{key} is missing")
    return value


def _integer(value: object, path: str) -> int:
    if type(value) is not int:
        raise SettingsError(f"settings: {path} must be an integer")
    if value < 0:
        raise SettingsError(f"settings: {path} must not be negative")
    return value


def _count(record: Mapping[str, Any], key: str, prefix: str) -> int:
    return _integer(record[key], f"{prefix}{key}")


def _positive(record: Mapping[str, Any], key: str) -> int:
    value = _count(record, key, "")
    if value < 1:
        raise SettingsError(f"settings: {key} must be at least 1")
    return value


def _counts(value: object, path: str) -> tuple[int, ...]:
    if not isinstance(value, list):
        raise SettingsError(f"settings: {path} must be a list of integers")
    return tuple(_integer(item, f"{path}[{i}]") for i, item in enumerate(value))


def _term(value: object, path: str) -> ScoreTerm:
    record = _object(value, path, _TERM_KEYS)
    term = ScoreTerm(*(_count(record, key, f"{path}.") for key in _TERM_KEYS))
    if term.unit < 1:
        raise SettingsError(f"settings: {path}.unit must be at least 1")
    return term


@cache
def _packaged() -> SolverSettings:
    data = resources.files("wassal_solver").joinpath("data", SETTINGS_FILE).read_bytes()
    return _read(data)


def _read(data: bytes) -> SolverSettings:
    try:
        document = load_json_bytes(data)
    except ContentLoadError as error:
        raise SettingsError(f"settings: not strict JSON: {error}") from None
    return SolverSettings.from_json(document)


def load_settings(path: Path | None = None) -> SolverSettings:
    """The packaged settings, or the record in `path`."""
    if path is None:
        return _packaged()
    return _read(path.read_bytes())
