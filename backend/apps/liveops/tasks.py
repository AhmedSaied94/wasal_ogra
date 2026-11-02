"""Live-ops background tasks: the maintenance guard, the offer expiry and the drift check.

`skip_in_maintenance` wraps every scheduled job that writes (research R7, FR-034); the drift check
and the heartbeat are the explicit exceptions, because they write only their own check rows.
"""

from __future__ import annotations

import functools
import logging
from collections.abc import Callable
from typing import Any, cast

import requests
from celery import Task, shared_task
from django.db import OperationalError

from apps.liveops import settings as live
from apps.liveops.services import offers, remote_config

logger = logging.getLogger("apps.liveops")

SKIPS = "skips_in_maintenance"


def skip_in_maintenance[F: Callable[..., Any]](task: F) -> F:
    """Return `{"skipped": "maintenance"}` while maintenance is on, and log it."""

    @functools.wraps(task)
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        if live.current()["maintenance_enabled"]:
            logger.info("task_skipped_maintenance", extra={"task": task.__name__})
            return {"skipped": "maintenance"}
        return task(*args, **kwargs)

    setattr(wrapper, SKIPS, True)
    return cast("F", wrapper)


@shared_task(
    name="liveops.tasks.expire_offers",
    bind=True,
    autoretry_for=(OperationalError,),
    retry_backoff=True,
    max_retries=3,
)
@skip_in_maintenance
def expire_offers(self: Task[[], dict[str, int]]) -> dict[str, int]:
    """Hourly: a scheduled offer becomes active, an ended one expired (FR-027)."""
    return offers.expire()


@shared_task(
    name="liveops.tasks.check_remote_config",
    bind=True,
    autoretry_for=(requests.RequestException,),
    retry_backoff=True,
    max_retries=3,
)
def check_remote_config(self: Task[[], dict[str, Any]]) -> dict[str, Any]:
    """Daily at 05:15 Cairo: compare the phone's Remote Config defaults with the live settings.

    Not wrapped by `skip_in_maintenance`: it writes only its own check row, and a drift report is
    exactly what an operator wants during maintenance (research R7, R8).
    """
    row = remote_config.run()
    return {"status": row.status, "drift": len(row.drift)}
