"""Times as integer milliseconds, and the effective time of an operation (contracts/fuel.md).

No float anywhere: a datetime becomes milliseconds by integer division of two timedeltas.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
MILLISECOND = timedelta(milliseconds=1)


def to_ms(instant: datetime) -> int:
    return (instant - EPOCH) // MILLISECOND


def from_ms(ms: int) -> datetime:
    return EPOCH + timedelta(milliseconds=ms)


def effective(occurred_at: datetime, timeline_at: datetime, now: datetime) -> datetime:
    """`clamp(occurred_at, timeline_at, now)`: never before the last operation applied, never past
    the server's clock (research R7)."""
    return min(max(occurred_at, timeline_at), max(timeline_at, now))
