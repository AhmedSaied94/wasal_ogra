"""Pack validation: the stages of FR-021 that need no authoring data.

Each stage adds its findings to one report. The `review` and `solver` stages need authoring data
or B05, so they run in `backend/apps/content`.
"""

from __future__ import annotations

from typing import Any

from wassal_content.findings import Finding, Report
from wassal_content.schemas import SchemaSet, default_schema_set

__all__ = ["SIZE_WARNING_BYTES", "validate_pack"]

# Mobile §19's budget: a pack over 2 MiB compressed is a warning, not an error (V-S1).
SIZE_WARNING_BYTES = 2_097_152


def _size_findings(file_size: int) -> list[Finding]:
    if file_size <= SIZE_WARNING_BYTES:
        return []
    return [
        Finding(
            path="$",
            code="V-S1",
            message=f"the pack file is {file_size} bytes, over the {SIZE_WARNING_BYTES} budget",
            stage="size",
            severity="warning",
            entity="pack",
            id="core",
        )
    ]


def validate_pack(
    pack: Any, *, file_size: int | None, schema_set: SchemaSet | None = None
) -> Report:
    """Run the schema stage and, when the pack file's size is known, the size stage."""
    schemas = schema_set or default_schema_set()
    report = Report()
    report.add_stage("schema", schemas.validate_document("pack", pack))
    if file_size is not None:
        report.add_stage("size", _size_findings(file_size))
    return report
