"""The balancing report (contracts/solver.md §6, data-model.md "Balancing report row")."""

from __future__ import annotations

import ast
import io
from pathlib import Path
from typing import Any

import pytest

from tests.paths import PACKAGE_ROOT, REPO
from tests.support.solving import SAMPLE_IDS, sample_trips, settings_with
from wassal_solver.engine.replay import ReplayReason, ReplayRefused
from wassal_solver.engine.replay import replay as real_replay
from wassal_solver.report import balancing
from wassal_solver.report.balancing import columns, render_table, report, write_csv
from wassal_solver.scoring.difficulty import observe_run as real_observe

BASE = [
    "trip_id",
    "verdict",
    "stars",
    "score",
    "owed_at_once",
    "change_pieces",
    "blockers",
    "breaks",
    "tightness_ms",
    "variety",
    "slack_ms",
]


def test_one_row_per_trip_in_order_with_every_column() -> None:
    settings = settings_with()
    rows = report(sample_trips(), settings)
    assert [row["trip_id"] for row in rows] == SAMPLE_IDS
    expected = [
        *BASE,
        *(f"r{ms}_{what}" for ms in (900, 1200) for what in ("stars", "fights", "mistakes")),
    ]
    assert columns(settings) == expected
    for row in rows:
        assert list(row) == expected
        assert row["verdict"] == "solved"
        assert row["stars"] == 3
        assert isinstance(row["score"], int)


def test_the_slack_is_per_station_in_station_order() -> None:
    rows = report(sample_trips(), settings_with())
    hay_01 = next(row for row in rows if row["trip_id"] == "line_hay.01")
    stations = [part.split(":")[0] for part in str(hay_01["slack_ms"]).split(";")]
    assert stations == ["madrasa", "forn"]
    assert all(int(part.split(":")[1]) > 0 for part in str(hay_01["slack_ms"]).split(";"))


def test_the_slower_player_columns_follow_report_reaction_ms() -> None:
    settings = settings_with(report_reaction_ms=(700,))
    rows = report(sample_trips()[:1], settings)
    assert [name for name in rows[0] if name.startswith("r")] == [
        "r700_stars",
        "r700_fights",
        "r700_mistakes",
    ]


def test_two_runs_give_identical_tables_and_csv() -> None:
    settings = settings_with()
    first, second = report(sample_trips(), settings), report(sample_trips(), settings)
    assert render_table(first, settings) == render_table(second, settings)
    one, two = io.StringIO(), io.StringIO()
    write_csv(first, settings, one)
    write_csv(second, settings, two)
    assert one.getvalue() == two.getvalue()
    lines = one.getvalue().split("\n")
    assert lines[0] == ",".join(columns(settings))
    assert len([line for line in lines if line]) == len(SAMPLE_IDS) + 1


def test_slower_players_are_read_only_by_the_report() -> None:
    """FR-043: `report_reaction_ms` stays out of builds, previews and CI."""
    allowed = {
        PACKAGE_ROOT / "src" / "wassal_solver" / "settings.py",
        *(PACKAGE_ROOT / "src" / "wassal_solver" / "report").rglob("*.py"),
    }
    sources = [
        *(PACKAGE_ROOT / "src" / "wassal_solver").rglob("*.py"),
        *(REPO / "backend" / "apps").rglob("*.py"),
        *(REPO / "backend" / "config").rglob("*.py"),
    ]
    readers = [
        path.relative_to(REPO)
        for path in sources
        if path not in allowed and _names(path) & {"report_reaction_ms"}
    ]
    assert readers == []


def _names(path: Path) -> set[str]:
    found: set[str] = set()
    for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
        if isinstance(node, ast.Attribute):
            found.add(node.attr)
        elif isinstance(node, ast.Name):
            found.add(node.id)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str):
            found.add(node.value)
    return found


def test_a_run_that_does_not_replay_leaves_its_cells_empty_and_the_report_goes_on(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    """Only a mirror bug can make a solver run fail to replay; the other rows still come out."""

    def replay(definition: Any, *args: Any) -> Any:
        if definition.trip_id == "line_hay.02":
            raise ReplayRefused(ReplayReason.ENTRY_REJECTED, "a mirror bug")
        return real_replay(definition, *args)

    def observe_run(definition: Any, *args: Any) -> Any:
        if definition.trip_id == "line_hay.02":
            raise ValueError("the run does not replay: a mirror bug")
        return real_observe(definition, *args)

    monkeypatch.setattr(balancing, "replay", replay)
    monkeypatch.setattr(balancing, "observe_run", observe_run)
    settings = settings_with()

    rows = {str(row["trip_id"]): row for row in report(sample_trips(), settings)}

    assert sorted(rows) == sorted(SAMPLE_IDS)
    broken = rows["line_hay.02"]
    assert broken["verdict"] == "solved"
    assert broken["slack_ms"] == ""
    assert [broken[f"r{ms}_fights"] for ms in settings.report_reaction_ms] == ["", ""]
    assert rows["line_hay.01"]["slack_ms"] != ""
    assert "the run of line_hay.02 does not replay" in caplog.text
