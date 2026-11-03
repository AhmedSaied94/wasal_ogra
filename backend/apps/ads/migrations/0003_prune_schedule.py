"""The daily cleanup of rewards that granted nothing (B07 FR-006, research R12). The pattern of
`liveops/0006_offer_schedule`."""

from typing import Any

from django.db import migrations

NAME = "ads.prune_ad_rewards"


def create_schedule(apps: Any, schema_editor: Any) -> None:
    crontab_schedule = apps.get_model("django_celery_beat", "CrontabSchedule")
    periodic_task = apps.get_model("django_celery_beat", "PeriodicTask")
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
            "task": "ads.tasks.prune_ad_rewards",
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
        ("ads", "0002_view_permissions"),
        ("django_celery_beat", "0019_alter_periodictasks_options"),
    ]

    operations = [migrations.RunPython(create_schedule, remove_schedule)]
