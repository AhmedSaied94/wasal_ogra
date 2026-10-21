"""Reading the trips the commands work on: one trip file, or a `content/source`-style layout
(contracts/cli.md). A layout's trip carries its line's band; a lone trip has none."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from wassal_content.findings import Finding
from wassal_content.loader import ContentLoadError, load_json_bytes
from wassal_content.models import TripDefinition, parse
from wassal_content.source import SourceTree, read_layout
from wassal_content.validate import document_findings

from wassal_solver.scoring.difficulty import Band

__all__ = [
    "Band",
    "InputError",
    "TripInput",
    "read_layout_trips",
    "read_trip_document",
    "read_trip_file",
    "read_trips",
]


class InputError(ValueError):
    """A file or layout that can't be read as trips."""


@dataclass(frozen=True, slots=True)
class TripInput:
    definition: TripDefinition
    band: Band | None


def read_trips(path: Path, trip_id: str | None = None) -> list[TripInput]:
    """The trips of a trip file or a layout directory, in trip id order, or only `trip_id`."""
    trips = read_layout_trips(path)[1] if path.is_dir() else [read_trip_file(path)]
    if trip_id is None:
        return trips
    chosen = [trip for trip in trips if trip.definition.trip_id == trip_id]
    if not chosen:
        raise InputError(f"no trip {trip_id} in {path}")
    return chosen


def read_trip_file(path: Path) -> TripInput:
    try:
        document = load_json_bytes(path.read_bytes())
    except ContentLoadError as error:
        raise InputError(f"{path}: not strict JSON: {error}") from None
    return TripInput(_definition(document, str(path)), None)


def read_layout_trips(root: Path) -> tuple[SourceTree, list[TripInput]]:
    """The layout's tree and its trips. Any error in the layout refuses it."""
    tree, findings = read_layout(root)
    errors = [f for f in findings if f.severity == "error" and f.code not in _ENGINE_RULES]
    if errors:
        shown = "; ".join(_show(finding) for finding in errors[:3])
        raise InputError(f"{root}: {len(errors)} error(s) in the layout: {shown}")
    bands = {
        line["line_id"]: Band(line["difficulty_band"]["min"], line["difficulty_band"]["max"])
        for line in tree.parts["lines"]
    }
    definitions = [
        _definition(document, f"{root} trip {document.get('trip_id')}")
        for document in tree.parts["trips"]
    ]
    trips = [TripInput(d, bands.get(d.line_id)) for d in definitions]
    trips.sort(key=lambda t: t.definition.trip_id)
    return tree, trips


def read_trip_document(document: Any, where: str) -> TripDefinition:
    """A trip document already parsed from JSON, checked as `read_trip_file` checks a file."""
    return _definition(document, where)


def _definition(document: Any, where: str) -> TripDefinition:
    findings = document_findings("trip", document)
    errors = [f for f in findings if f.severity == "error" and f.code not in _ENGINE_RULES]
    if errors:
        shown = "; ".join(_show(finding) for finding in errors[:3])
        raise InputError(f"{where}: not a valid trip: {shown}")
    definition = parse("trip", document)
    if not isinstance(definition, TripDefinition):
        raise InputError(f"{where}: not a trip")
    return definition


def _show(finding: Finding) -> str:
    where = f"{finding.file} " if finding.file else ""
    return f"{where}{finding.path} [{finding.code}] {finding.message}"


_ENGINE_RULES = frozenset({"V-T8", "V-T9", "V-T10", "V-T11"})
"""What the engine plays (B04's capability rules). A trip that breaks only these is still read, so
the solver can report the mirror's refusal (US2 scenario 6)."""
