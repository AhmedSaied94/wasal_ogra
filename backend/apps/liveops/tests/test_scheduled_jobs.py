"""Every scheduled job that writes skips its run during maintenance (B10 FR-034, research R7)."""

from __future__ import annotations

import importlib
from typing import Any

import pytest
from celery import current_app
from django_celery_beat.models import PeriodicTask

from apps import accounts, common, content, economy  # noqa: F401
from apps.liveops.tasks import SKIPS, expire_offers, skip_in_maintenance

pytestmark = pytest.mark.django_db

# Jobs that write only their own check rows: the heartbeat and the drift check.
MONITORING = {"common.tasks.heartbeat", "liveops.tasks.check_remote_config"}


def test_the_schedule_holds_the_offer_expiry() -> None:
    task = PeriodicTask.objects.get(name="liveops.expire_offers")
    assert task.task == "liveops.tasks.expire_offers"
    assert task.crontab is not None
    assert task.crontab.minute == "0"


def test_every_periodic_task_is_wrapped_or_monitored() -> None:
    # A task name is registered only once its module is imported in this process.
    for module in (
        "apps.accounts.tasks",
        "apps.ads.tasks",
        "apps.common.tasks",
        "apps.content.tasks",
        "apps.economy.tasks",
        "apps.liveops.tasks",
    ):
        importlib.import_module(module)
    tasks = list(PeriodicTask.objects.values_list("task", flat=True))
    assert tasks  # the migrations create some
    for name in tasks:
        if name in MONITORING:
            continue
        registered = current_app.tasks[name]
        assert getattr(registered.run, SKIPS, False), f"{name} writes during maintenance"


def test_a_wrapped_task_skips_while_on(live_settings: Any, caplog: Any) -> None:
    live_settings(maintenance_enabled=True)
    from apps.economy import tasks as economy_tasks

    with caplog.at_level("INFO"):
        result = economy_tasks.prune.apply().get()
    assert result == {"skipped": "maintenance"}  # type: ignore[comparison-overlap]
    assert any(record.message == "task_skipped_maintenance" for record in caplog.records)


def test_a_wrapped_task_runs_while_off() -> None:
    from apps.economy import tasks as economy_tasks

    result = economy_tasks.prune.apply().get()
    assert "processed_ops" in result


def test_the_decorator_returns_the_task_result() -> None:
    @skip_in_maintenance
    def job(value: int) -> int:
        return value + 1

    assert job(1) == 2
    assert getattr(job, SKIPS, False) is True
    assert expire_offers.name == "liveops.tasks.expire_offers"
