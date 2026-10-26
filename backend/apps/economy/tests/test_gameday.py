"""The game day is Cairo's calendar day, through its daylight saving (research R3)."""

from __future__ import annotations

from datetime import date, datetime

from pytest_django import Settings

from apps.economy.services.gameday import game_date


def utc(stamp: str) -> datetime:
    return datetime.fromisoformat(stamp + "+00:00")


def test_summer_time_days_turn_at_21_utc() -> None:
    # Egypt is UTC+3 in summer: midnight in Cairo is 21:00 UTC.
    assert game_date(utc("2026-10-17T20:59:59")) == date(2026, 10, 17)
    assert game_date(utc("2026-10-17T21:00:00")) == date(2026, 10, 18)


def test_winter_time_days_turn_at_22_utc() -> None:
    # UTC+2 in winter: 21:59:59 and 22:00:00 UTC fall on different game days.
    assert game_date(utc("2026-12-17T21:59:59")) == date(2026, 12, 17)
    assert game_date(utc("2026-12-17T22:00:00")) == date(2026, 12, 18)


def test_the_day_boundary_moves_with_the_daylight_saving_change() -> None:
    # Daylight saving ends at the end of 29 October 2026: the 28th turns at 21:00 UTC,
    # the 30th at 22:00 UTC.
    assert game_date(utc("2026-10-28T20:59:59")) == date(2026, 10, 28)
    assert game_date(utc("2026-10-28T21:00:00")) == date(2026, 10, 29)
    assert game_date(utc("2026-10-30T21:59:59")) == date(2026, 10, 30)
    assert game_date(utc("2026-10-30T22:00:00")) == date(2026, 10, 31)


def test_the_zone_is_a_setting(settings: Settings) -> None:
    settings.SYNC_GAME_TIMEZONE = "UTC"
    assert game_date(utc("2026-10-17T21:00:00")) == date(2026, 10, 17)
    settings.SYNC_GAME_TIMEZONE = "Asia/Riyadh"  # UTC+3 all year
    assert game_date(utc("2026-12-17T21:00:00")) == date(2026, 12, 18)
