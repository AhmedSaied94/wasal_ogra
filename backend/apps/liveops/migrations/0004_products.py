"""The store catalog: the four products of FR-020, and the `live_ops` permissions (B10 US3).

The seed amounts are the spec's (60 / 300 + 30 / 800 + 120), on both platforms. No price column
exists, by design (FR-021).
"""

from typing import Any

import apps.common.ids
import django.contrib.postgres.fields
from django.contrib.auth.management import create_permissions
from django.db import migrations, models

PRODUCTS = [
    dict(
        product_id="bonat_pack_s",
        kind="consumable",
        bonat=60,
        bonus_bonat=0,
        entitlement="",
        best_value=False,
        display_order=1,
    ),
    dict(
        product_id="bonat_pack_m",
        kind="consumable",
        bonat=300,
        bonus_bonat=30,
        entitlement="",
        best_value=False,
        display_order=2,
    ),
    dict(
        product_id="bonat_pack_l",
        kind="consumable",
        bonat=800,
        bonus_bonat=120,
        entitlement="",
        best_value=True,
        display_order=3,
    ),
    dict(
        product_id="remove_ads",
        kind="non_consumable",
        bonat=0,
        bonus_bonat=0,
        entitlement="remove_ads",
        best_value=False,
        display_order=4,
    ),
]
PERMISSIONS = [
    ("liveops", "view_storeproduct"),
    ("liveops", "add_storeproduct"),
    ("liveops", "change_storeproduct"),
]


def seed_products(apps: Any, schema_editor: Any) -> None:
    product = apps.get_model("liveops", "StoreProduct")
    for row in PRODUCTS:
        product.objects.update_or_create(
            product_id=row["product_id"],
            defaults={**row, "platforms": ["android", "ios"], "active": True},
        )
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


def unseed_products(apps: Any, schema_editor: Any) -> None:
    apps.get_model("liveops", "StoreProduct").objects.filter(
        product_id__in=[row["product_id"] for row in PRODUCTS]
    ).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("liveops", "0003_group"),
    ]

    operations = [
        migrations.CreateModel(
            name="StoreProduct",
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
                ("product_id", models.CharField(max_length=48, unique=True)),
                (
                    "kind",
                    models.CharField(
                        choices=[
                            ("consumable", "Consumable"),
                            ("non_consumable", "Non Consumable"),
                            ("subscription", "Subscription"),
                        ],
                        max_length=16,
                    ),
                ),
                (
                    "platforms",
                    django.contrib.postgres.fields.ArrayField(
                        base_field=models.CharField(max_length=8),
                        default=list,
                        size=None,
                    ),
                ),
                ("bonat", models.PositiveIntegerField(default=0)),
                ("bonus_bonat", models.PositiveIntegerField(default=0)),
                ("entitlement", models.CharField(blank=True, max_length=32)),
                ("best_value", models.BooleanField(default=False)),
                ("display_order", models.SmallIntegerField(default=0)),
                ("active", models.BooleanField(default=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "verbose_name": "store product",
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(
                            models.Q(("kind", "consumable"), _negated=True),
                            models.Q(("bonat__gt", 0), ("entitlement", "")),
                            _connector="OR",
                        ),
                        name="product_consumable_grants",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(
                            models.Q(("kind", "non_consumable"), _negated=True),
                            models.Q(
                                ("bonat", 0),
                                ("bonus_bonat", 0),
                                models.Q(("entitlement", ""), _negated=True),
                            ),
                            _connector="OR",
                        ),
                        name="product_non_consumable_grants",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("platforms", []), _negated=True),
                        name="product_platforms_not_empty",
                    ),
                    models.UniqueConstraint(
                        condition=models.Q(("active", True), ("best_value", True)),
                        fields=("best_value",),
                        name="product_one_best_value",
                    ),
                ],
            },
        ),
        migrations.RunPython(seed_products, unseed_products),
    ]
