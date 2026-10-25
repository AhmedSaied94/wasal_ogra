"""The economy settings, typed (specs/010-b03-ledger-sync/contracts/environment.md).

Read from `django.conf.settings` once per request or batch, so a test overrides one value with the
`settings` fixture and a deploy changes it with a restart.
"""

from __future__ import annotations

from dataclasses import dataclass

from django.conf import settings


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
    client_min_version: str
    client_latest_version: str


def current() -> EconomySettings:
    return EconomySettings(
        fuel_max=settings.ECONOMY_FUEL_MAX,
        fuel_max_subscriber=settings.ECONOMY_FUEL_MAX_SUBSCRIBER,
        fuel_regen_minutes=settings.ECONOMY_FUEL_REGEN_MINUTES,
        fuel_refill_daily_cap=settings.ECONOMY_FUEL_REFILL_DAILY_CAP,
        fuel_overdraft_per_day=settings.ECONOMY_FUEL_OVERDRAFT_PER_DAY,
        traffic_jam_ads_per_trip=settings.ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP,
        name_min_length=settings.ECONOMY_NAME_MIN_LENGTH,
        name_max_length=settings.ECONOMY_NAME_MAX_LENGTH,
        op_retention_days=settings.SYNC_OP_RETENTION_DAYS,
        content_max_age_days=settings.SYNC_CONTENT_MAX_AGE_DAYS,
        min_duration_percent=settings.SYNC_MIN_DURATION_PERCENT,
        fast_run_percent=settings.SYNC_FAST_RUN_PERCENT,
        trips_per_day_flag=settings.SYNC_TRIPS_PER_DAY_FLAG,
        clock_clamp_flag_minutes=settings.SYNC_CLOCK_CLAMP_FLAG_MINUTES,
        session_gap_minutes=settings.SYNC_SESSION_GAP_MINUTES,
        comeback_away_days=settings.SYNC_COMEBACK_AWAY_DAYS,
        comeback_cooldown_days=settings.SYNC_COMEBACK_COOLDOWN_DAYS,
        client_min_version=settings.CLIENT_MIN_VERSION,
        client_latest_version=settings.CLIENT_LATEST_VERSION,
    )
