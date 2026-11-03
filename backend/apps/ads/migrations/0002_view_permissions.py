"""`live_ops` and `economy_ops` may view the ad rewards (B07 contracts/admin.md, research R14).
Nothing grants add, change or delete. The pattern of economy/0002."""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

GROUPS = ("live_ops", "economy_ops")


def _view(apps: Any) -> Any:
    # Permissions are normally created after all migrations, so create them now.
    app_config = apps.get_app_config("ads")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None
    return apps.get_model("auth", "Permission").objects.get(
        content_type__app_label="ads", codename="view_adreward"
    )


def grant(apps: Any, schema_editor: Any) -> None:
    view = _view(apps)
    for group in apps.get_model("auth", "Group").objects.filter(name__in=GROUPS):
        group.permissions.add(view)


def revoke(apps: Any, schema_editor: Any) -> None:
    view = _view(apps)
    for group in apps.get_model("auth", "Group").objects.filter(name__in=GROUPS):
        group.permissions.remove(view)


class Migration(migrations.Migration):
    dependencies = [
        ("ads", "0001_initial"),
        ("economy", "0002_groups"),
        ("liveops", "0003_group"),
    ]

    operations = [migrations.RunPython(grant, revoke)]
