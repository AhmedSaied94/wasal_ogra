"""Seed every registry key with its default, then import a host's env overrides once (B10 R2, R5).

The deploy must not change behaviour: a retired variable that parses, is in range and differs from
the default becomes the live value, with one `import` change naming it. After this migration the
variables are never read (the `liveops.W001` check only names the ones still set so the host can
drop them).
"""

from __future__ import annotations

import os
import warnings
from typing import Any

from django.db import migrations

from apps.liveops import registry


def seed(apps: Any, schema_editor: Any) -> None:
    setting = apps.get_model("liveops", "LiveSetting")
    change = apps.get_model("liveops", "LiveopsChange")
    for spec in registry.SPECS.values():
        setting.objects.get_or_create(
            key=spec.key, defaults={"value": registry.validate(spec, spec.default)}
        )
    _import_env(setting, change)


def unseed(apps: Any, schema_editor: Any) -> None:
    setting = apps.get_model("liveops", "LiveSetting")
    change = apps.get_model("liveops", "LiveopsChange")
    setting.objects.filter(key__in=list(registry.SPECS)).delete()
    change.objects.filter(target="setting", source="import").delete()


def _import_env(setting: Any, change: Any) -> None:
    for name, keys in registry.ENV_IMPORTS:
        raw = os.environ.get(name)
        if not raw:
            continue
        for key in keys:
            spec = registry.get(key)
            try:
                value = registry.validate(spec, _parse(spec, raw))
            except ValueError:
                warnings.warn(
                    f"liveops: {name} is invalid and was not imported into {key}", stacklevel=1
                )
                continue
            if value == registry.validate(spec, spec.default):
                continue
            row = setting.objects.get(key=key)
            old, row.value = row.value, value
            row.save(update_fields=("value",))
            change.objects.create(
                target="setting",
                key=key,
                old=old,
                new=value,
                source="import",
                actor=None,
                note=registry.IMPORT_NOTE,
            )


def _parse(spec: registry.Spec, raw: str) -> Any:
    if spec.kind == registry.INT:
        return int(raw)
    return raw


class Migration(migrations.Migration):
    dependencies = [("liveops", "0001_initial")]

    operations = [migrations.RunPython(seed, unseed)]
