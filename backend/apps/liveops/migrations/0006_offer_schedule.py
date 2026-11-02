"""The hourly offer expiry (B10 US5, FR-027). The pattern of `economy/0003_prune_schedule`."""

from typing import Any

from django.db import migrations

NAME = "liveops.expire_offers"


def create_schedule(apps: Any, schema_editor: Any) -> None:
    crontab_schedule = apps.get_model("django_celery_beat", "CrontabSchedule")
    periodic_task = apps.get_model("django_celery_beat", "PeriodicTask")
    hourly, _ = crontab_schedule.objects.get_or_create(
        minute="0",
        hour="*",
        day_of_week="*",
        day_of_month="*",
        month_of_year="*",
        timezone="Africa/Cairo",
    )
    periodic_task.objects.update_or_create(
        name=NAME,
        defaults={
            "task": "liveops.tasks.expire_offers",
            "crontab": hourly,
            "interval": None,
            "queue": "default",
            "enabled": True,
        },
    )


def remove_schedule(apps: Any, schema_editor: Any) -> None:
    apps.get_model("django_celery_beat", "PeriodicTask").objects.filter(name=NAME).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("liveops", "0005_offers"),
        ("django_celery_beat", "0019_alter_periodictasks_options"),
    ]

    operations = [migrations.RunPython(create_schedule, remove_schedule)]
