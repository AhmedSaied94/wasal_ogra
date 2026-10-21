"""The balancing report: one row per trip, for the designer (contracts/solver.md §6, research R17).

Each row holds the default player's result, the slack at each station of the run, and how the
slower players of `report_reaction_ms` fare. Slower players appear nowhere else (FR-043).
"""

from __future__ import annotations

import csv
import dataclasses
import logging
from collections.abc import Sequence
from typing import TextIO

from wassal_content.models import TripDefinition

from wassal_solver.engine.replay import ReplayRefused, replay
from wassal_solver.scoring.difficulty import observe_run
from wassal_solver.settings import SCORE_INPUTS, SolverSettings
from wassal_solver.solver import SolverResult, solve
from wassal_solver.tunables import bundled_params

__all__ = ["Row", "columns", "render_table", "report", "write_csv"]

logger = logging.getLogger(__name__)

Row = dict[str, object]
"""Column name → value, in `columns(settings)` order. An empty string where there is none."""

_SLOWER = ("stars", "fights", "mistakes")


def columns(settings: SolverSettings) -> list[str]:
    """The report's columns (data-model.md "Balancing report row")."""
    slower = [f"r{ms}_{what}" for ms in settings.report_reaction_ms for what in _SLOWER]
    return ["trip_id", "verdict", "stars", "score", *SCORE_INPUTS, "slack_ms", *slower]


def report(trips: Sequence[TripDefinition], settings: SolverSettings) -> list[Row]:
    """One row per trip, in the order given."""
    return [_row(definition, settings) for definition in trips]


def _row(definition: TripDefinition, settings: SolverSettings) -> Row:
    params = bundled_params(definition.line_id)
    result = solve(definition, params, settings)
    row: Row = {
        "trip_id": definition.trip_id,
        "verdict": result.verdict.value,
        "stars": result.stars,
    }
    score = result.score
    row["score"] = "" if score is None else score.value
    for name in SCORE_INPUTS:
        row[name] = "" if score is None else score.input(name).value
    row["slack_ms"] = _slack(definition, result)
    for ms in settings.report_reaction_ms:
        slower = solve(definition, params, dataclasses.replace(settings, reaction_ms=ms))
        stars, fights, mistakes = _played(definition, slower)
        row[f"r{ms}_stars"] = stars
        row[f"r{ms}_fights"] = fights
        row[f"r{ms}_mistakes"] = mistakes
    return row


def _slack(definition: TripDefinition, result: SolverResult) -> str:
    """`station:ms;…`: the least slack of the changes to each station's passengers, in station
    order, for a solved run."""
    if result.run is None:
        return ""
    try:
        observed = observe_run(definition, result.run, bundled_params(definition.line_id))
    except ValueError as error:
        _not_replayed(definition, error)
        return ""
    dest = {p.passenger_id: p.dest_station_id for p in definition.passengers}
    least: dict[str, int] = {}
    for passenger_id, slack in observed.slacks:
        station = dest[passenger_id]
        least[station] = min(slack, least.get(station, slack))
    return ";".join(
        f"{s.station_id}:{least[s.station_id]}"
        for s in definition.stations
        if s.station_id in least
    )


def _played(definition: TripDefinition, result: SolverResult) -> tuple[object, object, object]:
    """The stars, fights and mistakes of the run, or of the best run."""
    log = result.run if result.run is not None else result.best_run
    if log is None:
        return result.stars, "", ""
    try:
        played = replay(definition, definition.seed, bundled_params(definition.line_id), log)
    except ReplayRefused as error:
        _not_replayed(definition, error)
        return result.stars, "", ""
    return played.stars, played.fights, len(played.mistakes)


def _not_replayed(definition: TripDefinition, error: Exception) -> None:
    """Only a mirror bug makes a solver run fail to replay. Its cells stay empty, and the other
    rows still come out."""
    logger.warning("report: the run of %s does not replay: %s", definition.trip_id, error)


def render_table(rows: Sequence[Row], settings: SolverSettings) -> str:
    """A fixed-width table: the header, then one line per row."""
    names = columns(settings)
    cells = [names, *([str(row[name]) for name in names] for row in rows)]
    widths = [max(len(line[i]) for line in cells) for i in range(len(names))]
    return "\n".join(
        "  ".join(cell.ljust(width) for cell, width in zip(line, widths, strict=True)).rstrip()
        for line in cells
    )


def write_csv(rows: Sequence[Row], settings: SolverSettings, out: TextIO) -> None:
    """The rows as CSV, with a header and `\\n` line ends."""
    names = columns(settings)
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(names)
    for row in rows:
        writer.writerow([row[name] for name in names])
