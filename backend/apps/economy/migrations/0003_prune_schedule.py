"""The daily prune of old operations, trip runs and day counters (B03 research R11, R12). The pattern
of accounts/0004."""

from typing import Any

from django.db import migrations

NAME = "economy.prune"


def create_schedule(apps: Any, schema_editor: Any) -> None:
    crontab_schedule = apps.get_model("django_celery_beat", "CrontabSchedule")
    periodic_task = apps.get_model("django_celery_beat", "PeriodicTask")
    # 04:45 Cairo time, after the 03:00 backup and the 04:30 sessions' prune.
    daily, _ = crontab_schedule.objects.get_or_create(
        minute="45",
        hour="4",
        day_of_week="*",
        day_of_month="*",
        month_of_year="*",
        timezone="Africa/Cairo",
    )
    periodic_task.objects.update_or_create(
        name=NAME,
        defaults={
            "task": "economy.tasks.prune",
            "crontab": daily,
            "interval": None,
            "queue": "default",
            "enabled": True,
        },
    )


def remove_schedule(apps: Any, schema_editor: Any) -> None:
    apps.get_model("django_celery_beat", "PeriodicTask").objects.filter(name=NAME).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("economy", "0002_groups"),
        ("django_celery_beat", "0019_alter_periodictasks_options"),
    ]

    operations = [migrations.RunPython(create_schedule, remove_schedule)]
