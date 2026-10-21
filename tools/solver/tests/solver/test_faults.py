"""The crafted trips of SC-004 (tests/data/faults), each caught or solved as it should be."""

from __future__ import annotations

import json

import pytest
from wassal_content.models import BoosterId
from wassal_content.validate import document_findings

from tests.paths import FAULTS
from tests.support.scripts import ok, start_trip
from tests.support.solving import fault, solve_trip
from wassal_solver.engine.commands import PickFromTray, SendHand, UseBooster
from wassal_solver.engine.validation import RefusalCode
from wassal_solver.solver import End, Verdict
from wassal_solver.solver.decisions import DecisionKind

PLAYABLE = ["change_impossible", "too_fast", "aid_only", "break_needed", "change_request"]


@pytest.mark.parametrize("name", PLAYABLE)
def test_a_playable_fault_is_valid_content(name: str) -> None:
    document = json.loads((FAULTS / f"{name}.json").read_text(encoding="utf-8"))
    assert [f for f in document_findings("trip", document) if f.severity == "error"] == []


def test_change_that_can_never_be_made_is_not_solved_and_names_the_passenger() -> None:
    result = solve_trip(fault("change_impossible"))
    assert result.verdict is Verdict.NOT_SOLVED
    assert result.end is End.EXHAUSTED
    loss = result.first_loss
    assert loss is not None
    assert (loss.kind, loss.passenger_id, loss.station_id) == ("fight", "p1", "madrasa")
    assert loss.t_ms == 30030
    assert result.best_run is not None
    assert result.timeline[-1].decision == "lost_star"
    assert result.timeline[-1].passenger_id == "p1"


def test_deliveries_closer_than_the_reaction_time_need_a_faster_player() -> None:
    slow = solve_trip(fault("too_fast"))
    assert slow.verdict is Verdict.NOT_SOLVED
    fast = solve_trip(fault("too_fast"), reaction_ms=100)
    assert fast.verdict is Verdict.SOLVED
    assert fast.stars == 3


def test_a_trip_that_needs_an_aid_is_not_solved() -> None:
    definition = fault("aid_only")
    assert solve_trip(definition).verdict is Verdict.NOT_SOLVED
    # With a change bag, the same trip reaches 3 stars.
    trip = start_trip(definition)
    trip.step_to(2079)
    ok(trip, UseBooster(BoosterId.CHANGE_BAG))
    for passenger_id in ("p1", "p2"):
        for _ in range(3):
            ok(trip, PickFromTray(100))
        ok(trip, SendHand(passenger_id))
    trip.step_to(40_000)
    assert trip.result is not None
    assert trip.result.stars == 3


def test_a_trip_that_needs_a_break_is_solved_with_one() -> None:
    result = solve_trip(fault("break_needed"))
    assert result.verdict is Verdict.SOLVED
    assert [entry.decision for entry in result.timeline].count(DecisionKind.REQUEST_BREAK) == 1


def test_a_change_request_either_answer_survives_is_solved() -> None:
    result = solve_trip(fault("change_request"))
    assert result.verdict is Verdict.SOLVED
    assert DecisionKind.ANSWER_CHANGE_REQUEST in [entry.decision for entry in result.timeline]


@pytest.mark.parametrize(
    ("name", "code"),
    [
        ("refused_definition", RefusalCode.STATIONS_OUT_OF_ORDER),
        ("unsupported_type", RefusalCode.UNSUPPORTED_ARCHETYPE),
    ],
)
def test_a_trip_the_mirror_refuses_is_refused_with_its_reason(name: str, code: str) -> None:
    result = solve_trip(fault(name))
    assert result.verdict is Verdict.REFUSED
    assert result.end is End.REFUSED
    assert result.refusals is not None
    assert code in [refusal.code for refusal in result.refusals]
    assert result.run is None
    assert result.best_run is None
    assert result.stars == 0
