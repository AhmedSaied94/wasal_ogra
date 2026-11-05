"""The shared game-day cases (fixtures/economy/game_day.json, specs/018-m11-ads research R9).

The app's `gameDayOf` (apps/mobile/lib/core/economy/domain/game_day.dart) has no timezone data: it
codes Egypt's rule since 2023. This fixture pins that rule to the server's `game_date`, so a tzdata
change fails here and the app's replay (apps/mobile/test/core/economy/game_day_test.dart) fails
until both agree again.

`WASSAL_REGEN_GAME_DAY=1 uv run pytest apps/economy/tests/test_game_day_fixture.py` rewrites the
file from `game_date`.
"""

from __future__ import annotations

import json
import os
from datetime import UTC, date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from django.conf import settings

from apps.economy.services.gameday import game_date
from apps.economy.services.timeline import from_ms, to_ms

FIXTURE = settings.BASE_DIR.parent / "fixtures" / "economy" / "game_day.json"
CAIRO = ZoneInfo("Africa/Cairo")
YEARS = range(2026, 2036)
SECOND = timedelta(seconds=1)


def _switches(year: int) -> list[datetime]:
    """The instants Cairo's UTC offset changes in `year`, found hour by hour, then to the second."""
    found: list[datetime] = []
    start = datetime(year, 1, 1, tzinfo=UTC)
    hour = timedelta(hours=1)
    t = start
    while t.year == year:
        if t.astimezone(CAIRO).utcoffset() != (t + hour).astimezone(CAIRO).utcoffset():
            lo, hi = t, t + hour
            while hi - lo > SECOND:
                mid = lo + (hi - lo) // 2
                if mid.astimezone(CAIRO).utcoffset() == lo.astimezone(CAIRO).utcoffset():
                    lo = mid
                else:
                    hi = mid
            found.append(hi)
        t += hour
    return found


def _local_midnight(day: date) -> datetime:
    return datetime(day.year, day.month, day.day, tzinfo=CAIRO).astimezone(UTC)


def _instants() -> list[datetime]:
    instants: set[datetime] = set()
    for year in YEARS:
        for switch in _switches(year):
            instants.update({switch - SECOND, switch, switch + SECOND})
            local_day = switch.astimezone(CAIRO).date()
            for offset in (-1, 0, 1, 2):
                midnight = _local_midnight(local_day + timedelta(days=offset))
                instants.update({midnight - SECOND, midnight, midnight + SECOND})
        for month in range(1, 13):
            noon = datetime(year, month, 15, 12, tzinfo=CAIRO).astimezone(UTC)
            instants.add(noon)
    return sorted(instants)


def _cases() -> list[dict[str, Any]]:
    return [
        {"ms": to_ms(instant), "date": game_date(instant).isoformat()} for instant in _instants()
    ]


def test_game_day_fixture_matches_game_date() -> None:
    if os.environ.get("WASSAL_REGEN_GAME_DAY") == "1":
        FIXTURE.write_text(json.dumps(_cases(), indent=1) + "\n")
    cases: list[dict[str, Any]] = json.loads(FIXTURE.read_text())
    assert cases == _cases()
    for case in cases:
        assert game_date(from_ms(case["ms"])).isoformat() == case["date"]


def test_the_fixture_covers_every_switch_and_month() -> None:
    cases: list[dict[str, Any]] = json.loads(FIXTURE.read_text())
    days = {case["date"] for case in cases}
    for year in YEARS:
        assert len(_switches(year)) == 2, year
        for month in range(1, 13):
            assert f"{year}-{month:02d}-15" in days
