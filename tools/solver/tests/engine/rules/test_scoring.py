"""The result (RULES.md §11), ported from `test/rules/scoring_test.dart`: stars, earnings,
duration, reputation and the fingerprint.
"""

from __future__ import annotations

import re

from tests.support.builders import TripBuilder
from tests.support.scripts import ok, set_reputation, start_trip, step_to_seconds
from wassal_solver.engine import Trip, command_log_hash
from wassal_solver.engine.commands import PickFromTray, ReturnHand
from wassal_solver.engine.model import Mistake, MistakeKind, TripOutcome, TripResult, TripStatus


def trip(*, max_earnings: int = 100) -> Trip:
    """One station at 1 s and a passenger who never pays: no fares, no fights, no mistakes unless
    a test adds them."""
    return start_trip(
        TripBuilder()
        .max_earnings(max_earnings)
        .station("kobri", 1)
        .passenger("p1", seat="A_r", dest="kobri", payment=[1000])
        .build()
    )


def finish(run: Trip) -> TripResult:
    step_to_seconds(run, 2)
    assert run.status is TripStatus.FINISHED
    assert run.result is not None
    return run.result


class TestStars:
    def test_3_with_no_fights_and_no_mistakes(self) -> None:
        result = finish(trip())
        assert result.stars == 3
        assert result.star_flags.to_json() == {
            "reached": True,
            "no_fights": True,
            "no_mistakes": True,
        }

    def test_2_with_a_mistake_and_no_fights(self) -> None:
        run = trip()
        run.state.mistakes.append(Mistake("p1", MistakeKind.OVER, 50))
        result = finish(run)
        assert result.stars == 2
        assert not result.star_flags.no_mistakes
        (mistake,) = result.mistakes
        assert mistake.amount_piasters == 50

    def test_1_with_a_fight_mistakes_or_not(self) -> None:
        run = trip()
        run.state.counters.fights = 1
        assert finish(run).stars == 1
        both = trip()
        both.state.counters.fights = 1
        both.state.mistakes.append(Mistake("p1", MistakeKind.UNRETURNED, 50))
        result = finish(both)
        assert result.stars == 1
        assert result.star_flags.to_json() == {
            "reached": True,
            "no_fights": False,
            "no_mistakes": False,
        }


class TestEarnings:
    def test_whole_pounds_rounded_down_2549_piasters_is_25_jenehat(self) -> None:
        run = trip()
        run.state.counters.tips_piasters = 2549
        assert finish(run).earnings_jenehat == 25

    def test_fares_minus_overpaid_plus_tips_never_below_0(self) -> None:
        run = trip()
        run.state.counters.overpaid_piasters = 500
        run.state.counters.tips_piasters = 200
        result = finish(run)
        assert result.earnings_jenehat == 0
        assert result.overpaid_piasters == 500
        assert result.tips_piasters == 200

    def test_capped_at_max_earnings_jenehat(self) -> None:
        run = trip(max_earnings=10)
        run.state.counters.tips_piasters = 5000
        assert finish(run).earnings_jenehat == 10


def test_duration_reputation_and_counters() -> None:
    run = trip()
    set_reputation(run, 77)
    result = finish(run)
    assert result.duration_ms == 1023
    assert result.reputation == 77
    assert result.lost_fares == 1
    assert result.outcome is TripOutcome.FINISHED
    assert result.trip_id == "line_gamaa.01"
    assert result.rev == 1
    assert not result.revived
    assert result.boosters_used == ()


def test_the_fingerprint_is_the_command_log_hash() -> None:
    run = trip()
    ok(run, PickFromTray(100))
    ok(run, ReturnHand())
    result = finish(run)
    assert re.fullmatch(r"[0-9a-f]{64}", result.command_log_hash)
    assert result.command_log_hash == command_log_hash(run.command_log)
