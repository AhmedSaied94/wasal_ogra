"""System check `common.E001`: every project model has a UUIDv7 primary key (FR-016)."""

import uuid
from collections.abc import Sequence

from django.apps import AppConfig
from django.apps import apps as project_apps
from django.apps.registry import Apps
from django.core import checks
from django.core.management import call_command
from django.db import models
from django.test.utils import isolate_apps

from apps.common.models import UUIDv7Model


def uuid7_errors(app_configs: Sequence[AppConfig] | None = None) -> list[checks.CheckMessage]:
    return [e for e in checks.run_checks(app_configs=app_configs) if e.id == "common.E001"]


def errors_in(isolated: Apps | None) -> list[checks.CheckMessage]:
    assert isolated is not None
    return uuid7_errors(list(isolated.get_app_configs()))


def test_project_passes() -> None:
    assert uuid7_errors() == []
    call_command("check")  # raises SystemCheckError on any error


def test_framework_models_are_ignored() -> None:
    framework = [
        model
        for model in project_apps.get_models()
        if not model.__module__.startswith("apps.")
        and not isinstance(model._meta.pk, models.UUIDField)
    ]
    labels = {model._meta.app_label for model in framework}
    assert {"auth", "contenttypes", "sessions", "admin", "django_celery_beat"} <= labels
    assert uuid7_errors() == []


def test_autofield_model_is_reported() -> None:
    with isolate_apps("apps.common") as isolated:

        class Counter(models.Model):
            class Meta:
                app_label = "common"

        errors = errors_in(isolated)
    assert [e.obj for e in errors] == [Counter]
    assert "Counter" in errors[0].msg


def test_uuid4_primary_key_is_reported() -> None:
    with isolate_apps("apps.common") as isolated:

        class Token(models.Model):
            id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

            class Meta:
                app_label = "common"

        errors = errors_in(isolated)
    assert [e.obj for e in errors] == [Token]


def test_editable_uuid7_primary_key_is_reported() -> None:
    from apps.common.ids import uuid7

    with isolate_apps("apps.common") as isolated:

        class Loose(models.Model):
            id = models.UUIDField(primary_key=True, default=uuid7)

            class Meta:
                app_label = "common"

        errors = errors_in(isolated)
    assert [e.obj for e in errors] == [Loose]


def test_uuidv7_model_passes() -> None:
    with isolate_apps("apps.common") as isolated:

        class Good(UUIDv7Model):
            class Meta:
                app_label = "common"

        assert errors_in(isolated) == []


def test_a_one_to_one_key_to_a_uuidv7_model_passes() -> None:
    """A table keyed by its player holds the player's UUIDv7 (B03 data-model.md)."""
    with isolate_apps("apps.common") as isolated:

        class Owner(UUIDv7Model):
            class Meta:
                app_label = "common"

        class Keyed(models.Model):
            owner = models.OneToOneField(Owner, primary_key=True, on_delete=models.PROTECT)

            class Meta:
                app_label = "common"

        assert errors_in(isolated) == []


def test_a_one_to_one_key_to_another_kind_of_key_is_reported() -> None:
    with isolate_apps("apps.common") as isolated:

        class Plain(models.Model):
            class Meta:
                app_label = "common"

        class Keyed(models.Model):
            plain = models.OneToOneField(Plain, primary_key=True, on_delete=models.PROTECT)

            class Meta:
                app_label = "common"

        errors = errors_in(isolated)
    assert {e.obj for e in errors} == {Plain, Keyed}
