"""The entitlements seam (B03 research R16). B06 and B12 fill it from purchases and
subscriptions; until then every player has none, and the tank is `ECONOMY_FUEL_MAX`."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from apps.accounts.models import Player
from apps.economy.services.settings import EconomySettings

NEUTRAL_FLAGS: dict[str, Any] = {"no_interstitials": False, "fuel_max_bonus": 0}


def flags_for(player: Player, at: datetime) -> dict[str, Any]:
    """The entitlement flags in force at `at`."""
    return dict(NEUTRAL_FLAGS)


def entitlements_for(player: Player, at: datetime) -> dict[str, Any]:
    """Bootstrap's `entitlements` block: neutral until B06 (contracts/api.md)."""
    return {
        "remove_ads": False,
        "subscription": None,
        "season_passes": [],
        "flags": flags_for(player, at),
    }


def tank_size(player: Player, at: datetime, settings: EconomySettings) -> int:
    """`fuel_max`, or `fuel_max_subscriber` while the flags carry `fuel_max_bonus` (FR-031)."""
    if flags_for(player, at).get("fuel_max_bonus"):
        return settings.fuel_max_subscriber
    return settings.fuel_max
