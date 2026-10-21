"""Random runs replay to their live result (spec FR-050), as the Dart fuzz test checks: random
logs over the five sample trips, each command drawn among those the trip could accept.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from hypothesis import given, settings

from tests.engine.random_runs import SAMPLES, SEEDS, run, sample
from tests.support.builders import default_params
from wassal_solver.engine import command_log_hash
from wassal_solver.engine.commands import decode_log
from wassal_solver.engine.replay import replay
from wassal_solver.engine.rules.command_handlers import COMMAND_CAP


def test_the_five_sample_trips_are_found() -> None:
    assert [path.name for path in SAMPLES] == [
        "line_gamaa.01.json",
        "line_gamaa.02.json",
        "line_hay.01.json",
        "line_hay.02.json",
        "line_hay.03.json",
    ]


@pytest.mark.parametrize("path", SAMPLES, ids=lambda path: path.stem)
@settings(max_examples=10)
@given(seed=SEEDS)
def test_a_random_run_replays_twice_to_its_live_result(path: Path, seed: int) -> None:
    definition = sample(path)
    params = default_params(definition.line_id)
    trip = run(definition, params, seed)
    live = trip.result
    assert live is not None, "a run ends with a result"
    log = trip.command_log
    assert len(log) <= COMMAND_CAP + 1
    first = replay(definition, trip.seed, params, log)
    second = replay(definition, trip.seed, params, log)
    assert first == second == live
    assert first.to_json() == live.to_json()
    assert first.command_log_hash == command_log_hash(log)
    wire = json.loads(json.dumps([entry.to_json() for entry in log]))
    assert replay(definition, trip.seed, params, decode_log(wire)) == live
