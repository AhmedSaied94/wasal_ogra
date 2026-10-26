"""The progress tables (B03 data-model.md "progress").

This app holds data and the unlock rules, and imports nothing from `economy`: the operation
handlers there write these rows through the batch (research R1, R5).
"""

from __future__ import annotations

from django.contrib.postgres.fields import ArrayField
from django.db import models
from django.db.models import Q

from apps.accounts.models import Player
from apps.common.models import UUIDv7Model


class TripProgress(UUIDv7Model):
    """Per player and trip. The bests are of finished results; `plays` counts every result."""

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="trip_progress")
    trip_id = models.CharField(max_length=40)
    best_stars = models.PositiveSmallIntegerField(default=0)
    best_time_ms = models.PositiveBigIntegerField(null=True, blank=True)
    plays = models.PositiveIntegerField(default=0)
    first_completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "trip progress"
        constraints = (
            models.UniqueConstraint(fields=("player", "trip_id"), name="trip_progress_once"),
            models.CheckConstraint(
                condition=Q(best_stars__gte=0, best_stars__lte=3), name="trip_progress_stars_0_3"
            ),
        )

    def __str__(self) -> str:
        return f"{self.trip_id}: {self.best_stars}★"


class TripRun(UUIDv7Model):
    """One played trip, kept 90 days (research R12)."""

    class Outcome(models.TextChoices):
        FINISHED = "finished"
        FAILED = "failed"
        ABANDONED = "abandoned"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="trip_runs")
    trip_id = models.CharField(max_length=40)
    rev = models.PositiveIntegerField()
    start_op = models.UUIDField()
    outcome = models.CharField(max_length=16, choices=Outcome.choices)
    stars = models.PositiveSmallIntegerField(default=0)
    fights = models.PositiveIntegerField(default=0)
    mistakes_count = models.PositiveIntegerField(default=0)
    earnings_jenehat = models.PositiveIntegerField(default=0)
    duration_ms = models.PositiveBigIntegerField(default=0)
    revived = models.BooleanField(default=False)
    boosters_used = models.JSONField(default=list, blank=True)
    command_log_hash = models.CharField(max_length=64, blank=True)
    content_version = models.PositiveIntegerField()
    client_version = models.CharField(max_length=32, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = (
            models.Index(fields=("created_at",), name="trip_run_prune"),
            models.Index(fields=("player", "created_at"), name="trip_run_by_player"),
        )
        constraints = (
            models.UniqueConstraint(fields=("player", "start_op"), name="trip_run_one_per_start"),
        )

    def __str__(self) -> str:
        return f"{self.trip_id} {self.outcome}"


class TripSession(models.Model):
    """One row per player: the open trip and the last result (mirrors M05's `trip_session`)."""

    player = models.OneToOneField(
        Player, primary_key=True, on_delete=models.PROTECT, related_name="trip_session"
    )
    # The accepted start with no result yet, copied from the pack at the start, so the result is
    # checked against what the phone was shown.
    open_start = models.UUIDField(null=True, blank=True)
    open_trip_id = models.CharField(max_length=40, blank=True)
    open_rev = models.PositiveIntegerField(default=0)
    open_content_version = models.PositiveIntegerField(default=0)
    open_max_earnings = models.PositiveIntegerField(default=0)
    open_last_station_ms = models.PositiveBigIntegerField(default=0)
    open_started_at = models.DateTimeField(null=True, blank=True)
    open_revived = models.BooleanField(default=False)
    open_traffic_jam_ads = models.PositiveSmallIntegerField(default=0)
    # The start whose result came last, for `result_double`.
    last_start = models.UUIDField(null=True, blank=True)
    last_outcome = models.CharField(max_length=16, blank=True)
    last_earnings = models.PositiveIntegerField(default=0)
    last_doubled = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"trip session {self.player_id}"


class Ownership(UUIDv7Model):
    class Kind(models.TextChoices):
        VEHICLE = "vehicle"
        UPGRADE = "upgrade"
        COSMETIC = "cosmetic"
        ITEM = "item"
        CHAPTER = "chapter"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="ownership")
    kind = models.CharField(max_length=16, choices=Kind.choices)
    sku_id = models.CharField(max_length=64)
    variant = models.CharField(max_length=32, blank=True)
    acquired_at = models.DateTimeField()
    acquired_by = models.UUIDField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name_plural = "ownership"
        constraints = (
            models.UniqueConstraint(fields=("player", "kind", "sku_id"), name="ownership_once"),
        )

    def __str__(self) -> str:
        return f"{self.kind} {self.sku_id}"


class StoryState(UUIDv7Model):
    """Per player and chapter. Family requests claimed are grant records, not columns here."""

    class Status(models.TextChoices):
        OPEN = "open"
        COMPLETED = "completed"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="story")
    chapter_id = models.CharField(max_length=32)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.OPEN)
    scenes_seen = ArrayField(models.CharField(max_length=32), default=list, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "story state"
        constraints = (
            models.UniqueConstraint(fields=("player", "chapter_id"), name="story_state_once"),
        )

    def __str__(self) -> str:
        return f"{self.chapter_id} {self.status}"


class DailyState(models.Model):
    """One row per player, created with the first bootstrap. B03 reads it; B08 and M13 write it."""

    player = models.OneToOneField(
        Player, primary_key=True, on_delete=models.PROTECT, related_name="daily_state"
    )
    streak = models.PositiveIntegerField(default=0)
    longest_streak = models.PositiveIntegerField(default=0)
    last_claim_game_date = models.DateField(null=True, blank=True)
    task_counters = models.JSONField(default=dict, blank=True)
    tasks_game_date = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"daily state {self.player_id}"
