"""The game day: the calendar day in `SYNC_GAME_TIMEZONE`, `Africa/Cairo` by default (research
R3). Every daily counter is keyed by the game date of the operation's effective time."""

from __future__ import annotations

from datetime import date, datetime
from zoneinfo import ZoneInfo

from django.conf import settings


def game_date(instant: datetime) -> date:
    """The game day `instant` (an aware datetime) falls on. Follows the zone's daylight saving."""
    return instant.astimezone(ZoneInfo(settings.SYNC_GAME_TIMEZONE)).date()
