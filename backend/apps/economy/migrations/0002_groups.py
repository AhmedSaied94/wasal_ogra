"""The `economy_ops` group, and what `player_support` may see (B03 contracts/admin.md "Groups and
permissions"). The pattern of accounts/0003."""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

SUPPORT = "player_support"
OPS = "economy_ops"
# (app label, codename) added to player_support; economy_ops has them too.
SUPPORT_ADDS = [
    ("economy", "view_wallet"),
    ("economy", "view_ledgerentry"),
    ("economy", "view_processedop"),
    ("economy", "view_inventory"),
    ("economy", "view_grantrecord"),
    ("economy", "view_playerflag"),
    ("economy", "change_playerflag"),
    ("progress", "view_ownership"),
    ("progress", "view_tripprogress"),
    ("progress", "view_storystate"),
]
OPS_ONLY = [
    ("accounts", "view_player"),
    ("economy", "adjust_wallet"),
    ("economy", "view_walletadjustment"),
    ("accounts", "view_namefilterentry"),
    ("accounts", "add_namefilterentry"),
    ("accounts", "change_namefilterentry"),
    ("accounts", "delete_namefilterentry"),
]


def _permissions(apps: Any, pairs: list[tuple[str, str]]) -> list[Any]:
    permission = apps.get_model("auth", "Permission")
    found = [
        permission.objects.get(content_type__app_label=app, codename=codename)
        for app, codename in pairs
    ]
    return found


def create_groups(apps: Any, schema_editor: Any) -> None:
    # Permissions are normally created after all migrations, so create them now.
    for label in ("accounts", "economy", "progress"):
        app_config = apps.get_app_config(label)
        app_config.models_module = True
        create_permissions(app_config, apps=apps, verbosity=0)
        app_config.models_module = None

    group = apps.get_model("auth", "Group")
    support, _ = group.objects.get_or_create(name=SUPPORT)
    support.permissions.add(*_permissions(apps, SUPPORT_ADDS))
    ops, _ = group.objects.get_or_create(name=OPS)
    ops.permissions.set(_permissions(apps, SUPPORT_ADDS + OPS_ONLY))


def remove_groups(apps: Any, schema_editor: Any) -> None:
    group = apps.get_model("auth", "Group")
    group.objects.filter(name=OPS).delete()
    support = group.objects.filter(name=SUPPORT).first()
    if support is not None:
        support.permissions.remove(*_permissions(apps, SUPPORT_ADDS))


class Migration(migrations.Migration):
    dependencies = [
        ("economy", "0001_economy"),
        ("progress", "0001_progress"),
        ("accounts", "0006_name_filter_seed"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(create_groups, remove_groups)]
