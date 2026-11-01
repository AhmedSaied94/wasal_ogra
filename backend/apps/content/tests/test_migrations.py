"""Migrations that must run on a database that already holds content (T011, R1-1).

Every other migration test starts from an empty database, where adding a CHECK constraint is free.
Staging and production hold rows, so `0011` is proven here against one: it adds the slot columns
with `db_default=0` and must let the not-yet-authored `0` pass.
"""

from __future__ import annotations

from typing import Any

import pytest
from django.db import IntegrityError, connection, transaction
from django.db.migrations.executor import MigrationExecutor

from apps.content.models import Item

BEFORE = [("content", "0010_line_vehicle_display_fields")]


def _executor() -> MigrationExecutor:
    """A fresh executor: it re-reads the recorded migrations after a change."""
    return MigrationExecutor(connection)


def _latest(executor: MigrationExecutor) -> None:
    executor.migrate(executor.loader.graph.leaf_nodes())


@pytest.mark.django_db(transaction=True)
def test_0011_migrates_a_database_that_already_has_items() -> None:
    executor = _executor()
    executor.migrate(BEFORE)
    old: Any = executor.loader.project_state(BEFORE).apps
    chapter = old.get_model("content", "Chapter").objects.create(
        chapter_id="ch4_salon", order=4, title_ar_eg="title", goal_kind="purchase"
    )
    room = old.get_model("content", "Room").objects.create(
        room_id="salon", name_ar_eg="name", chapter_id=chapter.pk, order=1
    )
    item = old.get_model("content", "Item").objects.create(
        room_id=room.pk, slug="nish", name_ar_eg="name", order=1
    )

    try:
        _latest(_executor())

        stored = Item.objects.get(pk=item.pk)
        # The expansion's default, which the CHECK lets pass until the piece is authored.
        assert (stored.slot_x, stored.slot_y, stored.slot_w, stored.slot_h) == (0, 0, 0, 0)
        # The constraint still refuses a slot that is authored and too small.
        for slot in ({"slot_w": 10}, {"slot_h": 23}):
            with pytest.raises(IntegrityError), transaction.atomic():
                Item.objects.filter(pk=item.pk).update(**slot)
    finally:
        # Leave the test database at its latest migration for the rest of the suite.
        _latest(_executor())
