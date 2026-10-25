"""Fixtures for the economy tests (B03 tasks.md T005).

Pack data comes from B04's real publish path: the sample pack, built and published as the content
tests do it. Players come from B02's real sign-in.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from pathlib import Path

import pytest

from apps.accounts.models import Player, User
from apps.accounts.services import players
from apps.accounts.tests.factories import CLIENT
from apps.content.models import ContentPack
from apps.content.tests.conftest import (
    author,
    channel,
    packs_dir,
    publisher,
    sample_imported,
    sample_reviewed,
)
from apps.content.tests.test_build import built
from apps.content.tests.test_publish import published
from apps.economy.tests.helpers import Api, signed_in_api

__all__ = ["author", "channel", "packs_dir", "publisher", "sample_imported", "sample_reviewed"]


@pytest.fixture
def published_packs(
    sample_reviewed: User, publisher: User, packs_dir: Path
) -> Callable[[int], list[int]]:
    """Publish the sample `n` more times; returns the new versions."""

    def publish(n: int = 1) -> list[int]:
        packs: list[ContentPack] = [published(built(sample_reviewed), publisher) for _ in range(n)]
        return [pack.version or 0 for pack in packs]

    return publish


@pytest.fixture
def published_pack(published_packs: Callable[[int], list[int]]) -> int:
    """The sample pack, published once. Its version (1)."""
    return published_packs(1)[0]


@pytest.fixture
def player(db: None) -> Player:
    issued, _ = players.create_or_return(uuid.uuid4(), "android", "ar-EG", client=CLIENT)
    return Player.objects.get(pk=issued.player_id)


@pytest.fixture
def api(db: None) -> Api:
    return signed_in_api()
