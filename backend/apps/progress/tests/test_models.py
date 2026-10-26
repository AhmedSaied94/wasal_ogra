"""The progress tables' constraints (B03 data-model.md "progress")."""

from __future__ import annotations

import uuid

import pytest
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.accounts.models import Player
from apps.accounts.tests.factories import make_player
from apps.progress.models import (
    DailyState,
    Ownership,
    StoryState,
    TripProgress,
    TripRun,
    TripSession,
)

pytestmark = pytest.mark.django_db


@pytest.fixture
def player(db: None) -> Player:
    return make_player()


def refused(make: object) -> None:
    with pytest.raises(IntegrityError), transaction.atomic():
        make()  # type: ignore[operator]


def test_trip_progress_is_unique_and_stars_are_0_to_3(player: Player) -> None:
    TripProgress.objects.create(player=player, trip_id="line_hay.01", best_stars=3)
    refused(lambda: TripProgress.objects.create(player=player, trip_id="line_hay.01"))
    refused(lambda: TripProgress.objects.create(player=player, trip_id="line_hay.02", best_stars=4))


def test_a_run_is_one_per_start_and_indexed(player: Player) -> None:
    start = uuid.uuid4()

    def make() -> TripRun:
        return TripRun.objects.create(
            player=player,
            trip_id="line_hay.01",
            rev=1,
            start_op=start,
            outcome="finished",
            content_version=1,
        )

    make()
    refused(make)
    names = {index.name for index in TripRun._meta.indexes}
    assert names == {"trip_run_prune", "trip_run_by_player"}


def test_ownership_and_story_are_unique(player: Player) -> None:
    now = timezone.now()
    Ownership.objects.create(player=player, kind="item", sku_id="salon.nish", acquired_at=now)
    refused(
        lambda: Ownership.objects.create(
            player=player, kind="item", sku_id="salon.nish", acquired_at=now
        )
    )
    StoryState.objects.create(player=player, chapter_id="ch1_first_job", scenes_seen=["the_stand"])
    refused(lambda: StoryState.objects.create(player=player, chapter_id="ch1_first_job"))
    assert StoryState.objects.get(player=player).scenes_seen == ["the_stand"]


def test_the_session_and_the_daily_state_are_one_row_per_player(player: Player) -> None:
    TripSession.objects.create(player=player)
    refused(lambda: TripSession.objects.create(player=player))
    DailyState.objects.create(player=player)
    refused(lambda: DailyState.objects.create(player=player))
    assert TripSession._meta.pk is not None
    assert TripSession._meta.pk.name == "player"
    assert DailyState._meta.pk is not None
    assert DailyState._meta.pk.name == "player"


def test_string_forms(player: Player) -> None:
    assert str(TripProgress(trip_id="line_hay.01", best_stars=2)) == "line_hay.01: 2★"
    assert str(TripRun(trip_id="line_hay.01", outcome="failed")) == "line_hay.01 failed"
    assert str(Ownership(kind="vehicle", sku_id="micro_old")) == "vehicle micro_old"
    assert str(StoryState(chapter_id="ch1_first_job", status="open")) == "ch1_first_job open"
    assert str(TripSession(player=player)).startswith("trip session")
    assert str(DailyState(player=player)).startswith("daily state")
