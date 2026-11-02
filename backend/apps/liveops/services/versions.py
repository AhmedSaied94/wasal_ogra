"""Active players per version, and what a new minimum would block (B10 research R10, FR-031/032)."""

from __future__ import annotations

from datetime import datetime, timedelta

from django.db.models import Count
from django.utils import timezone

from apps.accounts.models import Player
from apps.common.client import as_tuple, parse_client_version

ACTIVE_DAYS = 7
UNKNOWN = "unknown"


def fold(version: str) -> str:
    """`1.3.0+57` → `1.3.0`; a version that doesn't parse is `unknown`."""
    parsed = parse_client_version(version)
    return UNKNOWN if parsed is None else "{}.{}.{}".format(*parsed)


def active_counts(platform: str, *, now: datetime | None = None) -> dict[str, int]:
    """Players active within 7 days on `platform`, folded by version (build suffix ignored)."""
    since = (now or timezone.now()) - timedelta(days=ACTIVE_DAYS)
    rows = (
        Player.objects.filter(platform=platform, wallet__last_active_at__gte=since)
        .values("client_version")
        .annotate(players=Count("id"))
    )
    counts: dict[str, int] = {}
    for row in rows:
        version = fold(row["client_version"])
        counts[version] = counts.get(version, 0) + int(row["players"])
    return dict(sorted(counts.items(), key=lambda item: (item[0] == UNKNOWN, item[0])))


def blocked(platform: str, minimum: str, *, now: datetime | None = None) -> tuple[int, float]:
    """How many active players the minimum would block, and their share of all of them."""
    counts = active_counts(platform, now=now)
    floor = as_tuple(minimum)
    blocked_players = sum(
        players
        for version, players in counts.items()
        if version != UNKNOWN and as_tuple(version) < floor
    )
    total = sum(counts.values())
    return blocked_players, (blocked_players / total if total else 0.0)
