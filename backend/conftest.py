"""Shared pytest fixtures. Tests run against the real PostgreSQL and Valkey (constitution XIII)."""

from collections.abc import Iterator

import pytest
from django.core.cache import cache
from pytest_django import Settings


@pytest.fixture(autouse=True)
def _clear_cache() -> Iterator[None]:
    """Every test starts with an empty cache, so throttle counters never leak between tests."""
    cache.clear()
    yield
    cache.clear()


@pytest.fixture
def no_throttle(settings: Settings) -> None:
    """Turn off the per-address limit. The throttle reads this setting on every request."""
    settings.THROTTLE_ADDRESS_RATE = None
