"""The `core` channel row, and the content beat jobs (research R10, data-model "Framework tables")."""

import json
from typing import Any

from django.db import migrations

SWEEP = "content.sweep_stuck_builds"
SYNC = "content.sync_files"


def create(apps: Any, schema_editor: Any) -> None:
    apps.get_model("content", "ContentChannel").objects.get_or_create(pack_id="core")

    interval_schedule = apps.get_model("django_celery_beat", "IntervalSchedule")
    crontab_schedule = apps.get_model("django_celery_beat", "CrontabSchedule")
    periodic_task = apps.get_model("django_celery_beat", "PeriodicTask")
    every_10_minutes, _ = interval_schedule.objects.get_or_create(every=10, period="minutes")
    daily_at_2, _ = crontab_schedule.objects.get_or_create(
        minute="0",
        hour="2",
        day_of_week="*",
        day_of_month="*",
        month_of_year="*",
        timezone="UTC",
    )
    periodic_task.objects.update_or_create(
        name=SWEEP,
        defaults={
            "task": "content.tasks.sweep_stuck_builds",
            "interval": every_10_minutes,
            "queue": "content",
            "enabled": True,
        },
    )
    periodic_task.objects.update_or_create(
        name=SYNC,
        defaults={
            "task": "content.tasks.sync_files",
            "crontab": daily_at_2,
            "kwargs": json.dumps({"verify": True}),
            "queue": "content",
            "enabled": True,
        },
    )


def remove(apps: Any, schema_editor: Any) -> None:
    apps.get_model("django_celery_beat", "PeriodicTask").objects.filter(
        name__in=[SWEEP, SYNC]
    ).delete()
    channel = apps.get_model("content", "ContentChannel")
    channel.objects.filter(pack_id="core", current__isnull=True).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("content", "0003_groups"),
        ("django_celery_beat", "0019_alter_periodictasks_options"),
    ]

    operations = [migrations.RunPython(create, remove)]
