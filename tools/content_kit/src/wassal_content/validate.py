"""Pack validation: the stages of FR-021 that need no authoring data, and lone documents.

The stages are `schema`, `references`, `content_rules` and, when the pack file's size is known,
`size`. `content_rules` includes the engine's rules, V-T8 to V-T11 (specs/004). The rules assume
the schema's shapes, so when the schema stage fails they report `not_available` instead of
running. The `review` and `solver` stages need authoring data or B05, so they run in
`backend/apps/content`.

A lone document gets its schema and, for a trip, the engine rules that need no pack (V-T8, V-T9):
that is how a parity fixture's definition or a daily challenge is checked.
"""

from __future__ import annotations

from dataclasses import replace
from typing import Any

from wassal_content.findings import Finding, Report
from wassal_content.rules import (
    SIZE_WARNING_BYTES,
    content_rule_findings,
    engine_findings,
    reference_findings,
    size_findings,
    trip_engine_findings,
    trip_local_findings,
)
from wassal_content.schemas import SchemaSet, default_schema_set

__all__ = ["SIZE_WARNING_BYTES", "document_findings", "validate_pack"]


def validate_pack(
    pack: Any, *, file_size: int | None, schema_set: SchemaSet | None = None
) -> Report:
    """Run every stage that works on the pack alone, and report each one's result."""
    schemas = schema_set or default_schema_set()
    report = Report()
    report.add_stage("schema", schemas.validate_document("pack", pack))
    if report.stages["schema"] == "passed":
        report.add_stage("references", reference_findings(pack))
        report.add_stage("content_rules", [*content_rule_findings(pack), *engine_findings(pack)])
    else:
        report.skip_stage("references")
        report.skip_stage("content_rules")
    if file_size is not None:
        report.add_stage("size", size_findings(file_size, str(pack.get("pack_id", "core"))))
    return report


def document_findings(
    part: str, document: Any, *, file: str | None = None, schema_set: SchemaSet | None = None
) -> list[Finding]:
    """A lone document's findings: the schema's, or once it passes, a trip's own references
    (V-T1, V-T4 to V-T6) and the engine's rules (V-T8, V-T9)."""
    schemas = schema_set or default_schema_set()
    findings = schemas.validate_document(part, document, file=file)
    if part == "trip" and not findings:
        findings = sorted(
            replace(finding, file=file)
            for finding in [*trip_local_findings(document), *trip_engine_findings(document)]
        )
    return findings
