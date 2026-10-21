"""Time and memory budgets (spec SC-008, FR-047, research R14).

The times are wall-clock times on the machine that runs the tests, so they are generous bounds, not
measurements: SC-008's figures are for the CI runner, and a slower machine only gets closer to
them.
"""

from __future__ import annotations

import dataclasses
import time
import tracemalloc

from tests.paths import FIXTURES
from tests.support.solving import sample_trip
from wassal_solver.engine.fixture import parse_fixture
from wassal_solver.engine.params import TripParams
from wassal_solver.engine.replay import replay
from wassal_solver.fixture_files import load_fixture
from wassal_solver.settings import load_settings
from wassal_solver.solver import End, solve
from wassal_solver.tunables import bundled_params

NS_PER_MS = 1_000_000
LONGEST_TRIP_MS = 5_000
TYPICAL_TRIP_MS = 500
SOLVE_PEAK_BYTES = 64 * 1024 * 1024
TYPICAL = "solver__line_gamaa_02.json"
"""The longest sample trip, 100 s: longer than SC-008's typical 90-second trip."""
SLOW_HOP_MS = 40_000
"""A hop that leaves `line_gamaa.02` unsolvable, but only late in every branch, so the search
spends its whole budget: `change_impossible` is now proven in a few thousand steps."""
UNCAPPED_SECONDS = 3600
"""tracemalloc makes the search several times slower, and the safety cap is a wall-time guard that
isn't what this test measures."""


def _replay_ms(name: str) -> int:
    fixture = parse_fixture(load_fixture(FIXTURES / name))
    started = time.perf_counter_ns()
    replay(fixture.definition, fixture.seed, fixture.params, fixture.command_log)
    return (time.perf_counter_ns() - started) // NS_PER_MS


def test_the_longest_trip_replays_in_under_5_s() -> None:
    assert _replay_ms("stress__longest_trip.json") < LONGEST_TRIP_MS


def test_a_typical_trip_replays_in_under_half_a_second() -> None:
    fixture = parse_fixture(load_fixture(FIXTURES / TYPICAL))
    assert fixture.definition.stations[-1].at_seconds >= 90
    assert _replay_ms(TYPICAL) < TYPICAL_TRIP_MS


def test_a_full_budget_solve_stays_under_64_mb() -> None:
    definition = sample_trip("line_gamaa.02")
    params = TripParams.from_json(
        {**bundled_params(definition.line_id).to_json(), "trip_hop_ms": SLOW_HOP_MS}
    )
    settings = dataclasses.replace(load_settings(), safety_cap_seconds=UNCAPPED_SECONDS)
    tracemalloc.start()
    try:
        result = solve(definition, params, settings)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    assert result.end is End.BUDGET_SPENT
    assert result.effort_steps == settings.effort_budget_steps
    assert peak < SOLVE_PEAK_BYTES
