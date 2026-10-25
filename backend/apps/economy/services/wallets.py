"""The wallet as the answers show it (contracts/api.md): fuel recounted to the server's now,
without writing it (contracts/fuel.md, "A read")."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, overload

from apps.accounts.models import Player
from apps.economy.models import Wallet
from apps.economy.services import entitlements, fuel
from apps.economy.services.settings import EconomySettings
from apps.economy.services.timeline import from_ms, to_ms


@overload
def iso(instant: datetime) -> str: ...
@overload
def iso(instant: None) -> None: ...
@overload
def iso(instant: datetime | None) -> str | None: ...
def iso(instant: datetime | None) -> str | None:
    """ISO-8601 UTC with `Z`: to the second, or to the millisecond when it has one, so the app
    rebuilds a countdown exactly (M05 counts in milliseconds)."""
    if instant is None:
        return None
    utc = instant.astimezone(UTC)
    millis = utc.microsecond // 1000
    stamp = utc.strftime("%Y-%m-%dT%H:%M:%S")
    return f"{stamp}.{millis:03d}Z" if millis else f"{stamp}Z"


def fuel_state(wallet: Wallet) -> fuel.FuelState:
    until = wallet.fuel_unlimited_until
    return fuel.FuelState(
        liters=wallet.fuel,
        counted_from_ms=to_ms(wallet.fuel_updated_at),
        unlimited_until_ms=None if until is None else to_ms(until),
    )


def answer(
    wallet: Wallet, player: Player, now: datetime, settings: EconomySettings
) -> dict[str, Any]:
    """`{jenehat, bonat, fuel, fuel_max, fuel_updated_at, fuel_unlimited_until}` at `now`."""
    tank = entitlements.tank_size(player, now, settings)
    shown = fuel.regenerate(
        fuel_state(wallet),
        to_ms(now),
        max_liters=tank,
        regen_ms=fuel.regen_ms_of(settings.fuel_regen_minutes),
    )
    return {
        "jenehat": wallet.jenehat,
        "bonat": wallet.bonat,
        "fuel": shown.liters,
        "fuel_max": tank,
        "fuel_updated_at": iso(from_ms(shown.counted_from_ms)),
        "fuel_unlimited_until": iso(wallet.fuel_unlimited_until),
    }
