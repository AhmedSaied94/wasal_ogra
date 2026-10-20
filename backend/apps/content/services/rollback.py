"""Rolling back (FR-028, contracts/admin.md "Roll back to this").

A rollback builds an earlier published or retired pack's content as a new version, with
`rollback_of` set. Its build reads the stored pack's parts instead of the authoring tables, and
computes `rev` against the current pack like any build. The publisher then publishes it as usual.
Queueing it and publishing it each write a `rollback` audit record.
"""

from __future__ import annotations

from django.core.exceptions import PermissionDenied, ValidationError

from apps.accounts.models import User
from apps.content.models import ContentAuditRecord, ContentPack
from apps.content.models.packs import STORED
from apps.content.services import audit, build

ROLLBACK_PERMISSION = "content.rollback_pack"
Action = ContentAuditRecord.Action
Outcome = ContentAuditRecord.Outcome


def request_rollback(pack: ContentPack, actor: User | None) -> ContentPack:
    """Queue the rollback build. Needs `rollback_pack` and `CONTENT_ROLE=source`."""
    name = actor.username if actor is not None else ""
    try:
        build.require_builder(actor, ROLLBACK_PERMISSION)
        if pack.status not in STORED:
            raise ValidationError("Only a published or retired pack can be rolled back to.")
        draft = build.request_build(actor, rollback_of=pack, permission=ROLLBACK_PERMISSION)
    except (PermissionDenied, ValidationError) as error:
        reason = "; ".join(error.messages) if isinstance(error, ValidationError) else str(error)
        audit.record(
            Action.ROLLBACK, Outcome.FAILED, name, pack, {"stage": "queued", "reason": reason}
        )
        raise
    audit.record(
        Action.ROLLBACK, Outcome.SUCCEEDED, name, pack, {"stage": "queued", "build": str(draft.pk)}
    )
    return draft
