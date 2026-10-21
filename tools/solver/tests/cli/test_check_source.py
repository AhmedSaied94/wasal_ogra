"""`wassal-solver check-source` (contracts/cli.md, FR-039, FR-040): exit codes and output."""

from __future__ import annotations

import json
import shutil
from dataclasses import replace
from pathlib import Path
from typing import Any

import pytest

import wassal_solver.cli as cli_module
from tests.paths import FAULTS, SAMPLE
from tests.support.solving import SAMPLE_IDS
from wassal_solver.cli import main
from wassal_solver.solver import End, Verdict, solve


def layout_with(tmp_path: Path, fault: str, line: str = "line_hay") -> Path:
    """The sample layout with one fault trip added under its line."""
    root = tmp_path / "layout"
    shutil.copytree(SAMPLE, root)
    document = json.loads((FAULTS / f"{fault}.json").read_text(encoding="utf-8"))
    (root / "trips" / line / f"{document['trip_id']}.json").write_text(
        json.dumps(document, indent=2), encoding="utf-8"
    )
    return root


def run(capsys: pytest.CaptureFixture[str], *args: str) -> tuple[int, str]:
    code = main(["check-source", *args])
    return code, capsys.readouterr().out


def test_the_sample_is_inside_its_bands(capsys: pytest.CaptureFixture[str]) -> None:
    code, out = run(capsys, str(SAMPLE), "--bands", "error")
    assert code == 0
    for trip_id in SAMPLE_IDS:
        assert f"{trip_id}: solved" in out
    assert out.splitlines()[-1] == f"ok {len(SAMPLE_IDS)}"


def test_an_out_of_band_trip_fails_with_bands_error_and_warns_with_warning(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    root = layout_with(tmp_path, "hay_too_hard")
    code, out = run(capsys, str(root), "--bands", "error")
    assert code == 1
    assert "line_hay.98" in out
    assert "62" in out
    assert "0 to 30" in out
    assert "most from owed_at_once, change_pieces" in out
    code, out = run(capsys, str(root), "--bands", "warning")
    assert code == 0
    assert "warning: line_hay.98: difficulty 62 is outside the line's band 0 to 30" in out


def test_the_bands_default_to_a_warning(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert run(capsys, str(layout_with(tmp_path, "hay_too_hard")))[0] == 0


@pytest.mark.parametrize("bands", ["error", "warning"])
def test_an_unsolvable_trip_fails_naming_the_trip_the_version_and_the_file(
    tmp_path: Path, capsys: pytest.CaptureFixture[str], bands: str
) -> None:
    root = layout_with(tmp_path, "change_impossible")
    code, out = run(capsys, str(root), "--bands", bands)
    assert code == 1
    assert "FAILED line_hay.91" in out
    assert "pack version 0" in out
    assert "trips/line_hay/line_hay.91.json" in out
    assert "first fight at 30.030 s (p1, madrasa)" in out
    assert out.splitlines()[-1] == f"failed 1 of {len(SAMPLE_IDS) + 1}"


def test_a_refused_trip_fails(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    code, out = run(capsys, str(layout_with(tmp_path, "unsupported_type")))
    assert code == 1
    assert "FAILED line_hay.97" in out
    assert "unsupported_archetype" in out


@pytest.mark.parametrize("end", [End.SAFETY_CAP, End.INTERNAL_ERROR])
def test_a_safety_cap_or_an_internal_error_fails(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], end: End
) -> None:
    def stopped(*args: Any) -> Any:
        return replace(solve(*args), verdict=Verdict.NOT_SOLVED, end=end, run=None, score=None)

    monkeypatch.setattr(cli_module, "solve", stopped)
    code, out = run(capsys, str(SAMPLE))
    assert code == 1
    assert end.value in out


def test_a_layout_with_no_pack_prints_so_and_passes(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    empty = tmp_path / "source"
    empty.mkdir()
    (empty / "README.md").write_text("nothing yet\n", encoding="utf-8")
    code, out = run(capsys, str(empty))
    assert code == 0
    assert out == f"no pack in {empty}\n"


def test_json_prints_the_canonical_results(capsys: pytest.CaptureFixture[str]) -> None:
    code, out = run(capsys, str(SAMPLE), "--json")
    assert code == 0
    results = [json.loads(line) for line in out.splitlines()]
    assert [result["trip_id"] for result in results] == sorted(SAMPLE_IDS)
    assert all(result["verdict"] == "solved" for result in results)


def test_json_keeps_stdout_to_results_when_a_trip_fails(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    code = main(["check-source", str(layout_with(tmp_path, "change_impossible")), "--json"])
    captured = capsys.readouterr()
    assert code == 1
    results = [json.loads(line) for line in captured.out.splitlines()]
    assert len(results) == len(SAMPLE_IDS) + 1
    assert captured.err == f"failed 1 of {len(SAMPLE_IDS) + 1}\n"


def test_a_path_that_is_not_a_layout_is_a_usage_error(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["check-source", str(FAULTS / "too_fast.json")]) == 2
    assert main(["check-source", str(SAMPLE), "--bands", "loose"]) == 2
