"""Parity: the mirror replays every fixture of `fixtures/parity/` to its `expected_result`
(research R4, spec FR-010, SC-001).

The Dart suite replays the same files, so a rule changed on one side only fails one of the two.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from tests.paths import FIXTURES
from wassal_solver.engine.fixture import MISSING, Difference, first_difference, parse_fixture
from wassal_solver.engine.replay import replay
from wassal_solver.fixture_files import load_fixture

PATHS = sorted(FIXTURES.glob("*.json"))
STRESS = "stress__longest_trip.json"


def _replayed(path: Path) -> dict[str, Any]:
    fixture = parse_fixture(load_fixture(path))
    result = replay(fixture.definition, fixture.seed, fixture.params, fixture.command_log)
    return result.to_json()


def test_every_fixture_is_found() -> None:
    assert len(PATHS) >= 55
    assert all(path.suffix == ".json" for path in PATHS)
    assert FIXTURES / STRESS in PATHS


@pytest.mark.parametrize("path", PATHS, ids=lambda path: path.stem)
def test_the_mirror_replays_the_fixture_to_its_expected_result(path: Path) -> None:
    expected = load_fixture(path)["expected_result"]
    actual = _replayed(path)
    difference = first_difference(expected, actual)
    assert difference is None, f"{path.name}: {difference}"


@pytest.mark.parametrize("path", PATHS, ids=lambda path: path.stem)
def test_replaying_is_deterministic(path: Path) -> None:
    fixture = parse_fixture(load_fixture(path))
    times = 10 if path.name == STRESS else 100
    results = {
        str(replay(fixture.definition, fixture.seed, fixture.params, fixture.command_log).to_json())
        for _ in range(times)
    }
    assert len(results) == 1


class TestFirstDifference:
    def test_equal_values(self) -> None:
        assert first_difference({"a": [1, {"b": True}]}, {"a": [1, {"b": True}]}) is None
        assert first_difference([], []) is None

    def test_a_changed_leaf(self) -> None:
        assert first_difference({"a": {"b": 1, "c": 2}}, {"a": {"b": 1, "c": 3}}) == Difference(
            "$.a.c", 2, 3
        )

    def test_keys_are_visited_in_sorted_order(self) -> None:
        expected = {"z": 1, "b": 1, "m": [1]}
        actual = {"z": 2, "b": 2, "m": [2]}
        assert first_difference(expected, actual) == Difference("$.b", 1, 2)

    def test_a_missing_key(self) -> None:
        assert first_difference({"a": 1, "b": 2}, {"a": 1}) == Difference("$.b", 2, MISSING)
        assert first_difference({"a": 1}, {"a": 1, "b": 2}) == Difference("$.b", MISSING, 2)

    def test_a_longer_list(self) -> None:
        assert first_difference({"m": [1, 2]}, {"m": [1, 2, 3]}) == Difference("$.m[2]", MISSING, 3)
        assert first_difference([[0], [1]], [[0], [2]]) == Difference("$[1][0]", 1, 2)

    def test_a_bool_is_not_an_int(self) -> None:
        assert first_difference({"a": 1}, {"a": True}) == Difference("$.a", 1, True)
        assert first_difference({"a": {"b": 1}}, {"a": [1]}) == Difference("$.a", {"b": 1}, [1])

    def test_it_reads_as_one_line(self) -> None:
        text = str(Difference("$.stars", 3, 2))
        assert text == "$.stars: expected 3, got 2"
        assert str(Difference("$.b", 2, MISSING)) == "$.b: expected 2, got (missing)"
