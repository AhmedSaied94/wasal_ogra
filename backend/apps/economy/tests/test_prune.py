"""The daily prune (B03 tasks.md T085, spec FR-043, research R11, R12)."""

from __future__ import annotations

import uuid
from datetime import timedelta

import pytest
from django.utils import timezone
from django_celery_beat.models import PeriodicTask
from pytest_django import Settings

from apps.accounts.models import Player
from apps.economy import tasks
from apps.economy.models import Currency, DayCounter, Inventory, LedgerEntry, ProcessedOp
from apps.economy.services.gameday import game_date
from apps.economy.tests.helpers import grant, op, reasons, run, spend, trip_start, uuid7_at
from apps.progress.models import Ownership, TripProgress, TripRun

pytestmark = pytest.mark.django_db


def processed(player: Player, days_ago: float) -> ProcessedOp:
    return ProcessedOp.objects.create(
        player=player,
        client_txn_id=uuid.uuid4(),
        op_type="trip_start",
        payload_hash="0" * 64,
        status="accepted",
        processed_at=timezone.now() - timedelta(days=days_ago),
    )


def trip_run(player: Player, days_ago: int) -> TripRun:
    row = TripRun.objects.create(
        player=player,
        trip_id="line_hay.01",
        rev=1,
        start_op=uuid.uuid4(),
        outcome="finished",
        content_version=1,
    )
    TripRun.objects.filter(pk=row.pk).update(created_at=timezone.now() - timedelta(days=days_ago))
    return row


def counter(player: Player, days_ago: int) -> DayCounter:
    return DayCounter.objects.create(
        player=player,
        game_date=game_date(timezone.now()) - timedelta(days=days_ago),
        kind="trips_started",
        count=1,
    )


def test_old_rows_go_and_the_rest_stays(
    player: Player, published_pack: int, settings: Settings
) -> None:
    assert settings.SYNC_OP_RETENTION_DAYS == 180
    grant(player, Currency.BONAT, 50)
    run(player, trip_start("line_hay.01", published_pack))
    run(player, spend("booster", "wake_all", 8, published_pack))
    old = [processed(player, 182), trip_run(player, 91), counter(player, 41)]
    kept = [processed(player, 180), trip_run(player, 89), counter(player, 39)]
    lasting = (
        LedgerEntry.objects.count(),
        TripProgress.objects.count(),
        Ownership.objects.count(),
        Inventory.objects.count(),
    )

    deleted = tasks.prune.apply().get()

    assert deleted == {"processed_ops": 1, "trip_runs": 1, "day_counters": 1}
    for row in old:
        assert not type(row)._default_manager.filter(pk=row.pk).exists()
    for row in kept:
        assert type(row)._default_manager.filter(pk=row.pk).exists()
    assert lasting == (
        LedgerEntry.objects.count(),
        TripProgress.objects.count(),
        Ownership.objects.count(),
        Inventory.objects.count(),
    )


def test_an_operation_is_kept_a_day_past_the_retention(player: Player) -> None:
    """An id dated a day ahead is `op_expired` only a day after the retention: until then its
    row must stay, or it could apply again (security review L1)."""
    row = processed(player, 180.5)  # past the retention, inside the margin
    tasks.prune.apply().get()
    assert ProcessedOp.objects.filter(pk=row.pk).exists()


def test_trip_runs_go_in_chunks(player: Player, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tasks, "CHUNK", 2)
    for _ in range(5):
        trip_run(player, 100)
    assert tasks.prune.apply().get()["trip_runs"] == 5
    assert not TripRun.objects.exists()


def test_a_pruned_operation_sent_again_is_op_expired(player: Player, published_pack: int) -> None:
    at = timezone.now() - timedelta(days=182)
    envelope = op(
        "trip_start",
        {"trip_id": "line_hay.01", "content_version": published_pack, "fuel_mode": "fuel"},
        txn=uuid7_at(at),
    )
    ProcessedOp.objects.create(
        player=player,
        client_txn_id=uuid.UUID(envelope["client_txn_id"]),
        op_type="trip_start",
        payload_hash="0" * 64,
        status="accepted",
        processed_at=at,
    )
    tasks.prune.apply().get()
    assert not ProcessedOp.objects.filter(client_txn_id=envelope["client_txn_id"]).exists()
    assert reasons(run(player, envelope)) == ["op_expired"]


def test_the_task_retries_and_is_scheduled() -> None:
    assert tasks.prune.name == "economy.tasks.prune"
    assert tasks.prune.max_retries == 3
    task = PeriodicTask.objects.select_related("crontab").get(name="economy.prune")
    assert task.task == "economy.tasks.prune"
    assert task.enabled
    assert (task.crontab.hour, task.crontab.minute, str(task.crontab.timezone)) == (
        "4",
        "45",
        "Africa/Cairo",
    )
