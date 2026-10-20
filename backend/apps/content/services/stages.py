"""The validation stages that need authoring data or B05 (contracts/content-schemas.md)."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any, Protocol

from django.conf import settings
from django.utils.module_loading import import_string
from wassal_content.findings import Finding

from apps.content.services.snapshot import Snapshot


def review_stage(snapshot: Snapshot) -> list[Finding]:
    """`V-V1` for every speech line of the snapshot that nobody reviewed (FR-017)."""
    return [
        Finding(
            path=f"$.lines[{index}]",
            code="V-V1",
            message="this speech line isn't reviewed",
            stage="review",
            entity="speech_pool",
            id=speech_key,
        )
        for speech_key, index in snapshot.unreviewed
    ]


class SolverStage(Protocol):
    """B05's stage. `run` returns the findings, or `None` when it can't run (`not_available`)."""

    def run(self, pack: Mapping[str, Any]) -> list[Finding] | None: ...


class NoSolver:
    """`CONTENT_SOLVER_STAGE=none`: reports `not_available`, which blocks publishing (FR-022)."""

    def run(self, pack: Mapping[str, Any]) -> list[Finding] | None:
        return None


class StandInSolver:
    """`CONTENT_SOLVER_STAGE=stand_in`, for dev and test only: passes every trip."""

    def run(self, pack: Mapping[str, Any]) -> list[Finding] | None:
        return []


def load_solver_stage() -> SolverStage:
    path = str(settings.CONTENT_SOLVER_STAGE)
    if path == "none":
        return NoSolver()
    if path == "stand_in":
        return StandInSolver()
    target = import_string(path)
    stage: SolverStage = target() if isinstance(target, type) else target
    return stage
