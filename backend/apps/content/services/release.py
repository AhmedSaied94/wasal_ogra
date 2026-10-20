"""Release records and promotion codes (contracts/pack-delivery.md "Release record", R6)."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from wassal_content.canonical import canonical_bytes

from apps.content.models import ContentPack
from apps.content.services.build import utc_stamp
from apps.content.services.versioning import PACK_ID

WARNING_FIELDS = ("code", "entity", "id", "path", "message")


def release_record(pack: ContentPack, published_at: datetime) -> bytes:
    """The record as canonical JSON. It holds no staff names."""
    if pack.built_at is None or pack.version is None:
        raise ValueError(f"{pack} hasn't finished building")
    report = pack.validation_report
    record: dict[str, Any] = {
        "built_at": utc_stamp(pack.built_at),
        "min_client_version": pack.min_client_version,
        "pack_id": pack.pack_id,
        "published_at": utc_stamp(published_at),
        "schema_version": pack.schema_version,
        "sha256": pack.sha256,
        "size": pack.size,
        "stages": {stage: data["result"] for stage, data in report["stages"].items()},
        "version": pack.version,
        "warnings": [
            {name: finding[name] for name in WARNING_FIELDS}
            for finding in report["findings"]
            if finding["severity"] == "warning"
        ],
    }
    return canonical_bytes(record)


def promotion_code(pack: ContentPack) -> str:
    """`core-<v>:<sha256 of the release record>`, which production's publisher pastes."""
    return f"{PACK_ID}-{pack.version}:{pack.release_sha256}"
