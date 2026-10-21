"""The search and its ends (contracts/solver.md §3 and §4, research R8)."""

from __future__ import annotations

import logging
from dataclasses import replace
from typing import Any

import pytest

import wassal_solver.solver as solver_module
from tests.support.solving import (
    SAMPLE_IDS,
    fault,
    sample_trip,
    settings_with,
    solve_trip,
)
from wassal_solver.engine.commands import COMMAND_NAMES
from wassal_solver.engine.replay import replay
from wassal_solver.engine.trip import Trip, start
from wassal_solver.solver import End, Verdict
from wassal_solver.solver.search import Run, _Search, run_search
from wassal_solver.solver.timeline import Loss
from wassal_solver.tunables import bundled_params

PLAYER_COMMANDS = {
    "PickFromTray",
    "ReturnHand",
    "SendHand",
    "Tap",
    "ResolveClaim",
    "ResolveDispute",
    "ResolveChangeRequest",
    "RequestBreak",
    "CollectDropped",
}


def names(log: Any) -> set[str]:
    return {entry.command.name for entry in log}


@pytest.mark.parametrize("trip_id", SAMPLE_IDS)
def test_every_sample_trip_is_solved_and_its_run_replays_to_3_stars(trip_id: str) -> None:
    definition = sample_trip(trip_id)
    result = solve_trip(definition)
    assert (result.verdict, result.end, result.stars) == (Verdict.SOLVED, End.FOUND, 3)
    assert result.run is not None
    assert result.best_run is None
    assert result.first_loss is None
    replayed = replay(definition, definition.seed, bundled_params(definition.line_id), result.run)
    assert replayed.stars == 3
    assert result.run_hash == replayed.command_log_hash
    assert names(result.run) <= PLAYER_COMMANDS
    assert len(result.timeline) > 0


def test_the_player_commands_are_nine_of_the_thirteen() -> None:
    assert set(COMMAND_NAMES) > PLAYER_COMMANDS
    assert len(PLAYER_COMMANDS) == 9


def test_a_tiny_unsolvable_trip_is_exhausted() -> None:
    result = solve_trip(fault("change_impossible"))
    assert (result.verdict, result.end) == (Verdict.NOT_SOLVED, End.EXHAUSTED)
    assert result.best_run is not None
    assert names(result.best_run) <= PLAYER_COMMANDS
    assert result.stars == 1


def test_a_spent_budget_is_not_solved_and_shows_the_best_run() -> None:
    result = solve_trip(sample_trip("line_hay.01"), effort_budget_steps=50)
    assert (result.verdict, result.end) == (Verdict.NOT_SOLVED, End.BUDGET_SPENT)
    assert result.best_run is not None
    assert result.run is None
    assert result.effort_steps >= 50


def test_the_safety_cap_also_stops_the_play_on_after_the_budget(
    caplog: pytest.LogCaptureFixture,
) -> None:
    # The budget runs out before any branch ends, so the deepest node is played on, past the
    # 1024th step, where the cap is checked.
    result = solve_trip(sample_trip("line_hay.01"), effort_budget_steps=50, safety_cap_seconds=0)
    assert result.end is End.SAFETY_CAP
    assert result.verdict is Verdict.NOT_SOLVED
    assert "internal error" not in caplog.text


def test_the_safety_cap_stops_the_search() -> None:
    result = solve_trip(sample_trip("line_hay.01"), safety_cap_seconds=0)
    assert (result.verdict, result.end) == (Verdict.NOT_SOLVED, End.SAFETY_CAP)
    assert result.run is None


def test_a_refused_trip_is_refused() -> None:
    result = solve_trip(fault("refused_definition"))
    assert (result.verdict, result.end, result.effort_steps) == (Verdict.REFUSED, End.REFUSED, 0)


def test_an_exception_in_the_search_is_an_internal_error_and_is_logged(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    def broken(trip: Trip, settings: Any) -> Any:
        raise RuntimeError("the mirror broke")

    monkeypatch.setattr(solver_module, "run_search", broken)
    with caplog.at_level(logging.ERROR, logger="wassal_solver.solver"):
        result = solve_trip(sample_trip("line_hay.01"))
    assert (result.verdict, result.end) == (Verdict.NOT_SOLVED, End.INTERNAL_ERROR)
    assert "line_hay.01" in caplog.text
    assert "the mirror broke" in caplog.text


def test_a_run_that_does_not_confirm_is_an_internal_error_never_solved(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    real = replay

    def two_stars(*args: Any) -> Any:
        return replace(real(*args), stars=2)

    monkeypatch.setattr(solver_module, "replay", two_stars)
    with caplog.at_level(logging.ERROR, logger="wassal_solver.solver"):
        result = solve_trip(sample_trip("line_hay.01"))
    assert (result.verdict, result.end) == (Verdict.NOT_SOLVED, End.INTERNAL_ERROR)
    assert result.run is None
    assert "did not replay" in caplog.text


def test_the_visited_table_never_holds_more_than_its_cap() -> None:
    definition = fault("aid_only")
    for cap in (0, 1, 5):
        engine = _Search(settings_with(transposition_cap=cap))
        engine.run(start(definition, bundled_params(definition.line_id), definition.seed))
        assert len(engine.visited) <= cap
    engine = _Search(settings_with())
    engine.run(start(definition, bundled_params(definition.line_id), definition.seed))
    assert len(engine.visited) > 5


def test_the_best_run_has_the_most_stars_then_the_latest_first_loss() -> None:
    def run(stars: int, t_ms: int | None) -> Run:
        loss = None if t_ms is None else Loss("mistake", t_ms, None, None, "")
        return Run(trip=None, taken=(), loss=loss, stars=stars)  # type: ignore[arg-type]

    assert run(2, 1000).rank > run(1, 50_000).rank
    assert run(2, 2000).rank > run(2, 1000).rank
    assert run(3, None).rank > run(2, 90_000).rank


def test_effort_counts_the_mirror_steps(monkeypatch: pytest.MonkeyPatch) -> None:
    counted = 0
    step = Trip.step

    def counting(self: Trip) -> None:
        nonlocal counted
        counted += 1
        step(self)

    monkeypatch.setattr(Trip, "step", counting)
    definition = fault("aid_only")
    outcome = run_search(
        start(definition, bundled_params(definition.line_id), definition.seed), settings_with()
    )
    assert outcome.effort_steps == counted
    assert counted > 0


def test_solve_never_raises_on_a_definition_that_breaks_the_search(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def broken(*args: Any) -> Any:
        raise ValueError("bad state")

    monkeypatch.setattr("wassal_solver.solver.search.possible_decisions", broken)
    result = solve_trip(sample_trip("line_gamaa.01"))
    assert result.end is End.INTERNAL_ERROR
