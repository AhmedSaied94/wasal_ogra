"""Background tasks of the accounts app (B02)."""

from __future__ import annotations

from datetime import timedelta

from celery import Task, shared_task
from django.db import OperationalError
from django.db.models import Q
from django.utils import timezone

from apps.accounts.models import PlayerSession

# Sessions ended or lapsed this long ago are deleted. Their tokens can't verify by then anyway:
# the keys that signed them may have been retired (research R3, R13).
KEEP = timedelta(days=30)


@shared_task(
    name="accounts.tasks.prune_sessions",
    bind=True,
    autoretry_for=(OperationalError,),
    retry_backoff=True,
    max_retries=3,
)
def prune_sessions(self: Task[[], int]) -> int:
    """Daily at 04:30 Cairo time, after the 03:00 backup. Returns how many rows it deleted."""
    cutoff = timezone.now() - KEEP
    gone = Q(status=PlayerSession.Status.ENDED, ended_at__lt=cutoff) | Q(
        current_expires_at__lt=cutoff
    )
    deleted, _ = PlayerSession.objects.filter(gone).delete()
    return deleted
