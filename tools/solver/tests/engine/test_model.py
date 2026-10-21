"""The mirror's state (data-model.md "Mirror state"): slots dataclasses, an independent clone, and
a TripResult with exactly M01's keys.
"""

from __future__ import annotations

import dataclasses
from typing import Any

import pytest
from wassal_content.models import BoosterId

from tests.support.builders import TripBuilder
from tests.support.scripts import hold_token, ok, open_claim, start_trip
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import Abandon, PickFromTray
from wassal_solver.engine.model import (
    DRIVER,
    ChangeRequest,
    Claim,
    Counters,
    Dispute,
    LastSend,
    Mistake,
    MistakeKind,
    MoneyToken,
    PassengerState,
    PendingBreak,
    RepCause,
    StarFlags,
    StationState,
    TokenKind,
    TripResult,
    TripState,
)
from wassal_solver.engine.money import Pieces

# M01 data-model "TripResult", in its order.
RESULT_KEYS = [
    "trip_id",
    "rev",
    "outcome",
    "stars",
    "star_flags",
    "fares_collected_piasters",
    "overpaid_piasters",
    "tips_piasters",
    "earnings_jenehat",
    "fights",
    "lost_fares",
    "missed_stops",
    "impatient",
    "caught_liars",
    "mistakes",
    "reputation",
    "reputation_lost",
    "duration_ms",
    "boosters_used",
    "revived",
    "command_log_hash",
]


def _trip() -> Trip:
    definition = (
        TripBuilder()
        .station("kobri", 30)
        .station("gamaa", 60)
        .passenger("p1", seat="A_r", dest="kobri", payment=[1000])
        .passenger("p2", seat="B_m", dest="gamaa", payment=[500, 100, 100])
        .build()
    )
    trip = start_trip(definition)
    trip.step_to(330)
    ok(trip, PickFromTray(100))
    hold_token(trip, "p2", kind=TokenKind.FARE, pieces={500: 1}, owner="p2", target=DRIVER)
    open_claim(trip, "p1", truthful=False)
    trip.state.disputes[0] = Dispute(a="p1", b="p2")
    trip.state.change_requests["p2"] = ChangeRequest(note_piasters=5000)
    trip.state.pending_breaks.append(PendingBreak(denomination=1000, completes_at_ms=2000))
    trip.state.mistakes.append(
        Mistake(passenger_id="p1", kind=MistakeKind.OVER, amount_piasters=50)
    )
    trip.state.reputation_lost[RepCause.FIGHT] = 30
    trip.state.old_fare_payers.add("p2")
    return trip


@pytest.mark.parametrize(
    "cls", [TripState, PassengerState, MoneyToken, StationState, Counters, TripResult, StarFlags]
)
def test_every_state_class_is_a_slots_dataclass(cls: type) -> None:
    assert dataclasses.is_dataclass(cls)
    assert "__slots__" in cls.__dict__


@pytest.mark.parametrize(
    "cls", [Claim, Dispute, ChangeRequest, PendingBreak, LastSend, Mistake, Pieces]
)
def test_small_records_are_frozen_slots_dataclasses(cls: type) -> None:
    assert dataclasses.is_dataclass(cls)
    assert "__slots__" in cls.__dict__
    params = cls.__dataclass_params__  # type: ignore[attr-defined]
    assert params.frozen


def test_a_clone_equals_the_original() -> None:
    trip = _trip()
    copy = trip.clone()
    assert copy.state == trip.state
    assert copy.state.to_json() == trip.state.to_json()
    assert copy.command_log == trip.command_log
    assert copy.t_ms == trip.t_ms


def test_changing_the_clone_leaves_the_original_unchanged() -> None:
    trip = _trip()
    before = trip.state.to_json()
    copy = trip.clone()
    state = copy.state
    state.tray = state.tray.plus_one(50)
    state.hand = Pieces.of({1000: 1})
    state.passengers[0].balance = 999
    state.passengers[1].fare_sent = True
    state.tokens[1].holder = DRIVER
    state.tokens[1].hops_done = 3
    state.schedule[0].at_ms += 1000
    state.schedule[1].warned = True
    del state.claims["p1"]
    state.disputes.clear()
    state.change_requests["p1"] = ChangeRequest(note_piasters=1000)
    state.pending_breaks.clear()
    state.mistakes.clear()
    state.reputation_lost[RepCause.FIGHT] = 60
    state.old_fare_payers.clear()
    state.counters.fights += 1
    state.counters.tips_piasters += 200
    state.events_fired.append(True)
    state.boosters_used.append(BoosterId.WAKE_ALL)
    state.reputation -= 10
    ok(copy, Abandon())
    assert trip.state.to_json() == before
    assert len(trip.command_log) == 1
    assert trip.result is None


def test_trip_result_has_exactly_the_m01_keys() -> None:
    trip = _trip()
    ok(trip, Abandon())
    assert trip.result is not None
    result: dict[str, Any] = trip.result.to_json()
    assert list(result) == RESULT_KEYS
    assert list(result["star_flags"]) == ["reached", "no_fights", "no_mistakes"]
    assert result["mistakes"] == [{"passenger_id": "p1", "kind": "over", "amount_piasters": 50}]
    assert result["reputation_lost"] == {"fight": 30}
    assert result["outcome"] == "abandoned"
    assert len(result["command_log_hash"]) == 64


def test_reputation_lost_is_in_rep_cause_order() -> None:
    trip = _trip()
    trip.state.reputation_lost.clear()
    trip.state.reputation_lost[RepCause.IMPATIENT] = 5
    trip.state.reputation_lost[RepCause.FIGHT] = 30
    ok(trip, Abandon())
    assert trip.result is not None
    lost: dict[str, int] = trip.result.to_json()["reputation_lost"]  # type: ignore[assignment]
    assert list(lost) == ["fight", "impatient"]
    assert [cause.value for cause in RepCause] == [
        "fight",
        "false_accusation",
        "missed_stop",
        "short_change",
        "impatient",
        "change_request_declined",
        "exact_change",
        "liar_caught",
        "revive",
    ]
