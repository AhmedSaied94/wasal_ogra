"""The content invariant run by the restore drill and `sync_files --verify` (data-model.md)."""

from __future__ import annotations

from typing import Any

import psycopg

from apps.common.services.invariants import register

MAX_LISTED = 10
STORED_STATUSES = ["published", "retired"]


@register("content.published_packs_intact")
def published_packs_intact(connection: psycopg.Connection[Any]) -> tuple[bool, str]:
    """Every published or retired pack's file still has its recorded SHA-256 and size."""
    total = connection.execute(
        "SELECT count(*) FROM content_contentpack WHERE status = ANY(%s)", [STORED_STATUSES]
    ).fetchone()
    broken = connection.execute(
        "SELECT pack_id, version FROM content_contentpack"
        " WHERE status = ANY(%s)"
        " AND (sha256 <> encode(sha256(file), 'hex') OR octet_length(file) <> size)"
        " ORDER BY pack_id, version",
        [STORED_STATUSES],
    ).fetchall()
    count = total[0] if total else 0
    if not broken:
        return True, f"{count} published or retired packs intact"
    listed = ", ".join(f"{pack_id}-{version}" for pack_id, version in broken[:MAX_LISTED])
    return False, f"{len(broken)} of {count} packs don't match their sha256 or size: {listed}"
