"""Background tasks of the ads app (B07 FR-006, FR-024, research R12)."""

from __future__ import annotations

from datetime import timedelta

from celery import Task, shared_task
from django.db import OperationalError
from django.utils import timezone

from apps.ads.models import AdReward
from apps.liveops.tasks import skip_in_maintenance

# Rows that granted nothing are kept this long for support questions; granted rows back the
# ledger and stay. The 7-day expiry still refuses a callback replayed after its row is gone.
RETENTION_DAYS = 90
CHUNK = 5_000


@shared_task(
    name="ads.tasks.prune_ad_rewards",
    bind=True,
    autoretry_for=(OperationalError,),
    retry_backoff=True,
    max_retries=3,
)
@skip_in_maintenance
def prune_ad_rewards(self: Task[[], dict[str, int]]) -> dict[str, int]:
    """Daily at 04:30 Cairo time, in chunks, so one run never holds a long lock."""
    cutoff = timezone.now() - timedelta(days=RETENTION_DAYS)
    old = AdReward.objects.filter(created_at__lt=cutoff).exclude(outcome=AdReward.Outcome.GRANTED)
    total = 0
    while ids := list(old.order_by("id").values_list("pk", flat=True)[:CHUNK]):
        deleted, _ = AdReward.objects.filter(pk__in=ids).delete()
        total += deleted
    return {"ad_rewards": total}
