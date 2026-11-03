"""The daily cleanup (B07 FR-006, FR-024, research R12)."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

import pytest
from django.utils import timezone
from django_celery_beat.models import PeriodicTask

from apps.accounts.models import Player
from apps.ads import tasks
from apps.ads.models import AdReward
from apps.ads.tests.helpers import reward_row
from apps.liveops.tasks import SKIPS

pytestmark = pytest.mark.django_db


def days_ago(days: float) -> datetime:
    return timezone.now() - timedelta(days=days)


def test_old_refusals_go_and_grants_stay(player: Player) -> None:
    for _ in range(3):
        reward_row(None, "unattributed", at=days_ago(91))
    young = reward_row(player, "cap_reached", at=days_ago(89))
    old_granted = reward_row(player, at=days_ago(400))
    assert tasks.prune_ad_rewards.apply().get() == {"ad_rewards": 3}
    assert set(AdReward.objects.values_list("pk", flat=True)) == {young.pk, old_granted.pk}


def test_it_goes_in_chunks(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tasks, "CHUNK", 2)
    for _ in range(5):
        reward_row(None, "malformed", at=days_ago(100), nonce=None)
    assert tasks.prune_ad_rewards.apply().get() == {"ad_rewards": 5}


def test_it_skips_during_maintenance(live_settings: Any, caplog: Any) -> None:
    reward_row(None, "unattributed", at=days_ago(100))
    live_settings(maintenance_enabled=True)
    with caplog.at_level("INFO"):
        result: Any = tasks.prune_ad_rewards.apply().get()
        assert result == {"skipped": "maintenance"}
    assert any(r.message == "task_skipped_maintenance" for r in caplog.records)
    assert AdReward.objects.count() == 1


def test_it_is_scheduled_at_half_past_four_cairo_and_wrapped() -> None:
    task = PeriodicTask.objects.get(name="ads.prune_ad_rewards")
    assert task.task == "ads.tasks.prune_ad_rewards"
    assert task.crontab is not None
    crontab = (task.crontab.minute, task.crontab.hour, str(task.crontab.timezone))
    assert crontab == ("30", "4", "Africa/Cairo")
    assert getattr(tasks.prune_ad_rewards.run, SKIPS, False)
