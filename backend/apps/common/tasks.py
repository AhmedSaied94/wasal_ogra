"""Background tasks of the common app."""

from __future__ import annotations

import requests
from celery import Task, shared_task
from django.conf import settings

from apps.common.services import monitoring


@shared_task(
    name="common.tasks.heartbeat",
    bind=True,
    autoretry_for=(requests.RequestException,),
    retry_backoff=True,
    max_retries=3,
)
def heartbeat(self: Task[[], None]) -> None:
    """Runs every 5 minutes. Its ping proves scheduler, broker and worker all work (FR-006)."""
    monitoring.ping(settings.HC_PING_HEARTBEAT_URL, timeout=10)


class SentryTestError(Exception):
    """Raised on purpose by `manage.py sentry_test` (quickstart scenario 16)."""


# Never retried: one test, one Sentry issue.
@shared_task(name="common.tasks.sentry_test", bind=True, max_retries=0)
def sentry_test(self: Task[[], None]) -> None:
    """Fails on purpose, so the worker's Sentry integration reports it (`sentry_test --task`)."""
    raise SentryTestError("sentry_test: a test error from a worker task")
