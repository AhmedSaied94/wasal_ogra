"""Building a solver fixture (contracts/mirror.md §5 and §6), with no I/O."""

from __future__ import annotations

from tests.support.builders import definition_of
from tests.support.solving import sample_documents, solve_trip
from wassal_solver.engine.fixture import FIXTURE_KEYS, build_fixture, check_fixture
from wassal_solver.engine.replay import replay
from wassal_solver.tunables import bundled_params


def test_a_solver_fixture_is_the_five_keys_of_the_trip_its_params_and_its_run() -> None:
    document = sample_documents()[0]
    definition = definition_of(document)
    result = solve_trip(definition)
    assert result.run is not None
    params = bundled_params(definition.line_id)
    fixture = build_fixture(document, params, result.run)
    assert sorted(fixture) == sorted(FIXTURE_KEYS)
    assert fixture["definition"] == document
    assert fixture["seed"] == definition.seed
    assert fixture["params"] == params.to_json()
    assert fixture["command_log"] == [entry.to_json() for entry in result.run]
    assert (
        fixture["expected_result"]
        == replay(definition, definition.seed, params, result.run).to_json()
    )
    assert check_fixture(fixture) is None


def test_the_fixture_keeps_the_definition_as_given() -> None:
    document = sample_documents()[0]
    document["unknown_field"] = "kept"
    definition = definition_of(document)
    result = solve_trip(definition)
    assert result.run is not None
    fixture = build_fixture(document, bundled_params(definition.line_id), result.run)
    assert fixture["definition"]["unknown_field"] == "kept"
    document["unknown_field"] = "changed after"
    assert fixture["definition"]["unknown_field"] == "kept"
