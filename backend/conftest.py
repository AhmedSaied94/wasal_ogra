"""Shared pytest fixtures. Tests run against the real PostgreSQL and Valkey (constitution XIII)."""

import os
from collections.abc import Callable, Iterator
from pathlib import Path

import pytest
from django.conf import settings
from django.core.cache import cache
from hypothesis import HealthCheck
from hypothesis import settings as hypothesis_settings
from pytest_django import Settings

# Property tests run 300 examples in the normal run, and 10,000 once before merge with
# HYPOTHESIS_PROFILE=thorough (B02 research R15, SC-006).
hypothesis_settings.register_profile(
    "ci", max_examples=300, deadline=None, suppress_health_check=[HealthCheck.too_slow]
)
hypothesis_settings.register_profile(
    "thorough", max_examples=10_000, deadline=None, suppress_health_check=[HealthCheck.too_slow]
)
hypothesis_settings.load_profile(os.environ.get("HYPOTHESIS_PROFILE", "ci"))


@pytest.fixture(autouse=True, scope="session")
def _packs_dir_exists() -> None:
    """A worker started by a test checks CONTENT_PACKS_DIR (B04). Tests that write packs get
    their own directory from the content `packs_dir` fixture."""
    Path(settings.CONTENT_PACKS_DIR).mkdir(parents=True, exist_ok=True)


@pytest.fixture(autouse=True)
def _clear_cache() -> Iterator[None]:
    """Every test starts with an empty cache, so throttle counters never leak between tests."""
    cache.clear()
    yield
    cache.clear()


@pytest.fixture
def no_throttle(settings: Settings) -> None:
    """Turn off every limit. The throttles read these settings on every request."""
    settings.THROTTLE_ADDRESS_RATE = None
    settings.THROTTLE_PLAYER_RATE = None
    settings.THROTTLE_ANONYMOUS_RATE = None
    settings.THROTTLE_REFRESH_RATE = None
    settings.THROTTLE_LINK_RATE = None
    settings.THROTTLE_SYNC_RATE = None


@pytest.fixture(autouse=True)
def _fresh_liveops_snapshot() -> Iterator[None]:
    """A process-wide snapshot must not leak a value between tests (B10 research R3)."""
    from apps.liveops import settings as live

    live.reset()
    yield
    live.reset()


@pytest.fixture
def live_settings(db: None) -> Iterator[Callable[..., None]]:
    """`live_settings(fuel_overdraft_per_day=1)`: write live values for one test (B10 R4, T013).

    The rows are written through the service, so the rule checks and the history run as in
    production, and the process snapshot is refreshed; the defaults come back after the test.
    """
    from apps.accounts.models import User
    from apps.liveops import registry
    from apps.liveops import settings as live
    from apps.liveops.models import LiveopsChange
    from apps.liveops.services import settings_admin

    actor = User.objects.get_or_create(username="live-ops-tests", defaults={"is_staff": True})[0]
    changed: list[str] = []
    live.refresh()

    def apply(**values: object) -> None:
        settings_admin.change_many(values, actor, note="test")
        changed.extend(key for key in values if key not in changed)
        live.refresh()

    yield apply

    if changed:
        # Reset the keys a rule shares too, so a pair goes back together.
        keys = {other for key in changed for other in registry.rule_keys(key)}
        settings_admin.change_many(
            {key: registry.get(key).default for key in keys},
            actor,
            note="test teardown",
            source=LiveopsChange.Source.RESET,
        )
    live.refresh()
