"""Publishing on staging (contracts/pack-delivery.md "Publish on staging", FR-025-FR-027).

1. Check: `publish_pack`, `CONTENT_ROLE=source`, a validated pack whose solver stage passed and
   whose version is above the current pack's.
2. Write the pack file and its release record create-only.
3. Read both back and compare their sha256 with the record.
4. Commit in one transaction: published, current, permanent identifiers, index rows, retiring the
   6th newest, the audit record. The manifest cache is cleared on commit.
5. On failure the pack stays validated, a failed audit record is written, and a retry is safe:
   the release record is made once and kept, so a retry writes the same bytes.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import UUID

from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.utils import timezone
from wassal_content.loader import load_json_bytes
from wassal_content.packfile import sha256_hex

from apps.accounts.models import User
from apps.content.models import ContentAuditRecord, ContentChannel, ContentPack
from apps.content.models.packs import Status
from apps.content.services import (
    audit,
    build,
    exporter,
    files,
    lookups,
    manifest,
    permanence,
    permissions,
    release,
)
from apps.content.services.versioning import PACK_ID

logger = logging.getLogger(__name__)

PUBLISH_PERMISSION = "content.publish_pack"
Action = ContentAuditRecord.Action
Outcome = ContentAuditRecord.Outcome


class PublishRefused(Exception):
    """A check of step 1 failed. The message is for staff."""


class StorageMismatch(Exception):
    def __init__(self, name: str) -> None:
        super().__init__(f"{name} doesn't read back as recorded")


def check(pack: ContentPack, actor: User | None) -> User:
    """Step 1, also made when the publish is requested."""
    user = permissions.require(actor, PUBLISH_PERMISSION)
    permissions.require_role(permissions.SOURCE)
    if pack.status != Status.VALIDATED:
        raise PublishRefused(f"{pack} is {pack.status}, not validated.")
    solver = pack.validation_report.get("stages", {}).get("solver", {}).get("result")
    if solver != "passed":
        raise PublishRefused(f"{pack}'s solver stage is {solver}, not passed.")
    current = build.current_pack()
    if current is not None and (pack.version or 0) <= (current.version or 0):
        raise PublishRefused(f"{pack} isn't above the current pack, version {current.version}.")
    return user


def request_publish(pack: ContentPack, actor: User | None) -> None:
    """Check, then queue the publish on the worker, which holds the packs directory."""
    try:
        user = check(pack, actor)
    except (PermissionDenied, PublishRefused) as error:
        _failed(pack, actor, str(error))
        raise
    from apps.content import tasks  # the tasks module imports this one

    transaction.on_commit(lambda: tasks.publish_pack.delay(str(pack.pk), user.username))


def publish(pack_pk: str, actor: User | None) -> ContentPack:
    """Steps 1-5. Returns the pack, published or with `failure_reason` set."""
    pack = ContentPack.objects.get(pk=pack_pk)
    try:
        user = check(pack, actor)
        _prepare(pack)
        _store(pack)
        _commit(pack, user)
    except (PermissionDenied, PublishRefused) as error:
        return _failed(pack, actor, str(error))
    except files.FileConflict as conflict:
        return _failed(pack, actor, f"file_conflict: {conflict}")
    except (OSError, StorageMismatch) as error:
        logger.error(
            "publish storage error", extra={"pack": str(pack), "error": type(error).__name__}
        )
        return _failed(pack, actor, f"storage_error: {_storage_reason(error)}")
    except Exception:
        logger.exception("publish failed", extra={"pack": str(pack)})
        return _failed(pack, actor, "internal error, see the logs")
    return ContentPack.objects.get(pk=pack.pk)


def _storage_reason(error: Exception) -> str:
    if isinstance(error, StorageMismatch):
        return str(error)
    if isinstance(error, PermissionError):
        return "the packs directory isn't writable"
    return "the pack files couldn't be written"


def _prepare(pack: ContentPack) -> None:
    """Make the release record once. A retry reuses it, so its files never conflict."""
    if sha256_hex(bytes(pack.file)) != pack.sha256:
        raise StorageMismatch(files.pack_file_name(pack.version or 0))
    if pack.release_file:
        return
    data = release.release_record(pack, timezone.now())
    pack.release_file = data
    pack.release_sha256 = sha256_hex(data)
    pack.save(update_fields=["release_file", "release_sha256", "updated_at"])


def _store(pack: ContentPack) -> None:
    """Steps 2 and 3: write create-only, then read back and compare."""
    version = files.version_of(pack)
    directory = files.packs_dir()
    expected = (
        (files.pack_file_name(version), bytes(pack.file), pack.sha256),
        (files.release_file_name(version), bytes(pack.release_file), pack.release_sha256),
    )
    for name, data, _ in expected:
        files.write_create_only(directory / name, data)
    for name, _, sha256 in expected:
        if files.sha256_of(directory / name) != sha256:
            raise StorageMismatch(name)


def _published_at(pack: ContentPack) -> datetime:
    stamp = load_json_bytes(bytes(pack.release_file))["published_at"]
    return datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)


def _commit(pack: ContentPack, user: User) -> None:
    """Step 4, in one transaction."""
    data = exporter.stored_pack(pack)
    with transaction.atomic():
        channel = ContentChannel.objects.select_for_update().get_or_create(pack_id=PACK_ID)[0]
        locked = ContentPack.objects.select_for_update().get(pk=pack.pk)
        current = channel.current
        if locked.status != Status.VALIDATED:
            raise PublishRefused(f"{locked} is {locked.status}, not validated.")
        if current is not None and (locked.version or 0) <= (current.version or 0):
            raise PublishRefused(
                f"{locked} isn't above the current pack, version {current.version}."
            )
        version = files.version_of(locked)
        locked.status = Status.PUBLISHED
        locked.published_by = user.username
        locked.published_at = _published_at(locked)
        locked.failure_reason = ""
        locked.save()
        channel.current = locked
        channel.save(update_fields=["current", "updated_at"])
        permanence.record_published(data, version)
        lookups.index_pack(locked, data)
        lookups.retire_beyond_five(PACK_ID)
        audit.record(
            Action.PUBLISH, Outcome.SUCCEEDED, user, locked, {"report": locked.validation_report}
        )
        if locked.rollback_of_id is not None:
            audit.record(
                Action.ROLLBACK,
                Outcome.SUCCEEDED,
                user,
                locked,
                {"stage": "published", "rollback_of": _version_of(locked.rollback_of_id)},
            )
        transaction.on_commit(manifest.invalidate)


def _version_of(pack_pk: UUID) -> int | None:
    return ContentPack.objects.filter(pk=pack_pk).values_list("version", flat=True).first()


def _failed(pack: ContentPack, actor: User | None, reason: str) -> ContentPack:
    """Step 5: the pack stays as it was, with the reason, and a failed audit record."""
    audit.record(
        Action.PUBLISH,
        Outcome.FAILED,
        actor.username if actor is not None else "",
        pack,
        {"reason": reason},
    )
    if pack.status in (Status.DRAFT, Status.VALIDATED):
        ContentPack.objects.filter(pk=pack.pk).update(
            failure_reason=reason, updated_at=timezone.now()
        )
        pack.failure_reason = reason
    return pack
