"""Promotion on production (contracts/pack-delivery.md "Promotion on production", FR-039a, R6).

Production pulls the exact files staging published, anchored by the pasted promotion code:

1. `promote_pack`, `CONTENT_ROLE=target`, a well-formed code, a version above the current one.
2. Fetch the release record; its sha256 must equal the code.
3. Every stage passed, the solver included; a `size` or `solver` warning is fine (B05).
4. Fetch the pack file; its size and sha256 must equal the record's.
5. Decompress with a cap, parse strictly, run the schema, reference and content-rule stages
   against production's schemas, and check the identity and minimum-app-version floor.
6. Write both files create-only and read them back, raise the floor file, then commit.

Every failure is a short code without URLs or secrets, in the audit record. `current` changes
only at step 6's commit, so a failed promotion leaves production as it was.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from django.conf import settings
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.utils import timezone
from wassal_content.canonical import canonical_bytes
from wassal_content.loader import ContentLoadError, load_json_bytes
from wassal_content.packfile import PackFileError, decompress_capped, sha256_hex
from wassal_content.validate import validate_pack

from apps.accounts.models import User
from apps.common.client import as_tuple
from apps.content.models import ContentAuditRecord, ContentChannel, ContentPack
from apps.content.models.packs import Origin, Status
from apps.content.services import audit, build, files, http, lookups, manifest, permissions
from apps.content.services.versioning import PACK_ID

logger = logging.getLogger(__name__)

PROMOTE_PERMISSION = "content.promote_pack"
CODE = re.compile(r"^core-([0-9]+):([0-9a-f]{64})$")
MAX_RELEASE_BYTES = 64 * 1024
MAX_PACK_BYTES = 16 * 1024 * 1024
MAX_PACK_JSON_BYTES = 32 * 1024 * 1024
STAMP = "%Y-%m-%dT%H:%M:%SZ"
Action = ContentAuditRecord.Action
Outcome = ContentAuditRecord.Outcome


class PromotionRefused(Exception):  # step 1: nothing is fetched
    """The message is for staff."""


class PromotionFailed(Exception):
    """Steps 2-6. `code` is one of the contract's failure codes."""

    def __init__(self, code: str, findings: list[dict[str, str]] | None = None) -> None:
        self.code = code
        self.findings = findings or []
        super().__init__(code)


@dataclass(frozen=True)
class Fetched:
    version: int
    record: dict[str, Any]
    record_bytes: bytes
    pack: dict[str, Any]
    pack_bytes: bytes


def parse_code(code: str) -> tuple[int, str]:
    match = CODE.match(code.strip())
    if match is None:
        raise PromotionRefused("A promotion code looks like core-<version>:<64 hex characters>.")
    return int(match[1]), match[2]


def check(code: str, actor: User | None) -> tuple[User, int, str]:
    """Step 1, also made when the promotion is requested."""
    user = permissions.require(actor, PROMOTE_PERMISSION)
    permissions.require_role(permissions.TARGET)
    version, release_sha256 = parse_code(code)
    current = build.current_pack()
    if current is not None and version <= (current.version or 0):
        raise PromotionRefused(
            f"Version {version} isn't above production's current pack, {current.version}."
        )
    return user, version, release_sha256


def request_promotion(code: str, actor: User | None) -> None:
    """Check, then queue the promotion on the worker, which holds the packs directory."""
    try:
        user, _, _ = check(code, actor)
    except (PermissionDenied, PromotionRefused) as error:
        _audit_failed(code, actor, str(error))
        raise
    from apps.content import tasks  # the tasks module imports this one

    transaction.on_commit(lambda: tasks.promote_pack.delay(code.strip(), user.username))


def promote(code: str, actor: User | None) -> ContentPack | None:
    """Steps 1-6. Returns the promoted pack, or None after an audited failure."""
    try:
        user, version, release_sha256 = check(code, actor)
        fetched = _fetch(version, release_sha256)
        _validate(fetched)
        _store(fetched)
        return _commit(fetched, user)
    except (PermissionDenied, PromotionRefused) as error:
        _audit_failed(code, actor, str(error))
    except PromotionFailed as failure:
        _audit_failed(code, actor, failure.code, failure.findings)
    return None


# -- steps 2-5 -----------------------------------------------------------------------------------


def _get(name: str, max_bytes: int, unreachable: str, too_large: str) -> bytes:
    try:
        return http.fetch(f"{settings.CONTENT_PROMOTION_SOURCE_URL}{name}", max_bytes=max_bytes)
    except http.FetchError as error:
        raise PromotionFailed(too_large if error.reason == "too_large" else unreachable) from None


def _fetch(version: int, release_sha256: str) -> Fetched:
    record_bytes = _get(
        files.release_file_name(version),
        MAX_RELEASE_BYTES,
        "release_unreachable",
        "release_mismatch",
    )
    if sha256_hex(record_bytes) != release_sha256:
        raise PromotionFailed("release_mismatch")
    try:
        record = load_json_bytes(record_bytes)
    except ContentLoadError:
        raise PromotionFailed("release_mismatch") from None
    if not isinstance(record, dict) or record.get("version") != version:
        raise PromotionFailed("release_mismatch")
    if not _passed(record):
        raise PromotionFailed("release_not_passed")
    pack_bytes = _get(
        files.pack_file_name(version), MAX_PACK_BYTES, "pack_unreachable", "pack_mismatch"
    )
    if len(pack_bytes) != record.get("size") or sha256_hex(pack_bytes) != record.get("sha256"):
        raise PromotionFailed("pack_mismatch")
    try:
        pack = load_json_bytes(decompress_capped(pack_bytes, max_bytes=MAX_PACK_JSON_BYTES))
    except (PackFileError, ContentLoadError):
        raise PromotionFailed("pack_invalid") from None
    if not isinstance(pack, dict):
        raise PromotionFailed("pack_invalid")
    return Fetched(version, record, record_bytes, pack, pack_bytes)


WARNING_STAGES = frozenset({"size", "solver"})
"""The stages whose `warning` still promotes (B05 contracts/content-pipeline.md §4)."""


def _passed(record: dict[str, Any]) -> bool:
    """Step 3: every stage passed, or `size` or the solver warned, and the solver ran."""
    stages = record.get("stages")
    if not isinstance(stages, dict) or stages.get("solver") not in ("passed", "warning"):
        return False
    return all(
        result == "passed" or (stage in WARNING_STAGES and result == "warning")
        for stage, result in stages.items()
    )


def _validate(fetched: Fetched) -> None:
    """Step 5: production's own schemas and rules, the identity, and the minimum's floor."""
    pack, record = fetched.pack, fetched.record
    report = validate_pack(pack, file_size=len(fetched.pack_bytes))
    errors = [finding.to_dict() for finding in report.errors]
    if errors or any(
        report.stages.get(s) != "passed" for s in ("schema", "references", "content_rules")
    ):
        raise PromotionFailed("pack_invalid", errors[:50])
    for key in ("pack_id", "version", "schema_version"):
        if pack.get(key) != record.get(key):
            raise PromotionFailed(
                "pack_invalid", [{"path": f"$.{key}", "message": "differs from the release record"}]
            )
    minimum = record.get("min_client_version")
    if not isinstance(minimum, str) or not manifest.MIN_VERSION.match(minimum):
        raise PromotionFailed(
            "pack_invalid", [{"path": "min_client_version", "message": "malformed"}]
        )
    try:
        floor = build.min_client_floor(str(pack["schema_version"]))
    except KeyError:  # a schema major production doesn't know
        raise PromotionFailed(
            "pack_invalid", [{"path": "$.schema_version", "message": "unknown schema major"}]
        ) from None
    if as_tuple(minimum) < as_tuple(floor):
        raise PromotionFailed(
            "pack_invalid", [{"path": "min_client_version", "message": f"below the floor {floor}"}]
        )


# -- step 6 --------------------------------------------------------------------------------------


def _store(fetched: Fetched) -> None:
    directory = files.packs_dir()
    expected = (
        (files.pack_file_name(fetched.version), fetched.pack_bytes),
        (files.release_file_name(fetched.version), fetched.record_bytes),
    )
    try:
        for name, data in expected:
            files.write_create_only(directory / name, data)
        for name, data in expected:
            if files.sha256_of(directory / name) != sha256_hex(data):
                raise PromotionFailed("storage_error")
        # Raised before the commit, so it never lags production's files (contract).
        files.write_floor(fetched.version)
    except (OSError, files.FileConflict):
        logger.error("promotion storage error", extra={"version": fetched.version})
        raise PromotionFailed("storage_error") from None


def _stamp(value: Any) -> datetime | None:
    try:
        return datetime.strptime(str(value), STAMP).replace(tzinfo=UTC)
    except ValueError:
        return None


def _commit(fetched: Fetched, user: User) -> ContentPack:
    record = fetched.record
    try:
        with transaction.atomic():
            channel = ContentChannel.objects.select_for_update().get_or_create(pack_id=PACK_ID)[0]
            current = channel.current
            if current is not None and fetched.version <= (current.version or 0):
                raise PromotionRefused(
                    f"Version {fetched.version} isn't above production's current pack, "
                    f"{current.version}."
                )
            now = timezone.now()
            pack = ContentPack.objects.create(
                pack_id=PACK_ID,
                version=fetched.version,
                origin=Origin.PROMOTED,
                status=Status.PUBLISHED,
                schema_version=str(fetched.pack["schema_version"]),
                canonical_sha256=sha256_hex(canonical_bytes(fetched.pack)),
                sha256=str(record["sha256"]),
                size=len(fetched.pack_bytes),
                file=fetched.pack_bytes,
                release_sha256=sha256_hex(fetched.record_bytes),
                release_file=fetched.record_bytes,
                validation_report=_report(record),
                min_client_version=str(record["min_client_version"]),
                built_at=_stamp(record.get("built_at")),
                published_at=_stamp(record.get("published_at")),
                promoted_by=user.username,
                promoted_at=now,
            )
            channel.current = pack
            channel.save(update_fields=["current", "updated_at"])
            lookups.index_pack(pack, fetched.pack)
            lookups.retire_beyond_five(PACK_ID)
            audit.record(Action.PROMOTE, Outcome.SUCCEEDED, user, pack, {"record": record})
            transaction.on_commit(manifest.invalidate)
    except (PromotionFailed, PromotionRefused):
        raise
    except Exception:
        logger.exception("promotion commit failed", extra={"version": fetched.version})
        raise PromotionFailed("storage_error") from None
    return pack


def _report(record: dict[str, Any]) -> dict[str, Any]:
    """The pack's page shows staging's stage results and warnings, as the record has them."""
    stages: dict[str, dict[str, Any]] = {
        stage: {"result": result} for stage, result in record["stages"].items()
    }
    if "size" in stages:
        stages["size"]["bytes"] = record.get("size")
    warnings = [
        {**warning, "stage": "size" if warning.get("code") == "V-S1" else "", "severity": "warning"}
        for warning in record.get("warnings", [])
        if isinstance(warning, dict)
    ]
    return {"schema_version": record.get("schema_version"), "stages": stages, "findings": warnings}


def _audit_failed(
    code: str, actor: User | None, reason: str, findings: list[dict[str, str]] | None = None
) -> None:
    match = CODE.match(code.strip())
    details: dict[str, Any] = {"reason": reason, "code": code.strip()[:80]}
    if findings:
        details["findings"] = findings
    ContentAuditRecord.objects.create(
        action=Action.PROMOTE,
        outcome=Outcome.FAILED,
        actor=actor.username if actor is not None else "",
        pack_id=PACK_ID,
        version=int(match[1]) if match else None,
        details=details,
    )
