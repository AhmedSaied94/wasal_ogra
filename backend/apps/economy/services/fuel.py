"""The fuel rules (contracts/fuel.md): M05's, in the same integer arithmetic.

Times are UTC milliseconds since the epoch, `max_liters` is the tank's size and `regen_ms` a
liter's regeneration time, both read at the operation's time. Where this module and M05's
`fuel.dart` disagree on a rule that doesn't involve the server's clock, M05's wins: the shared
cases in `fixtures/economy/fuel.json` replay through both.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

# One `fuel_unlimited_1h`. It defines that product (glossary §3.3), so it isn't a setting.
UNLIMITED_WINDOW_MS = 3_600_000
MS_PER_MINUTE = 60_000

FUEL = "fuel"
UNLIMITED = "unlimited"


@dataclass(frozen=True)
class FuelState:
    """`counted_from_ms` is M05's `countedFrom`: below the maximum, when the current countdown
    started; at or above it, when the tank last became full."""

    liters: int
    counted_from_ms: int
    unlimited_until_ms: int | None = None


@dataclass(frozen=True)
class StartResult:
    """A trip start's fuel: the new state, or a refusal (`not_eligible`, `cap_reached`)."""

    state: FuelState
    reason: str | None = None
    overdraft: bool = False


def regen_ms_of(fuel_regen_minutes: int) -> int:
    return fuel_regen_minutes * MS_PER_MINUTE


def regenerate(s: FuelState, t: int, *, max_liters: int, regen_ms: int) -> FuelState:
    """Every liter that came back by `t`. At or above the maximum nothing regenerates."""
    if s.liters >= max_liters:
        return s
    n = max(0, (t - s.counted_from_ms) // regen_ms)
    if s.liters + n >= max_liters:
        # The moment it filled.
        filled = s.counted_from_ms + (max_liters - s.liters) * regen_ms
        return replace(s, liters=max_liters, counted_from_ms=filled)
    return replace(s, liters=s.liters + n, counted_from_ms=s.counted_from_ms + n * regen_ms)


def spend_one(s: FuelState, t: int, *, max_liters: int) -> FuelState:
    """One liter fewer. Leaving the maximum starts the countdown at `t`; below it, the time
    already counted is kept."""
    if s.liters < 1:
        raise ValueError("spend_one needs a liter")
    liters = s.liters - 1
    leaving_full = s.liters >= max_liters and liters < max_liters
    return replace(s, liters=liters, counted_from_ms=t if leaving_full else s.counted_from_ms)


def fill_to_max(s: FuelState, t: int, *, max_liters: int) -> FuelState | None:
    """A full tank at `t`, or None when it is already full (`tank_full`)."""
    if s.liters >= max_liters:
        return None
    return replace(s, liters=max_liters, counted_from_ms=t)


def extend_unlimited(s: FuelState, t: int) -> FuelState:
    """One more window, from `t` or from the end of a window still running."""
    start = max(t if s.unlimited_until_ms is None else s.unlimited_until_ms, t)
    return replace(s, unlimited_until_ms=start + UNLIMITED_WINDOW_MS)


def is_unlimited(s: FuelState, t: int) -> bool:
    return s.unlimited_until_ms is not None and t < s.unlimited_until_ms


def start(
    s: FuelState,
    t: int,
    *,
    mode: str,
    max_liters: int,
    regen_ms: int,
    overdrafts_today: int,
    overdraft_cap: int,
) -> StartResult:
    """A trip start at `t` (contracts/fuel.md "Per operation"). In `fuel` mode with no liter it
    is an overdraft: accepted, liters stay 0, while the game day has fewer than `overdraft_cap`."""
    r = regenerate(s, t, max_liters=max_liters, regen_ms=regen_ms)
    if mode == UNLIMITED:
        return StartResult(r) if is_unlimited(r, t) else StartResult(s, "not_eligible")
    if mode != FUEL:
        return StartResult(s, "not_eligible")
    if r.liters >= 1:
        return StartResult(spend_one(r, t, max_liters=max_liters))
    if overdrafts_today >= overdraft_cap:
        return StartResult(s, "cap_reached")
    return StartResult(r, overdraft=True)


def gift(s: FuelState, t: int, *, max_liters: int, regen_ms: int) -> FuelState:
    """The tutorial and comeback gifts: a full tank. A full tank is accepted and unchanged."""
    r = regenerate(s, t, max_liters=max_liters, regen_ms=regen_ms)
    return fill_to_max(r, t, max_liters=max_liters) or r
