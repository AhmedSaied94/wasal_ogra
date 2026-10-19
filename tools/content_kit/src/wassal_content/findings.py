"""Validation findings and reports (contracts/admin.md "Validation report")."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Literal

__all__ = ["SEVERITIES", "STAGES", "Finding", "Report", "StageResult"]

Severity = Literal["error", "warning"]
StageResult = Literal["passed", "warning", "failed", "not_available"]

SEVERITIES: tuple[Severity, ...] = ("error", "warning")
STAGES = ("schema", "references", "content_rules", "review", "solver", "size")


@dataclass(frozen=True, order=True)
class Finding:
    """One problem: where it is (entity, identifier, JSON path) and what it is.

    `code` is stable, so tests and the admin can name it: `V-SC` for a schema violation, `V-JS` for
    a document that isn't strict JSON, `V-LY` for a file outside the `content/source` layout, and
    the rule codes of contracts/content-schemas.md for the rest. `file` is set when the finding
    comes from one file of a layout.
    """

    path: str
    code: str
    message: str
    stage: str = "schema"
    severity: Severity = "error"
    entity: str = ""
    id: str = ""
    file: str | None = None

    def to_dict(self) -> dict[str, str]:
        """The finding as JSON, without an empty `file`."""
        data = {key: value for key, value in asdict(self).items() if value is not None}
        return {key: str(value) for key, value in data.items()}


@dataclass
class Report:
    """The result of every stage, and the findings."""

    stages: dict[str, StageResult] = field(default_factory=dict)
    findings: list[Finding] = field(default_factory=list)

    @property
    def errors(self) -> list[Finding]:
        return [finding for finding in self.findings if finding.severity == "error"]

    @property
    def passed(self) -> bool:
        """True when no stage failed: warnings don't block (FR-022)."""
        return all(result in ("passed", "warning") for result in self.stages.values())

    def add_stage(self, stage: str, findings: list[Finding]) -> None:
        """Record one stage's findings and derive its result."""
        self.findings.extend(sorted(findings))
        if any(finding.severity == "error" for finding in findings):
            self.stages[stage] = "failed"
        elif findings:
            self.stages[stage] = "warning"
        else:
            self.stages[stage] = "passed"

    def to_dict(self) -> dict[str, object]:
        return {
            "stages": {stage: {"result": result} for stage, result in self.stages.items()},
            "findings": [finding.to_dict() for finding in self.findings],
        }
