"""Every parity fixture's definition is content the engine can play (specs/004 T058).

A fixture is named as `fixtures/parity/README.md` says and has exactly its five keys, with the
right types. Its `definition` passes, on its own like a daily challenge, the trip schema, the
trip's own references (V-T1, V-T4 to V-T6) and the engine's rules (V-T8, V-T9). The checks
themselves are also covered on temporary fixtures below.
"""

import copy
import json
import re
from pathlib import Path
from typing import Any

import pytest

from tests.paths import EXAMPLES, PARITY
from wassal_content.loader import load_json_file
from wassal_content.schemas import SchemaSet
from wassal_content.validate import document_findings

FIXTURE_KEYS = frozenset({"definition", "seed", "params", "command_log", "expected_result"})
FIXTURES = sorted(PARITY.glob("*.json"))
FIXTURE_NAME = re.compile(
    r"^(core|archetype|event|command|booster|ending|sample|solver|stress)__[a-z0-9_]+\.json$"
)
# The JSON type of each key, as Python's json module reads it.
FIXTURE_TYPES: dict[str, type] = {
    "definition": dict,
    "seed": int,
    "params": dict,
    "command_log": list,
    "expected_result": dict,
}
TRIP: dict[str, Any] = load_json_file(
    EXAMPLES / "sample" / "trips" / "line_hay" / "line_hay.01.json"
)


def fixture_problems(path: Path, schema_set: SchemaSet) -> list[str]:
    """Everything wrong with one fixture file, one line each."""
    fixture = load_json_file(path)
    if not isinstance(fixture, dict):
        return ["a fixture is a JSON object"]
    problems = [f"unexpected key {key!r}" for key in sorted(set(fixture) - FIXTURE_KEYS)]
    problems += [f"missing key {key!r}" for key in sorted(FIXTURE_KEYS - set(fixture))]
    problems += [
        f"{key} is not a JSON {kind.__name__}"
        for key, kind in FIXTURE_TYPES.items()
        if key in fixture and (not isinstance(fixture[key], kind) or isinstance(fixture[key], bool))
    ]
    if "definition" in fixture:
        problems += [
            f"definition {finding.path} [{finding.code}]: {finding.message}"
            for finding in document_findings("trip", fixture["definition"], schema_set=schema_set)
        ]
    return problems


def test_the_parity_fixtures_are_there_and_named_by_area() -> None:
    assert FIXTURES, f"no fixtures in {PARITY}"
    assert [path.name for path in FIXTURES if not FIXTURE_NAME.match(path.name)] == []


@pytest.mark.parametrize("path", FIXTURES, ids=lambda path: path.name)
def test_every_parity_fixture_definition_is_playable_content(
    path: Path, schema_set: SchemaSet
) -> None:
    assert fixture_problems(path, schema_set) == []


def _fixture(tmp_path: Path, **changes: Any) -> Path:
    fixture: dict[str, Any] = {
        "definition": copy.deepcopy(TRIP),
        "seed": TRIP["seed"],
        "params": {},
        "command_log": [[330, "Tap", "p1"]],
        "expected_result": {},
    }
    fixture.update(changes)
    path = tmp_path / "core__case.json"
    path.write_text(json.dumps(fixture, ensure_ascii=False, indent=2, sort_keys=True))
    return path


def test_a_well_formed_fixture_has_no_problem(tmp_path: Path, schema_set: SchemaSet) -> None:
    assert fixture_problems(_fixture(tmp_path), schema_set) == []


def test_a_sixth_key_and_an_unplayable_event_are_problems(
    tmp_path: Path, schema_set: SchemaSet
) -> None:
    definition = copy.deepcopy(TRIP)
    definition["events"] = [{"event_id": "bump", "at_seconds": 20, "seconds": 5}]
    path = _fixture(tmp_path, definition=definition, notes="six keys")
    assert fixture_problems(path, schema_set) == [
        "unexpected key 'notes'",
        "definition $.events[0].seconds [V-T8]: bump doesn't take seconds",
    ]


def test_a_missing_key_and_a_schema_error_are_problems(
    tmp_path: Path, schema_set: SchemaSet
) -> None:
    path = _fixture(tmp_path)
    fixture = json.loads(path.read_text())
    del fixture["expected_result"]
    fixture["definition"]["archetype_count"] = 1
    path.write_text(json.dumps(fixture))
    assert fixture_problems(path, schema_set) == [
        "missing key 'expected_result'",
        "definition $.archetype_count [V-SC]: 'archetype_count' is not an allowed property",
    ]


def test_a_fixture_that_is_not_an_object_is_a_problem(
    tmp_path: Path, schema_set: SchemaSet
) -> None:
    path = tmp_path / "core__list.json"
    path.write_text("[]")
    assert fixture_problems(path, schema_set) == ["a fixture is a JSON object"]


def test_a_trip_reference_error_is_a_problem(tmp_path: Path, schema_set: SchemaSet) -> None:
    definition = copy.deepcopy(TRIP)
    definition["events"] = [{"event_id": "drop_me_here", "at_seconds": 20, "passenger_ids": ["p9"]}]
    definition["passengers"][0]["dest_station_id"] = "nowhere"
    path = _fixture(tmp_path, definition=definition)
    assert fixture_problems(path, schema_set) == [
        "definition $.events[0].passenger_ids[0] [V-T6]: no passenger 'p9' in this trip",
        "definition $.passengers[0].dest_station_id [V-T4]: "
        "'nowhere' is not a station of this trip",
    ]


def test_keys_of_the_wrong_type_are_problems(tmp_path: Path, schema_set: SchemaSet) -> None:
    path = _fixture(tmp_path, seed=True, params=[], expected_result=None)
    assert fixture_problems(path, schema_set) == [
        "seed is not a JSON int",
        "params is not a JSON dict",
        "expected_result is not a JSON dict",
    ]
