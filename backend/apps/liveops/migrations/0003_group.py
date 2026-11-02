"""The `live_ops` group (B10 contracts/admin.md "Group live_ops"). The pattern of
`economy/0002_groups`: only it and superusers see the live-ops pages.

Later phases add their models' permissions to the same group in their own migrations, so each
migration only names tables that exist.
"""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

GROUP = "live_ops"
PERMISSIONS = [
    ("liveops", "view_livesetting"),
    ("liveops", "change_livesetting"),
    ("liveops", "view_liveopschange"),
    ("liveops", "switch_maintenance"),
]


def create_group(apps: Any, schema_editor: Any) -> None:
    # Permissions are normally created after all migrations, so create them now.
    app_config = apps.get_app_config("liveops")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None

    permission = apps.get_model("auth", "Permission")
    group, _ = apps.get_model("auth", "Group").objects.get_or_create(name=GROUP)
    group.permissions.set(
        [
            permission.objects.get(content_type__app_label=app, codename=codename)
            for app, codename in PERMISSIONS
        ]
    )


def remove_group(apps: Any, schema_editor: Any) -> None:
    apps.get_model("auth", "Group").objects.filter(name=GROUP).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("liveops", "0002_seed"),
        ("accounts", "0006_name_filter_seed"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(create_group, remove_group)]
