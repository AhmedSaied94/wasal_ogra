"""The validation stages that need authoring data or B05 (contracts/content-schemas.md)."""

from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
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


REAL_SOLVER = "apps.content.services.solver_stage.SolverStage"
"""What `CONTENT_SOLVER_STAGE=solver` names (B05 contracts/content-pipeline.md §1)."""

Progress = Callable[[], None]


@dataclass(frozen=True)
class SolverOutput:
    """The stage's findings (`V-Z1` to `V-Z5`), one summary per trip in pack order, and `meta`:
    `solver_fingerprint`, `settings_version`, `solved` and `reused`."""

    findings: list[Finding]
    trips: list[dict[str, Any]] = field(default_factory=list)
    meta: dict[str, Any] = field(default_factory=dict)


class SolverStage(Protocol):
    """B05's stage. `run` returns its output, or `None` when it can't run (`not_available`).
    It calls `progress` after each trip, which keeps a running build from being swept."""

    def run(self, pack: Mapping[str, Any], progress: Progress) -> SolverOutput | None: ...


class NoSolver:
    """`CONTENT_SOLVER_STAGE=none`: reports `not_available`, which blocks publishing (FR-022)."""

    def run(self, pack: Mapping[str, Any], progress: Progress) -> SolverOutput | None:
        return None


class StandInSolver:
    """`CONTENT_SOLVER_STAGE=stand_in`, for dev and test only: passes every trip."""

    def run(self, pack: Mapping[str, Any], progress: Progress) -> SolverOutput | None:
        return SolverOutput([], [], {"stand_in": True})


def load_solver_stage() -> SolverStage:
    path = str(settings.CONTENT_SOLVER_STAGE)
    if path == "none":
        return NoSolver()
    if path == "stand_in":
        return StandInSolver()
    target = import_string(REAL_SOLVER if path == "solver" else path)
    stage: SolverStage = target() if isinstance(target, type) else target
    return stage
