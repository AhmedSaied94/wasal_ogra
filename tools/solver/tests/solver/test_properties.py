"""Property tests of the solver (FR-050): on sample trips with drawn changes, `solve` never
raises or errs, and every run it finds replays to 3 stars."""

from __future__ import annotations

from typing import Any

from hypothesis import given, settings
from hypothesis import strategies as st

from tests.support.builders import definition_of
from tests.support.solving import sample_documents, solve_trip
from wassal_solver.engine.replay import replay
from wassal_solver.solver import End, Verdict
from wassal_solver.tunables import bundled_params

_DENOMINATIONS = ("50", "100", "500", "1000", "2000")


@st.composite
def changed_trips(draw: st.DrawFn) -> dict[str, Any]:
    documents = sample_documents()
    document = documents[draw(st.integers(0, len(documents) - 1))]
    tray = {
        key: count
        for key in _DENOMINATIONS
        if (count := draw(st.integers(0, 6), label=f"tray {key}")) > 0
    }
    document["initial_tray"] = tray
    for passenger in document["passengers"]:
        if "pays_at_seconds" in passenger:
            passenger["pays_at_seconds"] = draw(st.integers(0, 40), label="pays_at")
    if len(document["passengers"]) > 1 and draw(st.booleans(), label="remove one"):
        index = draw(st.integers(0, len(document["passengers"]) - 1), label="removed")
        del document["passengers"][index]
    return document


@settings(max_examples=40)
@given(changed_trips())
def test_solve_never_errs_and_every_found_run_replays_to_3_stars(document: dict[str, Any]) -> None:
    try:
        definition = definition_of(document)
    except ValueError:
        return  # The change made it unreadable: not the solver's input.
    result = solve_trip(definition, effort_budget_steps=20_000)
    assert result.end is not End.INTERNAL_ERROR
    if result.verdict is Verdict.SOLVED:
        assert result.run is not None
        params = bundled_params(definition.line_id)
        assert replay(definition, definition.seed, params, result.run).stars == 3
