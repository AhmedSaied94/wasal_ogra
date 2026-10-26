"""System check `common.E001`: every project model's primary key is the UUIDv7 id (FR-016).

A one-to-one primary key to a model whose own key passes counts too: a table keyed by its player
(B03's wallet, trip session and daily state) holds the player's UUIDv7.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from typing import Any

from django.apps import AppConfig, apps
from django.core.checks import CheckMessage, Error
from django.db import models

from apps.common.ids import uuid7

PROJECT_PREFIX = "apps."


def check_uuid7_primary_keys(
    app_configs: Sequence[AppConfig] | None = None, **kwargs: Any
) -> list[CheckMessage]:
    configs: Iterable[AppConfig] = (
        app_configs if app_configs is not None else apps.get_app_configs()
    )
    return [
        Error(
            f"{model._meta.label} must use a UUIDv7 primary key.",
            hint="Inherit from apps.common.models.UUIDv7Model.",
            obj=model,
            id="common.E001",
        )
        for config in configs
        for model in config.get_models()
        if model.__module__.startswith(PROJECT_PREFIX) and not _is_uuid7_pk(model._meta.pk)
    ]


def _is_uuid7_pk(field: models.Field[Any, Any] | None) -> bool:
    if isinstance(field, models.OneToOneField):
        target = field.related_model
        return not isinstance(target, str) and _is_uuid7_pk(target._meta.pk)
    return isinstance(field, models.UUIDField) and field.default is uuid7 and not field.editable
