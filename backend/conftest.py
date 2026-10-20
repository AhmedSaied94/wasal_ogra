"""Shared pytest fixtures. Tests run against the real PostgreSQL and Valkey (constitution XIII)."""

from collections.abc import Iterator
from pathlib import Path

import pytest
from django.conf import settings
from django.core.cache import cache
from pytest_django import Settings


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
    """Turn off the per-address limit. The throttle reads this setting on every request."""
    settings.THROTTLE_ADDRESS_RATE = None
