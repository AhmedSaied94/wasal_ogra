"""The one-time import of retired env variables, and the warning that names them (B10 R5)."""

from __future__ import annotations

import importlib
from typing import Any

import pytest
from django.apps import apps as django_apps

from apps.liveops import checks, registry
from apps.liveops import settings as live
from apps.liveops.models import LiveopsChange, LiveSetting

SEED = importlib.import_module("apps.liveops.migrations.0002_seed")


def seed() -> None:
    SEED.seed(django_apps, None)
    live.refresh()


@pytest.mark.django_db
def test_a_host_override_is_imported_once_per_affected_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ECONOMY_FUEL_OVERDRAFT_PER_DAY", "3")
    monkeypatch.setenv("CLIENT_MIN_VERSION", "1.1.0")
    seed()
    assert live.current()["fuel_overdraft_per_day"] == 3
    assert live.current()["min_client_version_android"] == "1.1.0"
    assert live.current()["min_client_version_ios"] == "1.1.0"
    changes = LiveopsChange.objects.filter(source=LiveopsChange.Source.IMPORT)
    assert {(change.key, change.new) for change in changes} == {
        ("fuel_overdraft_per_day", 3),
        ("min_client_version_android", "1.1.0"),
        ("min_client_version_ios", "1.1.0"),
    }
    assert all(change.actor is None for change in changes)
    assert all(change.note == "from env on migrate" for change in changes)
    assert all(change.old == registry.get(change.key).default for change in changes)


@pytest.mark.django_db
def test_a_default_equal_value_imports_nothing(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ECONOMY_FUEL_OVERDRAFT_PER_DAY", "2")
    seed()
    assert LiveSetting.objects.get(key="fuel_overdraft_per_day").value == 2
    assert not LiveopsChange.objects.filter(source=LiveopsChange.Source.IMPORT).exists()


@pytest.mark.django_db
def test_an_unparseable_value_is_ignored_with_a_warning(
    monkeypatch: pytest.MonkeyPatch, recwarn: Any
) -> None:
    monkeypatch.setenv("ECONOMY_FUEL_OVERDRAFT_PER_DAY", "many")
    seed()
    assert LiveSetting.objects.get(key="fuel_overdraft_per_day").value == 2
    assert not LiveopsChange.objects.filter(source=LiveopsChange.Source.IMPORT).exists()
    assert any("ECONOMY_FUEL_OVERDRAFT_PER_DAY is invalid" in str(w.message) for w in recwarn)


def test_w001_names_each_retired_variable_still_set(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in registry.RETIRED_ENV_VARIABLES:
        monkeypatch.delenv(name, raising=False)
    assert checks.retired_env_variables() == []
    monkeypatch.setenv("ECONOMY_FUEL_MAX", "5")
    monkeypatch.setenv("CLIENT_MIN_VERSION", "1.0.0")
    warnings = checks.retired_env_variables()
    assert {warning.id for warning in warnings} == {"liveops.W001"}
    named = {warning.obj for warning in warnings}
    assert named == {"ECONOMY_FUEL_MAX", "CLIENT_MIN_VERSION"}
    assert all(warning.msg.startswith(str(warning.obj)) for warning in warnings)
