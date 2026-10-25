"""The daily prune of old sessions (B02 research R3, data-model.md "Migrations")."""

from typing import Any

from django.db import migrations

NAME = "accounts.prune_sessions"


def create_schedule(apps: Any, schema_editor: Any) -> None:
    crontab_schedule = apps.get_model("django_celery_beat", "CrontabSchedule")
    periodic_task = apps.get_model("django_celery_beat", "PeriodicTask")
    # 04:30 Cairo time, after the 03:00 backup.
    daily, _ = crontab_schedule.objects.get_or_create(
        minute="30",
        hour="4",
        day_of_week="*",
        day_of_month="*",
        month_of_year="*",
        timezone="Africa/Cairo",
    )
    periodic_task.objects.update_or_create(
        name=NAME,
        defaults={
            "task": "accounts.tasks.prune_sessions",
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
        ("accounts", "0003_player_support_group"),
        ("django_celery_beat", "0019_alter_periodictasks_options"),
    ]

    operations = [migrations.RunPython(create_schedule, remove_schedule)]
