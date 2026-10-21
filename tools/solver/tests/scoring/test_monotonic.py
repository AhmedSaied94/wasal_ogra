"""The score is monotonic, integral and repeatable (Hypothesis, FR-025, FR-026)."""

from __future__ import annotations

from hypothesis import given
from hypothesis import strategies as st

from wassal_solver.scoring.difficulty import score_of
from wassal_solver.settings import SCORE_INPUTS, ScoreTable, ScoreTerm

terms = st.builds(
    ScoreTerm,
    free=st.integers(0, 20),
    per=st.integers(0, 50),
    unit=st.integers(1, 5000),
    cap=st.integers(0, 100),
)
tables = st.builds(
    ScoreTable,
    slack_ref_ms=st.integers(0, 60_000),
    terms=st.tuples(*(terms for _ in SCORE_INPUTS)).map(
        lambda found: tuple(zip(SCORE_INPUTS, found, strict=True))
    ),
)
values = st.fixed_dictionaries({name: st.integers(0, 100_000) for name in SCORE_INPUTS})


@given(tables, values, st.sampled_from(SCORE_INPUTS), st.integers(1, 100_000))
def test_raising_one_input_never_lowers_the_score(
    table: ScoreTable, found: dict[str, int], name: str, more: int
) -> None:
    raised = {**found, name: found[name] + more}
    assert score_of(raised, table).value >= score_of(found, table).value


@given(tables, values)
def test_the_score_is_an_int_from_0_to_100_and_repeatable(
    table: ScoreTable, found: dict[str, int]
) -> None:
    score = score_of(found, table)
    assert type(score.value) is int
    assert 0 <= score.value <= 100
    assert score_of(dict(found), table) == score
    for _, points in score.inputs:
        assert type(points.points) is int
        assert points.points >= 0
