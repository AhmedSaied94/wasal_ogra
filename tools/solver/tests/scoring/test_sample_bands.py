"""Every sample trip is solved and scores inside its line's band (FR-042, SC-003)."""

from __future__ import annotations

import json

import pytest

from tests.paths import SAMPLE
from tests.support.solving import SAMPLE_IDS, sample_trip, solve_trip
from wassal_solver.scoring.difficulty import Band, in_band


def band_of(line_id: str) -> Band:
    line = json.loads((SAMPLE / "lines" / f"{line_id}.json").read_text(encoding="utf-8"))
    return Band(line["difficulty_band"]["min"], line["difficulty_band"]["max"])


def test_the_sample_bands_are_the_ones_the_spec_names() -> None:
    assert band_of("line_hay") == Band(0, 30)
    assert band_of("line_gamaa") == Band(20, 55)


@pytest.mark.parametrize("trip_id", SAMPLE_IDS)
def test_a_sample_trip_scores_inside_its_band(trip_id: str) -> None:
    definition = sample_trip(trip_id)
    result = solve_trip(definition)
    assert result.solved
    assert result.score is not None
    assert in_band(result.score.value, band_of(definition.line_id)), result.score
