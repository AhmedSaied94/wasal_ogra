"""The `player_support` group (B02 contracts/admin.md, research R12)."""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

NAME = "player_support"
CODENAMES = ["view_player", "change_player", "view_device", "view_identity"]


def create_group(apps: Any, schema_editor: Any) -> None:
    # Permissions are normally created after all migrations, so create them now.
    app_config = apps.get_app_config("accounts")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None

    group, _ = apps.get_model("auth", "Group").objects.get_or_create(name=NAME)
    permissions = apps.get_model("auth", "Permission").objects.filter(
        content_type__app_label="accounts", codename__in=CODENAMES
    )
    if permissions.count() != len(CODENAMES):
        raise RuntimeError(f"{NAME}: an accounts permission is missing")
    group.permissions.set(permissions)


def remove_group(apps: Any, schema_editor: Any) -> None:
    apps.get_model("auth", "Group").objects.filter(name=NAME).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0002_players"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(create_group, remove_group)]
