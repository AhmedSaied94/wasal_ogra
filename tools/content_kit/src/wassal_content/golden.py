"""The golden checksums of the sample pack (FR-011, SC-004, research R4).

The sample content built as version 1 must give the checksums in
`content/examples/sample.golden.json` on every machine. A change of compressor (zlib-ng, say)
or of the canonical form shows up as a red test, not as a silent difference.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from wassal_content.canonical import canonical_bytes
from wassal_content.packfile import build_pack_file, sha256_hex
from wassal_content.schemas import SchemaSet
from wassal_content.source import assemble_pack, export_bytes, read_layout

__all__ = ["GOLDEN_VERSION", "compute_golden", "golden_bytes"]

GOLDEN_VERSION = 1


def compute_golden(sample: Path, schema_set: SchemaSet | None = None) -> dict[str, Any]:
    """The checksums and size of the sample layout built as version 1."""
    tree, findings = read_layout(sample, schema_set)
    if findings:
        problems = "\n".join(f"  {f.file}: {f.path}: {f.message}" for f in findings)
        raise ValueError(f"the sample has findings:\n{problems}")
    canonical = canonical_bytes(assemble_pack(tree, GOLDEN_VERSION))
    packed = build_pack_file(canonical)
    return {
        "canonical_sha256": sha256_hex(canonical),
        "sha256": sha256_hex(packed),
        "size": len(packed),
        "version": GOLDEN_VERSION,
    }


def golden_bytes(sample: Path, schema_set: SchemaSet | None = None) -> bytes:
    """The golden file's content, in the export format."""
    return export_bytes(compute_golden(sample, schema_set))
