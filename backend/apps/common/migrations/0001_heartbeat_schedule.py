"""The 5-minute heartbeat schedule (FR-006, contracts/operations.md "Heartbeat")."""

from typing import Any

from django.db import migrations

NAME = "heartbeat"


def create_schedule(apps: Any, schema_editor: Any) -> None:
    interval_schedule = apps.get_model("django_celery_beat", "IntervalSchedule")
    periodic_task = apps.get_model("django_celery_beat", "PeriodicTask")
    every_5_minutes, _ = interval_schedule.objects.get_or_create(every=5, period="minutes")
    periodic_task.objects.update_or_create(
        name=NAME,
        defaults={
            "task": "common.tasks.heartbeat",
            "interval": every_5_minutes,
            "queue": "default",
            "enabled": True,
        },
    )


def remove_schedule(apps: Any, schema_editor: Any) -> None:
    apps.get_model("django_celery_beat", "PeriodicTask").objects.filter(name=NAME).delete()


class Migration(migrations.Migration):
    dependencies = [("django_celery_beat", "0019_alter_periodictasks_options")]

    operations = [migrations.RunPython(create_schedule, remove_schedule)]
