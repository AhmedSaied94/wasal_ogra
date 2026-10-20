"""The size stage: a pack over mobile §19's budget is a warning, not an error (V-S1)."""

from __future__ import annotations

from wassal_content.findings import Finding

__all__ = ["SIZE_WARNING_BYTES", "size_findings"]

SIZE_WARNING_BYTES = 2_097_152


def size_findings(file_size: int, pack_id: str = "core") -> list[Finding]:
    """The size finding of a pack file of `file_size` compressed bytes, if any."""
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
            id=pack_id,
        )
    ]
