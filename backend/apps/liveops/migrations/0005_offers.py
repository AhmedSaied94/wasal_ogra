"""Offers: no row is seeded (FR-028), and `live_ops` gets view, add and change on them."""

from typing import Any

import apps.common.ids
import django.db.models.deletion
from django.contrib.auth.management import create_permissions
from django.db import migrations, models

PERMISSIONS = [
    ("liveops", "view_offer"),
    ("liveops", "add_offer"),
    ("liveops", "change_offer"),
]


def add_permissions(apps: Any, schema_editor: Any) -> None:
    app_config = apps.get_app_config("liveops")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None
    permission = apps.get_model("auth", "Permission")
    group = apps.get_model("auth", "Group").objects.get(name="live_ops")
    group.permissions.add(
        *[
            permission.objects.get(content_type__app_label=app, codename=codename)
            for app, codename in PERMISSIONS
        ]
    )


def remove_permissions(apps: Any, schema_editor: Any) -> None:
    permission = apps.get_model("auth", "Permission")
    group = apps.get_model("auth", "Group").objects.get(name="live_ops")
    group.permissions.remove(
        *[
            permission.objects.get(content_type__app_label=app, codename=codename)
            for app, codename in PERMISSIONS
        ]
    )


class Migration(migrations.Migration):
    dependencies = [
        ("liveops", "0004_products"),
    ]

    operations = [
        migrations.CreateModel(
            name="Offer",
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
                ("offer_id", models.SlugField(max_length=48, unique=True)),
                (
                    "kind",
                    models.CharField(
                        choices=[
                            ("starter", "Starter"),
                            ("sale", "Sale"),
                            ("season_pass", "Season Pass"),
                            ("other", "Other"),
                        ],
                        max_length=16,
                    ),
                ),
                ("starts_at", models.DateTimeField()),
                ("ends_at", models.DateTimeField(blank=True, null=True)),
                ("priority", models.SmallIntegerField(default=0)),
                ("rules", models.JSONField(blank=True, default=list)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("scheduled", "Scheduled"),
                            ("active", "Active"),
                            ("expired", "Expired"),
                        ],
                        default="scheduled",
                        max_length=16,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "product",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="offers",
                        to="liveops.storeproduct",
                    ),
                ),
            ],
            options={
                "indexes": [
                    models.Index(fields=["status", "starts_at"], name="offer_status_start")
                ],
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(
                            ("ends_at__isnull", True),
                            ("ends_at__gt", models.F("starts_at")),
                            _connector="OR",
                        ),
                        name="offer_ends_after_start",
                    )
                ],
            },
        ),
        migrations.RunPython(add_permissions, remove_permissions),
    ]
