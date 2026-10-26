"""The fuel rules in integer milliseconds (contracts/fuel.md, research R7)."""

from __future__ import annotations

import tokenize
from pathlib import Path

import pytest

from apps.economy.services import fuel
from apps.economy.services.fuel import FuelState

MINUTE = 60_000
REGEN = 20 * MINUTE
T0 = 1_792_659_600_000  # 2026-10-17T09:00:00Z


def at(minutes: int) -> int:
    return T0 + minutes * MINUTE


def regen(s: FuelState, t: int, max_liters: int = 5) -> FuelState:
    return fuel.regenerate(s, t, max_liters=max_liters, regen_ms=REGEN)


def test_regen_ms_of() -> None:
    assert fuel.regen_ms_of(20) == REGEN


def test_regenerate_counts_whole_liters_and_keeps_the_rest_of_the_countdown() -> None:
    s = FuelState(2, at(0))
    assert regen(s, at(19)) == s
    assert regen(s, at(20)) == FuelState(3, at(20))
    assert regen(s, at(45)) == FuelState(4, at(40))
    # Full at 09:60: counting stops there.
    assert regen(s, at(500)) == FuelState(5, at(60))
    # Time before the countdown counts for nothing.
    assert regen(s, at(-30)) == s


def test_regenerate_does_nothing_at_or_above_the_maximum() -> None:
    assert regen(FuelState(5, at(0)), at(100)) == FuelState(5, at(0))
    assert regen(FuelState(7, at(0)), at(100)) == FuelState(7, at(0))


def test_spend_one_starts_the_countdown_only_when_leaving_full() -> None:
    assert fuel.spend_one(FuelState(5, at(-60)), at(0), max_liters=5) == FuelState(4, at(0))
    assert fuel.spend_one(FuelState(3, at(-5)), at(0), max_liters=5) == FuelState(2, at(-5))
    # Above a lowered maximum, a liter fewer is still at or above it: nothing counts yet.
    assert fuel.spend_one(FuelState(5, at(-60)), at(0), max_liters=4) == FuelState(4, at(-60))
    with pytest.raises(ValueError, match="needs a liter"):
        fuel.spend_one(FuelState(0, at(0)), at(0), max_liters=5)


def test_fill_to_max_refuses_a_full_tank() -> None:
    assert fuel.fill_to_max(FuelState(1, at(-10)), at(0), max_liters=5) == FuelState(5, at(0))
    assert fuel.fill_to_max(FuelState(5, at(-10)), at(0), max_liters=5) is None
    assert fuel.fill_to_max(FuelState(6, at(-10)), at(0), max_liters=5) is None


def test_extend_unlimited_from_now_or_from_the_end_of_a_running_window() -> None:
    hour = fuel.UNLIMITED_WINDOW_MS
    assert fuel.extend_unlimited(FuelState(2, at(0)), at(0)).unlimited_until_ms == at(0) + hour
    running = FuelState(2, at(0), at(30))
    assert fuel.extend_unlimited(running, at(10)).unlimited_until_ms == at(30) + hour
    ended = FuelState(2, at(0), at(5))
    assert fuel.extend_unlimited(ended, at(10)).unlimited_until_ms == at(10) + hour


def test_is_unlimited() -> None:
    assert not fuel.is_unlimited(FuelState(0, at(0)), at(0))
    assert fuel.is_unlimited(FuelState(0, at(0), at(10)), at(9))
    assert not fuel.is_unlimited(FuelState(0, at(0), at(10)), at(10))


def test_start_in_each_mode() -> None:
    def start(s: FuelState, mode: str, overdrafts: int = 0) -> fuel.StartResult:
        return fuel.start(
            s,
            at(0),
            mode=mode,
            max_liters=5,
            regen_ms=REGEN,
            overdrafts_today=overdrafts,
            overdraft_cap=2,
        )

    assert start(FuelState(3, at(-5)), "fuel") == fuel.StartResult(FuelState(2, at(-5)))
    empty = FuelState(0, at(-5))
    assert start(empty, "fuel") == fuel.StartResult(empty, overdraft=True)
    assert start(empty, "fuel", overdrafts=2) == fuel.StartResult(empty, "cap_reached")
    window = FuelState(0, at(-5), at(10))
    assert start(window, "unlimited") == fuel.StartResult(window)
    assert start(empty, "unlimited") == fuel.StartResult(empty, "not_eligible")
    assert start(FuelState(3, at(-5)), "challenge") == fuel.StartResult(
        FuelState(3, at(-5)), "not_eligible"
    )


def test_gift_fills_a_tank_and_leaves_a_full_one() -> None:
    assert fuel.gift(FuelState(1, at(-10)), at(0), max_liters=5, regen_ms=REGEN) == FuelState(
        5, at(0)
    )
    full = FuelState(5, at(-10))
    assert fuel.gift(full, at(0), max_liters=5, regen_ms=REGEN) == full
    # Above a lowered maximum the liters are kept, not cut to it.
    assert fuel.gift(FuelState(7, at(-10)), at(0), max_liters=5, regen_ms=REGEN).liters == 7


def code_tokens(path: Path) -> list[tokenize.TokenInfo]:
    with open(path, "rb") as source:
        return [
            token
            for token in tokenize.tokenize(source.readline)
            if token.type in (tokenize.NAME, tokenize.OP)
        ]


def test_the_fuel_module_is_integer_only() -> None:
    """No `float`, `Decimal` or true division (`/`); integer floor division (`//`) is the rule."""
    path = Path(fuel.__file__)
    for token in code_tokens(path):
        assert token.string not in ("float", "Decimal", "/", "/="), f"{path.name}:{token.start}"
