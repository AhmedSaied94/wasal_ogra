"""Shared pytest fixtures. Tests run against the real PostgreSQL and Valkey (constitution XIII)."""

import os
from collections.abc import Iterator
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
