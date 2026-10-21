"""«حد معاه فكة؟» (RULES.md §3 step 2.6, §4.9, §14.1), ported from `request_break_test.dart`: a
note goes out and its break-down comes back `trip_break_delay_ms` (1.5 s) later. The
`BreakRequested` and `BreakCompleted` events are checked as the pending break and the tray.
"""

from __future__ import annotations

import pytest

from tests.support.builders import TripBuilder, params_with
from tests.support.scripts import ok, rejects, start_trip
from wassal_solver.engine.commands import RejectionCode, RequestBreak
from wassal_solver.engine.model import PendingBreak


def _trip(tray: dict[int, int], *, max_breaks: int = 2) -> TripBuilder:
    return (
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[500, 100, 100], pays_at=1)
        .tray(tray)
        .rules(max_break_requests=max_breaks)
    )


@pytest.mark.parametrize("note", [1000, 2000, 5000, 10000, 20000])
def test_a_note_comes_back_as_its_table_row_1_5_s_later(note: int) -> None:
    trip = start_trip(_trip({note: 1, 50: 1}).build())
    total = trip.state.tray.total
    ok(trip, RequestBreak(note))
    assert trip.state.pending_breaks == [PendingBreak(denomination=note, completes_at_ms=1500)]
    assert trip.state.tray.total == total - note
    assert trip.state.breaks_used == 1
    trip.step_to(1485)
    assert len(trip.state.pending_breaks) == 1, "not completed yet"
    assert trip.state.tray.total == total - note
    trip.step()
    assert trip.t_ms == 1518
    assert trip.state.tray.total == total
    assert trip.state.tray.count(note) == 0, "the row never holds the note itself"
    assert trip.state.pending_breaks == []


def test_a_10000_note_gives_5000_2000x2_500_100x4_and_50x2() -> None:
    trip = start_trip(_trip({10000: 1}).build())
    ok(trip, RequestBreak(10000))
    trip.step_to(1518)
    assert trip.state.tray.to_json() == {"50": 2, "100": 4, "500": 1, "2000": 2, "5000": 1}


def test_a_note_the_tray_lacks_is_tray_empty() -> None:
    rejects(start_trip(_trip({1000: 1}).build()), RequestBreak(2000), RejectionCode.TRAY_EMPTY)


def test_beyond_max_break_requests_is_break_limit() -> None:
    trip = start_trip(_trip({1000: 3}).build())
    ok(trip, RequestBreak(1000))
    ok(trip, RequestBreak(1000))
    rejects(trip, RequestBreak(1000), RejectionCode.BREAK_LIMIT)


def test_a_note_below_trip_break_min_piasters_is_break_limit() -> None:
    rejects(start_trip(_trip({500: 2}).build()), RequestBreak(500), RejectionCode.BREAK_LIMIT)


def test_a_value_that_is_not_a_denomination_is_bad_argument() -> None:
    rejects(start_trip(_trip({1000: 1}).build()), RequestBreak(1500), RejectionCode.BAD_ARGUMENT)


def test_a_note_with_no_table_row_is_break_limit() -> None:
    trip = start_trip(_trip({500: 2}).build(), params=params_with({"trip_break_min_piasters": 500}))
    rejects(trip, RequestBreak(500), RejectionCode.BREAK_LIMIT)


def test_a_break_completes_while_a_choice_is_open() -> None:
    builder = _trip({1000: 1}).passenger(
        "p2", seat="A_m", dest="gamaa", payment=[1000], pays_at=1, archetype="false_claimer"
    )
    trip = start_trip(builder.build())
    trip.step_to(1023)
    assert list(trip.state.claims) == ["p2"]
    ok(trip, RequestBreak(1000))
    trip.step_to(2541)
    assert trip.state.pending_breaks == []
    assert trip.state.tray.count(50) == 2, "the 1000 came back as its row"
    assert list(trip.state.claims) == ["p2"]
