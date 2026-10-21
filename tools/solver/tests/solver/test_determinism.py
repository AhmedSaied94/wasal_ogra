"""The same trip, params and settings give byte-identical results (research R9, FR-021)."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest
from wassal_content.canonical import canonical_bytes

from tests.paths import SAMPLE
from tests.support.solving import SAMPLE_IDS, sample_trip, solve_trip

SOLVER = Path(sys.executable).parent / "wassal-solver"


@pytest.mark.parametrize("trip_id", SAMPLE_IDS)
def test_solving_twice_in_one_process_gives_identical_results(trip_id: str) -> None:
    first = canonical_bytes(solve_trip(sample_trip(trip_id)).to_json())
    second = canonical_bytes(solve_trip(sample_trip(trip_id)).to_json())
    assert first == second


def test_two_processes_with_different_hash_seeds_print_identical_bytes() -> None:
    outputs = []
    for seed in ("1", "2"):
        env = {**os.environ, "PYTHONHASHSEED": seed}
        done = subprocess.run(
            [str(SOLVER), "solve", str(SAMPLE), "--json"],
            capture_output=True,
            check=True,
            env=env,
        )
        outputs.append(done.stdout)
    assert outputs[0] == outputs[1]
    assert outputs[0].count(b"\n") == len(SAMPLE_IDS)
