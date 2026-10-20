"""Pack validation: the stages of FR-021 that need no authoring data.

The stages are `schema`, `references`, `content_rules` and, when the pack file's size is known,
`size`. The rules assume the schema's shapes, so when the schema stage fails they report
`not_available` instead of running. The `review` and `solver` stages need authoring data or B05,
so they run in `backend/apps/content`.
"""

from __future__ import annotations

from typing import Any

from wassal_content.findings import Report
from wassal_content.rules import (
    SIZE_WARNING_BYTES,
    content_rule_findings,
    reference_findings,
    size_findings,
)
from wassal_content.schemas import SchemaSet, default_schema_set

__all__ = ["SIZE_WARNING_BYTES", "validate_pack"]


def validate_pack(
    pack: Any, *, file_size: int | None, schema_set: SchemaSet | None = None
) -> Report:
    """Run every stage that works on the pack alone, and report each one's result."""
    schemas = schema_set or default_schema_set()
    report = Report()
    report.add_stage("schema", schemas.validate_document("pack", pack))
    if report.stages["schema"] == "passed":
        report.add_stage("references", reference_findings(pack))
        report.add_stage("content_rules", content_rule_findings(pack))
    else:
        report.skip_stage("references")
        report.skip_stage("content_rules")
    if file_size is not None:
        report.add_stage("size", size_findings(file_size, str(pack.get("pack_id", "core"))))
    return report
