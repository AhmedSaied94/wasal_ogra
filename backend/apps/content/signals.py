"""Deletes the content rules refuse, including queryset and cascade deletes (FR-016, FR-038).

Django sends `pre_delete` for every row a delete collects, before it deletes any of them, so one
refusal stops the whole delete.
"""

from __future__ import annotations

from typing import Any

from django.db.models.signals import pre_delete

from apps.content.errors import ImmutableError
from apps.content.models import PERMANENT_MODELS, ContentAuditRecord, ContentPack, PermanentModel
from apps.content.models.packs import STORED
from apps.content.services import permanence


def refuse_published_identifier(sender: type[Any], instance: PermanentModel, **kwargs: Any) -> None:
    permanence.refuse_delete(instance)


def refuse_audit_delete(sender: type[Any], instance: ContentAuditRecord, **kwargs: Any) -> None:
    raise ImmutableError("the content audit log is append-only")


def refuse_stored_pack_delete(sender: type[Any], instance: ContentPack, **kwargs: Any) -> None:
    if instance.status in STORED:
        raise ImmutableError(f"{instance} is {instance.status}, so its record is kept")


for _model in PERMANENT_MODELS:
    pre_delete.connect(
        refuse_published_identifier,
        sender=_model,
        dispatch_uid=f"content.permanence.{_model._meta.model_name}",
    )
pre_delete.connect(refuse_audit_delete, sender=ContentAuditRecord, dispatch_uid="content.audit")
pre_delete.connect(refuse_stored_pack_delete, sender=ContentPack, dispatch_uid="content.packs")
