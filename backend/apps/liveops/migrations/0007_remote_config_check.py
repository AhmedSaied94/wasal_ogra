"""The drift check's runs (B10 research R8), with view-only access for `live_ops`."""

from typing import Any

import apps.common.ids
from django.contrib.auth.management import create_permissions
from django.db import migrations, models


def add_permissions(apps: Any, schema_editor: Any) -> None:
    app_config = apps.get_app_config("liveops")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None
    permission = apps.get_model("auth", "Permission")
    group = apps.get_model("auth", "Group").objects.get(name="live_ops")
    group.permissions.add(
        permission.objects.get(content_type__app_label="liveops", codename="view_remoteconfigcheck")
    )


def remove_permissions(apps: Any, schema_editor: Any) -> None:
    permission = apps.get_model("auth", "Permission")
    group = apps.get_model("auth", "Group").objects.get(name="live_ops")
    group.permissions.remove(
        permission.objects.get(content_type__app_label="liveops", codename="view_remoteconfigcheck")
    )


class Migration(migrations.Migration):
    dependencies = [
        ("liveops", "0006_offer_schedule"),
    ]

    operations = [
        migrations.CreateModel(
            name="RemoteConfigCheck",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=apps.common.ids.uuid7,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("ran_at", models.DateTimeField()),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("ok", "Ok"),
                            ("drift", "Drift"),
                            ("unreachable", "Unreachable"),
                            ("not_configured", "Not Configured"),
                        ],
                        max_length=16,
                    ),
                ),
                ("template_version", models.CharField(blank=True, max_length=32)),
                ("drift", models.JSONField(blank=True, default=list)),
            ],
            options={
                "verbose_name": "Remote Config check",
                "ordering": ("-ran_at", "-id"),
                "indexes": [models.Index(fields=["ran_at"], name="remote_config_ran_at")],
            },
        ),
        migrations.RunPython(add_permissions, remove_permissions),
    ]
