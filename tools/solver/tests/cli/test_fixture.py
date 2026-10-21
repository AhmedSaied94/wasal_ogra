"""`wassal-solver fixture` (contracts/cli.md, contracts/mirror.md §6)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from tests.paths import FAULTS, SAMPLE
from wassal_solver.cli import main
from wassal_solver.fixture_files import check_fixtures

HAY_01 = SAMPLE / "trips" / "line_hay" / "line_hay.01.json"
HAY_02 = SAMPLE / "trips" / "line_hay" / "line_hay.02.json"


def test_it_writes_a_solver_fixture_named_after_the_trip(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["fixture", str(HAY_01), str(HAY_02), "--out", str(tmp_path)]) == 0
    written = sorted(path.name for path in tmp_path.iterdir())
    assert written == ["solver__line_hay_01.json", "solver__line_hay_02.json"]
    assert check_fixtures(sorted(tmp_path.iterdir())) == []
    document = json.loads((tmp_path / written[0]).read_text(encoding="utf-8"))
    assert document["definition"] == json.loads(HAY_01.read_text(encoding="utf-8"))
    assert document["expected_result"]["stars"] == 3
    assert "wrote" in capsys.readouterr().out


def test_an_existing_fixture_is_never_overwritten(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    existing = tmp_path / "solver__line_hay_01.json"
    existing.write_text("{}\n", encoding="utf-8")
    assert main(["fixture", str(HAY_01), str(HAY_02), "--out", str(tmp_path)]) == 1
    assert existing.read_text(encoding="utf-8") == "{}\n"
    assert not (tmp_path / "solver__line_hay_02.json").exists()
    assert "already exists" in capsys.readouterr().out


def test_a_trip_that_is_not_solved_writes_nothing(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    trips = [str(HAY_01), str(FAULTS / "change_impossible.json")]
    assert main(["fixture", *trips, "--out", str(tmp_path)]) == 1
    assert list(tmp_path.iterdir()) == []
    assert "line_hay.91" in capsys.readouterr().out


def test_no_trip_is_a_usage_error() -> None:
    assert main(["fixture"]) == 2


def test_a_trip_given_twice_writes_nothing(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["fixture", str(HAY_01), str(HAY_01), "--out", str(tmp_path)]) == 1
    assert list(tmp_path.iterdir()) == []
    assert "line_hay.01 is given twice" in capsys.readouterr().out
