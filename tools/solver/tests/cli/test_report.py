"""`wassal-solver report` (contracts/cli.md): a layout or a pack file, a table and a CSV."""

from __future__ import annotations

from pathlib import Path

import pytest
from wassal_content.canonical import canonical_bytes
from wassal_content.packfile import build_pack_file
from wassal_content.source import assemble_pack, read_layout

from tests.paths import SAMPLE
from tests.support.solving import SAMPLE_IDS
from wassal_solver.cli import main


def pack_file(tmp_path: Path) -> Path:
    tree, findings = read_layout(SAMPLE)
    assert not [f for f in findings if f.severity == "error"]
    path = tmp_path / "pack.json.gz"
    path.write_bytes(build_pack_file(canonical_bytes(assemble_pack(tree, 1))))
    return path


def test_a_layout_prints_a_table_with_a_row_per_trip(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["report", str(SAMPLE)]) == 0
    lines = capsys.readouterr().out.splitlines()
    assert lines[0].split()[:3] == ["trip_id", "verdict", "stars"]
    assert [line.split()[0] for line in lines[1:]] == SAMPLE_IDS


def test_a_pack_file_gives_the_same_rows(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["report", str(SAMPLE)]) == 0
    from_layout = capsys.readouterr().out
    assert main(["report", str(pack_file(tmp_path))]) == 0
    assert capsys.readouterr().out == from_layout


def test_csv_writes_the_same_rows_and_is_repeatable(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    first, second = tmp_path / "a.csv", tmp_path / "b.csv"
    assert main(["report", str(SAMPLE), "--csv", str(first)]) == 0
    assert main(["report", str(SAMPLE), "--csv", str(second)]) == 0
    assert first.read_bytes() == second.read_bytes()
    rows = first.read_text(encoding="utf-8").splitlines()
    assert rows[0].startswith("trip_id,verdict,stars,score,")
    assert [row.split(",")[0] for row in rows[1:]] == SAMPLE_IDS
    capsys.readouterr()


@pytest.mark.parametrize("args", [[], ["no/such/layout"]])
def test_a_usage_error_exits_2(args: list[str]) -> None:
    assert main(["report", *args]) == 2


def test_a_file_that_is_not_a_pack_is_a_usage_error(tmp_path: Path) -> None:
    bad = tmp_path / "pack.json.gz"
    bad.write_bytes(b"not gzip")
    assert main(["report", str(bad)]) == 2
