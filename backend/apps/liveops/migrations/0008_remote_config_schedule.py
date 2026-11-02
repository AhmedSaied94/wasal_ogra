"""The daily drift check at 05:15 Cairo (B10 research R8). The pattern of `0006_offer_schedule`."""

from typing import Any

from django.db import migrations

NAME = "liveops.check_remote_config"


def create_schedule(apps: Any, schema_editor: Any) -> None:
    crontab_schedule = apps.get_model("django_celery_beat", "CrontabSchedule")
    periodic_task = apps.get_model("django_celery_beat", "PeriodicTask")
    daily, _ = crontab_schedule.objects.get_or_create(
        minute="15",
        hour="5",
        day_of_week="*",
        day_of_month="*",
        month_of_year="*",
        timezone="Africa/Cairo",
    )
    periodic_task.objects.update_or_create(
        name=NAME,
        defaults={
            "task": "liveops.tasks.check_remote_config",
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
        ("liveops", "0007_remote_config_check"),
        ("django_celery_beat", "0019_alter_periodictasks_options"),
    ]

    operations = [migrations.RunPython(create_schedule, remove_schedule)]
