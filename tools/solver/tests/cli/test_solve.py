"""`wassal-solver solve` (contracts/cli.md): what it prints and its exit codes."""

from __future__ import annotations

import json

import pytest

from tests.paths import FAULTS, SAMPLE
from tests.support.solving import SAMPLE_IDS
from wassal_solver.cli import main


def run(capsys: pytest.CaptureFixture[str], *args: str) -> tuple[int, str]:
    code = main(["solve", *args])
    return code, capsys.readouterr().out


def test_a_trip_file_prints_the_verdict_the_end_the_stars_and_the_timeline(
    capsys: pytest.CaptureFixture[str],
) -> None:
    code, out = run(capsys, str(FAULTS / "break_needed.json"))
    assert code == 0
    lines = out.splitlines()
    assert lines[0].startswith("line_hay.94 (rev 1): solved, found, 3 stars, ")
    assert any("request_break" in line for line in lines[1:])
    assert any("give_change" in line and "100+100+100" in line for line in lines[1:])


def test_a_layout_solves_every_trip_in_trip_id_order(capsys: pytest.CaptureFixture[str]) -> None:
    code, out = run(capsys, str(SAMPLE))
    assert code == 0
    heads = [line for line in out.splitlines() if not line.startswith(" ")]
    assert [head.split(" ")[0] for head in heads] == sorted(SAMPLE_IDS)
    assert all(": solved, found, 3 stars" in head for head in heads)


def test_one_trip_of_a_layout(capsys: pytest.CaptureFixture[str]) -> None:
    code, out = run(capsys, str(SAMPLE), "--trip", "line_hay.02")
    assert code == 0
    assert out.startswith("line_hay.02 (rev 1): solved")
    assert sum(1 for line in out.splitlines() if not line.startswith(" ")) == 1


def test_json_prints_one_canonical_result_a_line(capsys: pytest.CaptureFixture[str]) -> None:
    code, out = run(capsys, str(SAMPLE), "--json")
    assert code == 0
    results = [json.loads(line) for line in out.splitlines()]
    assert [r["trip_id"] for r in results] == sorted(SAMPLE_IDS)
    for line, result in zip(out.splitlines(), results, strict=True):
        assert line == json.dumps(result, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        assert result["verdict"] == "solved"
        assert {"run", "run_hash", "timeline", "effort_steps", "settings_version"} <= set(result)


def test_a_trip_that_is_not_solved_reports_and_still_exits_0(
    capsys: pytest.CaptureFixture[str],
) -> None:
    code, out = run(capsys, str(FAULTS / "change_impossible.json"))
    assert code == 0
    assert "not_solved, exhausted, 1 stars" in out
    assert "first fight at 30.030 s (p1, madrasa): left owed 300" in out
    assert "lost_star" in out


def test_a_refused_trip_reports_the_refusal_and_exits_0(
    capsys: pytest.CaptureFixture[str],
) -> None:
    code, out = run(capsys, str(FAULTS / "unsupported_type.json"))
    assert code == 0
    assert "refused" in out.splitlines()[0]
    assert "unsupported_archetype" in out


def test_the_reaction_time_can_be_overridden(capsys: pytest.CaptureFixture[str]) -> None:
    trip = str(FAULTS / "too_fast.json")
    assert run(capsys, trip)[1].splitlines()[0].split(": ")[1].startswith("not_solved")
    assert (
        run(capsys, trip, "--reaction-ms", "100")[1]
        .splitlines()[0]
        .split(": ")[1]
        .startswith("solved")
    )


@pytest.mark.parametrize(
    "args",
    [
        [],
        ["no/such/file.json"],
        [str(SAMPLE), "--trip", "line_nowhere.01"],
        [str(FAULTS / "too_fast.json"), "--reaction-ms", "-1"],
        [str(FAULTS / "too_fast.json"), "--reaction-ms", "fast"],
    ],
)
def test_a_usage_error_exits_2(capsys: pytest.CaptureFixture[str], args: list[str]) -> None:
    assert main(["solve", *args]) == 2


def test_a_file_that_is_not_a_trip_is_a_usage_error(
    tmp_path: pytest.TempPathFactory, capsys: pytest.CaptureFixture[str]
) -> None:
    path = tmp_path / "trip.json"  # type: ignore[operator]
    path.write_text('{"trip_id": 1}', encoding="utf-8")
    assert main(["solve", str(path)]) == 2
    assert "not a valid trip" in capsys.readouterr().err
    path.write_text("{", encoding="utf-8")
    assert main(["solve", str(path)]) == 2
