"""The seed, the env import and the post-migrate hook (B10 research R2, R5)."""

from __future__ import annotations

from collections.abc import Callable

import pytest

from apps.liveops import registry
from apps.liveops import settings as live
from apps.liveops.apps import seed_registry_rows
from apps.liveops.models import LiveSetting
from apps.liveops.seed import sync_registry_rows


@pytest.mark.django_db
def test_every_registry_key_has_a_row_with_its_default() -> None:
    rows = dict(LiveSetting.objects.values_list("key", "value"))
    assert set(rows) == set(registry.SPECS)
    assert rows == registry.defaults()
    assert not LiveSetting.objects.filter(unused=True).exists()


@pytest.mark.django_db
def test_a_key_added_later_gets_a_row_from_the_hook() -> None:
    LiveSetting.objects.filter(key="fuel_max").delete()
    seed_registry_rows(None)
    assert LiveSetting.objects.get(key="fuel_max").value == 5


@pytest.mark.django_db
def test_a_dropped_key_is_marked_unused_and_never_read() -> None:
    LiveSetting.objects.create(key="retired_key", value=1)
    sync_registry_rows()
    assert LiveSetting.objects.get(key="retired_key").unused is True
    live.refresh()
    assert "retired_key" not in live.current()
    assert live.current()["fuel_max"] == 5


@pytest.mark.django_db
def test_a_row_marked_unused_is_revived_when_its_key_is_back(
    live_settings: Callable[..., None],
) -> None:
    live_settings(fuel_max=6)
    LiveSetting.objects.filter(key="fuel_max").update(unused=True)
    live.refresh()
    assert live.current()["fuel_max"] == 5  # the code default, while the row is hidden
    seed_registry_rows(None)
    row = LiveSetting.objects.get(key="fuel_max")
    assert (row.unused, row.value) == (False, 6)
    live.refresh()
    assert live.current()["fuel_max"] == 6
