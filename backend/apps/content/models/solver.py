"""Solver runs: one trip solved for a build or a preview (B05 data-model.md "SolverRun", R14).

A run is reused by `input_key`, whichever kind made it, but only when its status is `done`.
`finish_run` (services/solver_stage.py) stores a result that read the clock (`safety_cap`) or
came from a bug (`internal_error`) as `failed`, so it is never reused.
"""

from __future__ import annotations

from typing import ClassVar

from django.db import models
from django.db.models import Q

from apps.content.models.base import TimestampedModel


class SolverRun(TimestampedModel):
    """`updated_at` is the heartbeat the sweep reads (contracts/content-pipeline.md §5)."""

    class Kind(models.TextChoices):
        BUILD = "build"
        PREVIEW = "preview"

    class Status(models.TextChoices):
        QUEUED = "queued"
        RUNNING = "running"
        DONE = "done"
        FAILED = "failed"

    ACTIVE: ClassVar[tuple[str, ...]] = (Status.QUEUED, Status.RUNNING)
    FINISHED: ClassVar[tuple[str, ...]] = (Status.DONE, Status.FAILED)

    kind = models.CharField(max_length=16, choices=Kind.choices)
    status = models.CharField(max_length=16, choices=Status.choices)
    input_key = models.CharField(max_length=64, db_index=True)
    # The trip's identifier, such as `line_hay.01`. Not `trip_id`, which is the FK's column.
    trip_identifier = models.CharField(max_length=40)
    # Previews only. A deleted trip keeps its runs.
    trip = models.ForeignKey(
        "content.Trip",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="solver_runs",
    )
    # Previews only: a staff name, which never leaves the database.
    requested_by = models.CharField(max_length=150, blank=True)
    # A SolverResult, or {"findings": [...]} when the checks failed, or {"error": ...}.
    result = models.JSONField(default=dict, blank=True)
    finished_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(
                fields=["trip"],
                condition=Q(kind="preview", status__in=["queued", "running"]),
                name="solverrun_one_active_preview",
            ),
            models.CheckConstraint(
                condition=Q(status__in=["done", "failed"], finished_at__isnull=False)
                | Q(status__in=["queued", "running"], finished_at__isnull=True),
                name="solverrun_finished_has_time",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.kind} run of {self.trip_identifier} ({self.status})"
