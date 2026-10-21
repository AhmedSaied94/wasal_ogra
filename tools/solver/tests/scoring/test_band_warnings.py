"""A solvable trip outside its line's band (SC-004, US3 scenario 3)."""

from __future__ import annotations

from tests.support.solving import fault, solve_trip
from wassal_solver.scoring.difficulty import Band, in_band

HAY = Band(0, 30)
GAMAA = Band(20, 55)


def test_a_hay_trip_that_is_too_hard_scores_above_its_band() -> None:
    result = solve_trip(fault("hay_too_hard"))
    assert result.solved
    assert result.score is not None
    assert not in_band(result.score.value, HAY)
    assert result.score.value > HAY.max


def test_a_gamaa_trip_that_is_too_easy_scores_below_its_band() -> None:
    result = solve_trip(fault("gamaa_too_easy"))
    assert result.solved
    assert result.score is not None
    assert not in_band(result.score.value, GAMAA)
    assert result.score.value < GAMAA.min
