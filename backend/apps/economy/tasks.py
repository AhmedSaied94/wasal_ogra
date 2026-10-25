"""Background tasks of the economy (B03 spec FR-043, research R11, R12)."""

from __future__ import annotations

from datetime import timedelta
from typing import Any

from celery import Task, shared_task
from django.db import OperationalError
from django.db.models import QuerySet
from django.utils import timezone

from apps.economy.models import DayCounter, ProcessedOp
from apps.economy.services import settings
from apps.economy.services.gameday import game_date
from apps.progress.models import TripRun

# Deleted in chunks, so one day's prune never holds a long lock or a huge transaction.
CHUNK = 10_000
TRIP_RUN_KEEP = timedelta(days=90)
# Longer than any counter's window (a game day) and the 30-day comeback cooldown.
DAY_COUNTER_KEEP = timedelta(days=40)
# How far ahead of the server's clock an operation id may be dated before it is `op_expired`.
FUTURE_ID_MARGIN = timedelta(days=1)


@shared_task(
    name="economy.tasks.prune",
    bind=True,
    autoretry_for=(OperationalError,),
    retry_backoff=True,
    max_retries=3,
)
def prune(self: Task[[], dict[str, int]]) -> dict[str, int]:
    """Daily at 04:45 Cairo time, after the sessions' prune. The ledger, progress, ownership and
    inventory are never deleted. A pruned operation id stays refused: it is older than the
    retention, so it is `op_expired` (research R11). Operations are kept one day longer than the
    retention, because an id may be dated up to a day ahead of the server's clock."""
    now = timezone.now()
    kept_ops = timedelta(days=settings.current().op_retention_days) + FUTURE_ID_MARGIN
    return {
        "processed_ops": _delete_in_chunks(
            ProcessedOp.objects.filter(processed_at__lt=now - kept_ops)
        ),
        "trip_runs": _delete_in_chunks(TripRun.objects.filter(created_at__lt=now - TRIP_RUN_KEEP)),
        "day_counters": _delete_in_chunks(
            DayCounter.objects.filter(game_date__lt=game_date(now) - DAY_COUNTER_KEEP)
        ),
    }


def _delete_in_chunks(rows: QuerySet[Any]) -> int:
    total = 0
    while ids := list(rows.values_list("pk", flat=True)[:CHUNK]):
        deleted, _ = rows.model.objects.filter(pk__in=ids).delete()
        total += deleted
    return total
