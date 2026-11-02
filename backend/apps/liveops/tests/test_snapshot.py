"""The per-process snapshot (B10 research R3)."""

from __future__ import annotations

import logging
from datetime import timedelta

import pytest
import time_machine
from django.db import OperationalError
from django.utils import timezone
from pytest_django import DjangoAssertNumQueries

from apps.liveops import registry
from apps.liveops import settings as live
from apps.liveops.models import LiveSetting


@pytest.mark.django_db
def test_current_returns_typed_values() -> None:
    snapshot = live.current()
    assert snapshot["fuel_max"] == 5
    assert snapshot["trip_hints_mode_line_hay"] == "always"
    assert snapshot["maintenance_enabled"] is False
    assert snapshot["maintenance_until"] is None
    assert snapshot["min_client_version_android"] == "1.0.0"
    assert len(snapshot) == len(registry.SPECS)


@pytest.mark.django_db
def test_a_saved_change_is_seen_after_the_window_and_not_before() -> None:
    live.refresh()
    assert live.current()["fuel_overdraft_per_day"] == 2
    # Written behind the service, so nothing refreshes the snapshot.
    LiveSetting.objects.filter(key="fuel_overdraft_per_day").update(value=1)
    assert live.current()["fuel_overdraft_per_day"] == 2
    with time_machine.travel(timezone.now() + timedelta(seconds=31), tick=False):
        assert live.current()["fuel_overdraft_per_day"] == 1


@pytest.mark.django_db
def test_a_failed_read_keeps_the_last_snapshot(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    live.refresh()
    before = live.current()

    def boom() -> live.Snapshot:
        raise OperationalError("the database went away")

    monkeypatch.setattr(live._SETTINGS, "_load", boom)
    with caplog.at_level(logging.WARNING):
        after = live.refresh()
    assert after is before
    assert any(record.message == "liveops_snapshot_stale" for record in caplog.records)


@pytest.mark.django_db
def test_a_key_without_a_row_falls_back_to_its_default() -> None:
    LiveSetting.objects.filter(key="fuel_max").delete()
    live.refresh()
    assert live.current()["fuel_max"] == registry.get("fuel_max").default


@pytest.mark.django_db
def test_an_unknown_key_raises_key_error() -> None:
    with pytest.raises(KeyError):
        live.current()["fuel_maxx"]


@pytest.mark.django_db
def test_the_request_path_makes_no_query_when_the_snapshot_is_fresh(
    django_assert_num_queries: DjangoAssertNumQueries,
) -> None:
    live.refresh()
    with django_assert_num_queries(0):
        assert live.current()["fuel_max"] == 5


@pytest.mark.django_db
def test_the_snapshot_iterates_and_has_a_short_repr() -> None:
    snapshot = live.current()
    assert set(iter(snapshot)) == set(registry.SPECS)
    assert repr(snapshot) == f"Snapshot({len(registry.SPECS)} keys)"


def test_a_cache_that_never_loads_raises() -> None:
    def boom() -> object:
        raise OperationalError("the database went away")

    cache: live.Cache[object] = live.Cache(boom, "test")
    with pytest.raises(OperationalError):
        cache.current()


@pytest.mark.django_db
def test_an_unknown_row_key_is_skipped() -> None:
    LiveSetting.objects.create(key="ghost_key", value=1)
    live.refresh()
    assert "ghost_key" not in live.current()


@pytest.mark.django_db
def test_an_unparseable_stored_value_warns_and_uses_the_default(
    caplog: pytest.LogCaptureFixture,
) -> None:
    LiveSetting.objects.filter(key="fuel_max").update(value="many")
    with caplog.at_level(logging.WARNING):
        live.refresh()
    assert live.current()["fuel_max"] == 5
    assert any(record.message == "liveops_invalid_value" for record in caplog.records)
