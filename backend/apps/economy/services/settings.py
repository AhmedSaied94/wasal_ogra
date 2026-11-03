"""The economy settings, typed (B10 research R4, contracts/settings.md).

Every balancing number comes from one `liveops.settings.current()` snapshot, which the batch reads
once; a change applies within a minute without a restart. Only the game timezone and the operation
retention stay environment variables: the timezone is a contract with the phone and the retention
sizes the database.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from django.conf import settings

from apps.liveops import settings as live


@dataclass(frozen=True)
class EconomySettings:
    fuel_max: int
    fuel_max_subscriber: int
    fuel_regen_minutes: int
    fuel_refill_daily_cap: int
    fuel_overdraft_per_day: int
    traffic_jam_ads_per_trip: int
    name_min_length: int
    name_max_length: int
    op_retention_days: int
    content_max_age_days: int
    min_duration_percent: int
    fast_run_percent: int
    trips_per_day_flag: int
    clock_clamp_flag_minutes: int
    session_gap_minutes: int
    comeback_away_days: int
    comeback_cooldown_days: int


def current() -> EconomySettings:
    return from_snapshot(live.current())


def from_snapshot(snapshot: Mapping[str, Any]) -> EconomySettings:
    """The economy's view of a snapshot a caller already holds (one read per request)."""
    return EconomySettings(
        fuel_max=snapshot["fuel_max"],
        fuel_max_subscriber=snapshot["fuel_max_subscriber"],
        fuel_regen_minutes=snapshot["fuel_regen_minutes"],
        fuel_refill_daily_cap=snapshot["ads_fuel_refill_daily_cap"],
        fuel_overdraft_per_day=snapshot["fuel_overdraft_per_day"],
        traffic_jam_ads_per_trip=snapshot["traffic_jam_ads_per_trip"],
        name_min_length=snapshot["name_min_length"],
        name_max_length=snapshot["name_max_length"],
        op_retention_days=settings.SYNC_OP_RETENTION_DAYS,
        content_max_age_days=snapshot["content_max_age_days"],
        min_duration_percent=snapshot["min_duration_percent"],
        fast_run_percent=snapshot["fast_run_percent"],
        trips_per_day_flag=snapshot["trips_per_day_flag"],
        clock_clamp_flag_minutes=snapshot["clock_clamp_flag_minutes"],
        session_gap_minutes=snapshot["session_gap_minutes"],
        comeback_away_days=snapshot["comeback_away_days"],
        comeback_cooldown_days=snapshot["comeback_cooldown_days"],
    )
