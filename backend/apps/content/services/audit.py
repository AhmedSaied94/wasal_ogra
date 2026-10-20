"""The content audit log (FR-038): publishes, promotions, rollbacks and minimum-version changes."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from apps.accounts.models import User
from apps.content.models import ContentAuditRecord, ContentPack


def record(
    action: str,
    outcome: str,
    actor: User | str,
    pack: ContentPack | None = None,
    details: Mapping[str, Any] | None = None,
) -> ContentAuditRecord:
    return ContentAuditRecord.objects.create(
        action=action,
        outcome=outcome,
        actor=actor if isinstance(actor, str) else actor.username,
        pack_id=pack.pack_id if pack else "",
        version=pack.version if pack else None,
        sha256=pack.sha256 if pack else "",
        details=dict(details or {}),
    )
