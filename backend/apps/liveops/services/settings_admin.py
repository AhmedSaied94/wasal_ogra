"""Every settings write: validated, attributed, locked and recorded (B10 research R14).

The admin and the `maintenance` command call these functions; nothing else saves a `LiveSetting`.
Each change and its `LiveopsChange` row are written in one transaction.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from django.db import transaction

from apps.accounts.models import User
from apps.liveops import registry, settings
from apps.liveops.models import LiveopsChange, LiveSetting


def change(
    key: str,
    value: Any,
    actor: User | None,
    note: str = "",
    source: str = LiveopsChange.Source.ADMIN,
) -> LiveSetting:
    """Change one setting. Raises `ValueError` with the contract's text when it is refused."""
    return change_many({key: value}, actor, note=note, source=source)[0]


def change_many(
    values: Mapping[str, Any],
    actor: User | None,
    note: str = "",
    source: str = LiveopsChange.Source.ADMIN,
) -> list[LiveSetting]:
    """Change several settings in one transaction, checking the rules once (contracts/settings.md).

    The rows of the changed keys and of every key that shares a rule with them are locked in key
    order, so two operators saving related keys are serialized and can't both pass a rule.
    """
    if not values:
        return []
    specs = {key: registry.get(key) for key in values}
    stored = {key: registry.validate(specs[key], raw) for key, raw in values.items()}
    with transaction.atomic():
        locked = _lock({key: specs[key] for key in values})
        candidate = dict(locked)
        for key, value in stored.items():
            candidate[key] = registry.typed(specs[key], value)
        registry.check_rules(candidate, set(values))
        rows = [_write(key, stored[key], actor, note, source) for key in values]
        transaction.on_commit(settings.refresh)
    return rows


def candidate_for(key: str, value: Any) -> dict[str, Any]:
    """The snapshot with one new value in it, as the rules would see it (no locks: the admin form).

    `change` re-checks the same rules under the row locks, so a race can't pass them.
    """
    spec = registry.get(key)
    keys = sorted(registry.rule_keys(key))
    stored = dict(LiveSetting.objects.filter(key__in=keys).values_list("key", "value"))
    values: dict[str, Any] = {}
    for other in keys:
        other_spec = registry.get(other)
        raw = stored.get(other, other_spec.default)
        try:
            values[other] = registry.typed(other_spec, registry.validate(other_spec, raw))
        except ValueError:
            values[other] = other_spec.default
    values[key] = registry.typed(spec, registry.validate(spec, value))
    return values


def reset(
    key: str,
    actor: User | None,
    note: str = "",
    source: str = LiveopsChange.Source.RESET,
) -> LiveSetting:
    """Write the registry's default as a `reset` change."""
    return change(key, registry.get(key).default, actor, note=note, source=source)


def _lock(specs: Mapping[str, registry.Spec]) -> dict[str, Any]:
    """Lock the rows the rules read, and return their typed current values in key order."""
    keys = sorted({key for key in specs for key in registry.rule_keys(key)})
    rows = {
        row.key: row.value
        for row in LiveSetting.objects.select_for_update().filter(key__in=keys).order_by("key")
    }
    locked: dict[str, Any] = {}
    for key in keys:
        spec = registry.get(key)
        raw = rows.get(key, spec.default)
        try:
            locked[key] = registry.typed(spec, registry.validate(spec, raw))
        except ValueError:
            locked[key] = spec.default
    return locked


def _write(
    key: str,
    value: Any,
    actor: User | None,
    note: str,
    source: str,
) -> LiveSetting:
    spec = registry.get(key)
    row, created = LiveSetting.objects.select_for_update().get_or_create(
        key=key, defaults={"value": value, "updated_by": actor}
    )
    if not created:
        old = row.value
        row.value = value
        row.updated_by = actor
        row.unused = False
        row.save(update_fields=("value", "updated_by", "unused", "updated_at"))
    else:
        old = spec.default
    LiveopsChange.objects.create(
        target=LiveopsChange.Target.SETTING,
        key=key,
        old=old,
        new=value,
        source=source,
        actor=actor,
        note=note,
    )
    return row
