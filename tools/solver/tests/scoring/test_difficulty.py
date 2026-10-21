"""The difficulty score's inputs, points and shape (contracts/solver.md §5, research R11)."""

from __future__ import annotations

from wassal_content.models import TripDefinition

from tests.support.builders import TripBuilder, default_params
from tests.support.solving import fault, solve_trip
from wassal_solver.engine.commands import (
    Command,
    LoggedCommand,
    PickFromTray,
    RequestBreak,
    SendHand,
    Tap,
)
from wassal_solver.scoring.difficulty import Band, in_band, measure, points, score_of, score_trip
from wassal_solver.settings import SCORE_INPUTS, ScoreTerm, load_settings

SLACK_REF = load_settings().score.slack_ref_ms


def log(*entries: tuple[int, Command]) -> list[LoggedCommand]:
    return [LoggedCommand(t, command) for t, command in entries]


def inputs(definition: TripDefinition, run: list[LoggedCommand]) -> dict[str, int]:
    return measure(definition, run, default_params(definition.line_id), SLACK_REF)


def give(t: int, passenger_id: str, *pieces: int) -> list[tuple[int, Command]]:
    """Picks `pieces` a tap apart from `t`, then sends them."""
    entries: list[tuple[int, Command]] = [
        (t + 198 * i, PickFromTray(piece)) for i, piece in enumerate(pieces)
    ]
    return [*entries, (t + 198 * len(pieces), SendHand(passenger_id))]


def two_payers() -> TripDefinition:
    """p1 and p2 both pay 1000 for a 700 fare at 0 s and get off at gamaa, 30 s."""
    return (
        TripBuilder()
        .station("gamaa", 30)
        .tray({100: 8, 50: 4, 500: 2})
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=0)
        .passenger("p2", seat="A_l", dest="gamaa", payment=[1000], pays_at=0)
        .build()
    )


def test_owed_at_once_is_the_most_passengers_owed_at_the_same_step() -> None:
    assert inputs(two_payers(), [])["owed_at_once"] == 2
    run = log(*give(660, "p1", 100, 100, 100))
    assert inputs(two_payers(), run)["owed_at_once"] == 2
    single = (
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=0)
        .passenger("p2", seat="A_l", dest="gamaa", payment=[1000], pays_at=20)
        .build()
    )
    assert inputs(single, log(*give(660, "p1", 100, 100, 100)))["owed_at_once"] == 1


def test_change_pieces_counts_every_piece_given_as_change() -> None:
    run = log(*give(660, "p1", 100, 100, 100), *give(2000, "p2", 100, 100, 50, 50))
    assert inputs(two_payers(), run)["change_pieces"] == 7


def test_blockers_are_sleepers_and_headphones_on_a_payers_chain_to_the_driver() -> None:
    trip = (
        TripBuilder()
        .station("gamaa", 30)
        .station("souq", 60)
        .passenger("p1", seat="C_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
        .passenger("p2", seat="B_r", dest="souq", payment=[500, 100, 100], archetype="sleeper")
        .passenger("p3", seat="A_r", dest="souq", payment=[500, 100, 100], archetype="headphones")
        .passenger("p4", seat="A_l", dest="souq", payment=[500, 100, 100], archetype="sleeper")
        .build()
    )
    # p1's chain to the driver passes p2 and p3; p4 is in another column.
    run = log((0, Tap("p2")), (1100, Tap("p3")), (1298, Tap("p3")))
    assert inputs(trip, run)["blockers"] == 2


def test_breaks_counts_the_break_requests() -> None:
    definition = fault("break_needed")
    result = solve_trip(definition)
    assert result.run is not None
    assert inputs(definition, list(result.run))["breaks"] == 1
    assert sum(isinstance(entry.command, RequestBreak) for entry in result.run) == 1


def test_tightness_is_the_reference_slack_minus_the_least_slack() -> None:
    assert inputs(two_payers(), [])["tightness_ms"] == 0
    # The last change arrives at t, and both get off at gamaa (30030): the least slack is
    # 30030 - t.
    run = log(*give(660, "p1", 100, 100, 100), *give(25_000, "p2", 100, 100, 100))
    found = inputs(two_payers(), run)
    assert found["tightness_ms"] > 0
    late = 30030 - (SLACK_REF - found["tightness_ms"])
    assert 25_000 < late < 30030
    early = log(*give(660, "p1", 100, 100, 100), *give(2000, "p2", 100, 100, 100))
    assert inputs(two_payers(), early)["tightness_ms"] == 0


def test_variety_counts_distinct_archetypes_and_events() -> None:
    trip = (
        TripBuilder()
        .station("gamaa", 30)
        .station("souq", 60)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=0)
        .passenger("p2", seat="A_l", dest="souq", payment=[1000], archetype="sleeper")
        .passenger("p3", seat="A_m", dest="souq", payment=[1000], archetype="sleeper")
        .event("traffic", 10, seconds=5)
        .event("traffic", 20, seconds=5)
        .event("bump", 25)
        .build()
    )
    assert inputs(trip, [])["variety"] == 4


def test_points_follow_the_table() -> None:
    term = ScoreTerm(free=1, per=8, unit=1, cap=24)
    assert [points(term, v) for v in (0, 1, 2, 3, 4, 9)] == [0, 0, 8, 16, 24, 24]
    tight = ScoreTerm(free=0, per=2, unit=1000, cap=20)
    assert [points(tight, v) for v in (0, 499, 999, 1000, 2500, 99_000)] == [0, 0, 1, 2, 5, 20]


def test_the_score_is_the_capped_sum_of_the_points() -> None:
    table = load_settings().score
    values = {
        "owed_at_once": 3,
        "change_pieces": 8,
        "blockers": 1,
        "breaks": 0,
        "tightness_ms": 2100,
        "variety": 4,
    }
    score = score_of(values, table)
    assert [score.input(name).points for name in SCORE_INPUTS] == [16, 6, 6, 0, 4, 12]
    assert score.value == 44
    huge = score_of(dict.fromkeys(SCORE_INPUTS, 10**6), table)
    assert huge.value == 100


def test_the_score_json_has_every_input_and_no_band() -> None:
    result = solve_trip(fault("hay_too_hard"))
    assert result.score is not None
    document = result.score.to_json()
    assert set(document) == {"value", "inputs"}
    assert list(document["inputs"]) == list(SCORE_INPUTS)  # type: ignore[call-overload]
    for entry in document["inputs"].values():  # type: ignore[attr-defined]
        assert set(entry) == {"value", "points"}
    assert "band" not in str(document)


def test_in_band_includes_both_ends() -> None:
    band = Band(20, 55)
    assert [in_band(v, band) for v in (19, 20, 37, 55, 56)] == [False, True, True, True, False]


def test_a_trip_with_nothing_to_do_scores_near_zero() -> None:
    definition = fault("gamaa_too_easy")
    result = solve_trip(definition)
    assert result.score is not None
    assert result.score.value <= 5
    assert result.run is not None
    assert score_trip(definition, result.run, default_params("line_gamaa"), load_settings()) == (
        result.score
    )


def test_a_result_that_is_not_solved_or_is_refused_has_no_score() -> None:
    assert solve_trip(fault("change_impossible")).score is None
    assert solve_trip(fault("unsupported_type")).score is None
    assert solve_trip(fault("too_fast")).score is None


def test_the_most_contributing_inputs_come_first() -> None:
    result = solve_trip(fault("hay_too_hard"))
    assert result.score is not None
    assert result.score.most() == ("owed_at_once", "change_pieces")
