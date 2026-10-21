"""What a solve returns (data-model.md "SolverResult", contracts/solver.md §1 and §4)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import TYPE_CHECKING

from wassal_solver.engine.commands import LoggedCommand, command_log_hash
from wassal_solver.engine.validation import Refusal
from wassal_solver.solver.search import End
from wassal_solver.solver.timeline import Loss, TimelineEntry

if TYPE_CHECKING:
    from wassal_solver.scoring.difficulty import Score

__all__ = ["SolverResult", "Verdict"]


class Verdict(StrEnum):
    SOLVED = "solved"
    NOT_SOLVED = "not_solved"
    REFUSED = "refused"


@dataclass(frozen=True, slots=True)
class SolverResult:
    """One trip's verdict, its run or best run, and what made it."""

    trip_id: str
    rev: int
    verdict: Verdict
    end: End
    stars: int
    """Of the run, or of the best run; 0 without either."""
    run: tuple[LoggedCommand, ...] | None
    """The 3-star run, when solved."""
    best_run: tuple[LoggedCommand, ...] | None
    """When not solved and some branch was played to its end."""
    first_loss: Loss | None
    timeline: tuple[TimelineEntry, ...]
    score: Score | None
    """When solved."""
    refusals: tuple[Refusal, ...] | None
    """When refused."""
    effort_steps: int
    settings_version: str
    solver_fingerprint: str
    params_fingerprint: str

    @property
    def solved(self) -> bool:
        return self.verdict is Verdict.SOLVED

    @property
    def run_hash(self) -> str | None:
        """The fingerprint of the run, or of the best run (M01 research R9)."""
        log = self.run if self.run is not None else self.best_run
        return None if log is None else command_log_hash(log)

    def to_json(self) -> dict[str, object]:
        """The canonical-ready form; absent fields are left out."""
        out: dict[str, object] = {
            "trip_id": self.trip_id,
            "rev": self.rev,
            "verdict": self.verdict.value,
            "end": self.end.value,
            "stars": self.stars,
        }
        if self.run is not None:
            out["run"] = [entry.to_json() for entry in self.run]
        if self.best_run is not None:
            out["best_run"] = [entry.to_json() for entry in self.best_run]
        run_hash = self.run_hash
        if run_hash is not None:
            out["run_hash"] = run_hash
        if self.first_loss is not None:
            out["first_loss"] = self.first_loss.to_json()
        out["timeline"] = [entry.to_json() for entry in self.timeline]
        if self.score is not None:
            out["score"] = self.score.to_json()
        if self.refusals is not None:
            out["refusals"] = [refusal.to_json() for refusal in self.refusals]
        out["effort_steps"] = self.effort_steps
        out["settings_version"] = self.settings_version
        out["solver_fingerprint"] = self.solver_fingerprint
        out["params_fingerprint"] = self.params_fingerprint
        return out
