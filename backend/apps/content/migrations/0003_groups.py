"""The `content_author` and `content_publisher` groups (research R9)."""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

AUTHORING_MODELS = (
    "line",
    "station",
    "vehicle",
    "seat",
    "trip",
    "tripstation",
    "trippassenger",
    "tripevent",
    "chapter",
    "scene",
    "sceneline",
    "room",
    "item",
    "itemvariant",
    "familyrequest",
    "speechpool",
    "speechline",
    "catalogprice",
    "dailyrewardday",
    "tasktemplate",
)
GROUPS = {
    "content_author": [
        *(
            f"{action}_{model}"
            for model in AUTHORING_MODELS
            for action in ("add", "change", "delete")
        ),
        "import_content",
        "export_content",
        "build_pack",
        "review_speech",
    ],
    "content_publisher": [
        "publish_pack",
        "rollback_pack",
        "promote_pack",
        "change_min_client_version",
    ],
}


def create_groups(apps: Any, schema_editor: Any) -> None:
    # Permissions are normally created after all migrations, so create them now.
    app_config = apps.get_app_config("content")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None

    group_model = apps.get_model("auth", "Group")
    permission_model = apps.get_model("auth", "Permission")
    for name, codenames in GROUPS.items():
        group, _ = group_model.objects.get_or_create(name=name)
        permissions = permission_model.objects.filter(
            content_type__app_label="content", codename__in=codenames
        )
        if permissions.count() != len(codenames):
            raise RuntimeError(f"{name}: a content permission is missing")
        group.permissions.set(permissions)


def remove_groups(apps: Any, schema_editor: Any) -> None:
    apps.get_model("auth", "Group").objects.filter(name__in=GROUPS).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("content", "0002_current_pack_check"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(create_groups, remove_groups)]
