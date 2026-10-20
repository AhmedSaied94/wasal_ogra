"""`content.published_packs_intact` (tasks.md T056, data-model "Invariants")."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import psycopg
import pytest
from django.db import connection
from django.db.models import F

from apps.common.services import invariants
from apps.common.services.backups import Database
from apps.content.invariants import published_packs_intact
from apps.content.models import ContentPack
from apps.content.models.packs import Status
from apps.content.tests import factories as make

# The check reads through its own connection, as the drill does, so the rows must be committed.
pytestmark = pytest.mark.django_db(transaction=True)


@pytest.fixture
def conn() -> Iterator[psycopg.Connection[Any]]:
    with psycopg.connect(**Database.from_settings(connection.settings_dict).connect_kwargs()) as c:
        yield c


def test_it_is_registered_for_the_drill() -> None:
    assert invariants.registered()["content.published_packs_intact"] is published_packs_intact


def test_intact_packs_pass(conn: psycopg.Connection[Any]) -> None:
    make.pack(1, Status.RETIRED)
    make.pack(2, Status.PUBLISHED)
    make.pack(3, Status.VALIDATED)

    assert published_packs_intact(conn) == (True, "2 published or retired packs intact")


def test_an_empty_database_passes(conn: psycopg.Connection[Any]) -> None:
    assert published_packs_intact(conn) == (True, "0 published or retired packs intact")


@pytest.mark.parametrize(
    "tamper", [{"size": F("size") + 1}, {"file": b"tampered"}, {"sha256": "0" * 64}]
)
def test_a_tampered_pack_fails(conn: psycopg.Connection[Any], tamper: dict[str, Any]) -> None:
    make.pack(1, Status.PUBLISHED)
    second = make.pack(2, Status.PUBLISHED)
    ContentPack.objects.filter(pk=second.pk).update(**tamper)  # bypasses save(), as tampering would

    assert published_packs_intact(conn) == (
        False,
        "1 of 2 packs don't match their sha256 or size: core-2",
    )


def test_drafts_are_not_checked(conn: psycopg.Connection[Any]) -> None:
    draft = make.pack(1)
    ContentPack.objects.filter(pk=draft.pk).update(size=0)

    assert published_packs_intact(conn)[0] is True
