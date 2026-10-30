"""The `content_author` group's permissions for M10's StoryRider (specs/015-m10-apartment-story).

A group's permissions are set when it is created (0003), so a model added later needs its own
grant, or the authoring inline is read-only and saves nothing.
"""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

RIDER_CODENAMES = ("add_storyrider", "change_storyrider", "delete_storyrider")
GROUP = "content_author"


def _ensure_permissions(apps: Any) -> None:
    """The model's permissions exist only after `post_migrate`, which runs after every migration."""
    app_config = apps.get_app_config("content")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None


def grant(apps: Any, schema_editor: Any) -> None:
    _ensure_permissions(apps)
    group_model = apps.get_model("auth", "Group")
    permission_model = apps.get_model("auth", "Permission")
    group = group_model.objects.filter(name=GROUP).first()
    if group is None:
        return
    permissions = permission_model.objects.filter(
        content_type__app_label="content", codename__in=RIDER_CODENAMES
    )
    group.permissions.add(*permissions)


def revoke(apps: Any, schema_editor: Any) -> None:
    group_model = apps.get_model("auth", "Group")
    permission_model = apps.get_model("auth", "Permission")
    group = group_model.objects.filter(name=GROUP).first()
    if group is None:
        return
    permissions = permission_model.objects.filter(
        content_type__app_label="content", codename__in=RIDER_CODENAMES
    )
    group.permissions.remove(*permissions)


class Migration(migrations.Migration):
    dependencies = [
        ("content", "0011_m10_story_fields"),
    ]

    operations = [migrations.RunPython(grant, revoke)]
