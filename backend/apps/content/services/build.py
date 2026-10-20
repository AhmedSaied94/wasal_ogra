"""Building a draft pack (FR-020-FR-024, research R7, R10).

`request_build` records a queued draft and queues the job. `run_build` takes a consistent
snapshot, assigns the version, computes each trip's `rev` against the current pack, assembles and
compresses the pack, and runs every validation stage. A worker restart never leaves a half-built
pack looking valid: the record only becomes `validated` in the build's last save.
"""

from __future__ import annotations

import logging
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from django.db import transaction
from django.utils import timezone
from wassal_content.canonical import canonical_bytes
from wassal_content.findings import STAGES, Report
from wassal_content.packfile import build_pack_file, sha256_hex
from wassal_content.schemas import default_schema_set
from wassal_content.source import SourceTree, assemble_pack
from wassal_content.validate import validate_pack

from apps.accounts.models import User
from apps.content.models import ContentChannel, ContentPack, PackTripIndex
from apps.content.models.packs import BuildState, Origin, Status
from apps.content.services import exporter, permissions, stages, versioning
from apps.content.services.snapshot import Snapshot, snapshot

logger = logging.getLogger(__name__)

PACK_ID = "core"
STALE_AFTER_SECONDS = 30 * 60


@dataclass
class BuildOutput:
    """What a build produces, saved or (for `--dry-run`) only shown."""

    version: int
    pack: dict[str, Any]
    canonical_sha256: str
    sha256: str
    size: int
    file: bytes
    report: dict[str, Any]
    passed: bool


def utc_stamp(moment: datetime) -> str:
    return moment.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def min_client_floor(version: str) -> str:
    """The lowest `min_client_version` a pack of this schema major may have (FR-032, R3)."""
    floors: Mapping[str, str] = default_schema_set().meta["min_client_version_by_major"]
    return floors[version.split(".")[0]]


def current_pack() -> ContentPack | None:
    channel = ContentChannel.objects.select_related("current").filter(pack_id=PACK_ID).first()
    return channel.current if channel else None


# -- requesting -----------------------------------------------------------------------------------


BUILD_PERMISSION = "content.build_pack"


def require_builder(actor: User | None, permission: str = BUILD_PERMISSION) -> User:
    user = permissions.require(actor, permission)
    permissions.require_role(permissions.SOURCE)
    return user


def request_build(
    actor: User | None,
    *,
    rollback_of: ContentPack | None = None,
    permission: str = BUILD_PERMISSION,
) -> ContentPack:
    """A queued draft, built by the `content` queue once this transaction commits. A rollback
    build needs `rollback_pack` instead of `build_pack` (contracts/admin.md)."""
    pack = new_draft(actor, rollback_of=rollback_of, permission=permission)
    from apps.content import tasks  # the tasks module imports this one

    transaction.on_commit(lambda: tasks.build_pack.delay(str(pack.pk)))
    return pack


def new_draft(
    actor: User | None,
    *,
    rollback_of: ContentPack | None = None,
    permission: str = BUILD_PERMISSION,
) -> ContentPack:
    """A draft waiting for its build, after `request_build`'s checks."""
    user = require_builder(actor, permission)
    current = current_pack()
    version = exporter.schema_version()
    return ContentPack.objects.create(
        pack_id=PACK_ID,
        origin=Origin.BUILT,
        status=Status.DRAFT,
        build_state=BuildState.QUEUED,
        schema_version=version,
        min_client_version=current.min_client_version if current else min_client_floor(version),
        built_by=user.username,
        rollback_of=rollback_of,
    )


# -- building -------------------------------------------------------------------------------------


def parts_of(pack: ContentPack) -> Snapshot:
    """A stored pack's content as parts, for a rollback build (FR-028)."""
    stored = exporter.stored_pack(pack)
    tree = SourceTree(
        meta={"pack_id": PACK_ID, "schema_version": stored["schema_version"], "version": 0},
        catalog=stored["catalog"],
    )
    for array in tree.parts:
        tree.parts[array] = list(stored[array])
    return Snapshot(tree=tree, snapshot_at=timezone.now())


def current_trips(current: ContentPack | None) -> dict[str, dict[str, Any]]:
    """The current pack's trip definitions, from its index rows or else its file."""
    if current is None:
        return {}
    rows = PackTripIndex.objects.filter(pack=current).values_list("trip_id", "definition")
    if rows:
        return {trip_id: dict(definition) for trip_id, definition in rows}
    return {trip["trip_id"]: trip for trip in exporter.stored_pack(current)["trips"]}


def with_revs(pack: dict[str, Any], current: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
    """`rev` goes up only for a trip whose definition differs from the current pack's (FR-023)."""
    trips = []
    for trip in pack["trips"]:
        before = current.get(trip["trip_id"])
        if before is None:
            trips.append(trip)
            continue
        same = {**trip, "rev": 0} == {**before, "rev": 0}
        trips.append({**trip, "rev": before["rev"] if same else before["rev"] + 1})
    return {**pack, "trips": trips}


def produce(
    parts: Snapshot, version: int, current: ContentPack | None, *, review: bool
) -> BuildOutput:
    """Assemble, compress and validate. Changes nothing in the database."""
    pack = with_revs(assemble_pack(parts.tree, version), current_trips(current))
    canonical = canonical_bytes(pack)
    file = build_pack_file(canonical)
    report = validate_pack(pack, file_size=len(file))
    report.add_stage("review", stages.review_stage(parts) if review else [])
    solver = stages.load_solver_stage().run(pack)
    if solver is None:
        report.skip_stage("solver")
    else:
        report.add_stage("solver", solver)
    return BuildOutput(
        version=version,
        pack=pack,
        canonical_sha256=sha256_hex(canonical),
        sha256=sha256_hex(file),
        size=len(file),
        file=file,
        report=report_dict(report, parts.snapshot_at, pack["schema_version"], len(file)),
        passed=is_green(report),
    )


def stage_order(stage: str) -> int:
    """A stage's place in reports. Stored reports are `jsonb`, which doesn't keep key order."""
    return STAGES.index(stage) if stage in STAGES else len(STAGES)


def is_green(report: Report) -> bool:
    """Every stage passed or warned. The solver may also be `not_available`, which only blocks
    publishing (contracts/admin.md "Validation report")."""
    return all(
        result in ("passed", "warning") or (stage == "solver" and result == "not_available")
        for stage, result in report.stages.items()
    )


def report_dict(report: Report, snapshot_at: datetime, version: str, size: int) -> dict[str, Any]:
    stages_: dict[str, dict[str, Any]] = {
        stage: {"result": report.stages[stage]} for stage in STAGES if stage in report.stages
    }
    stages_["size"]["bytes"] = size
    # Grouped by stage, errors first within each (contracts/admin.md "Validation report").
    findings = sorted(report.findings, key=lambda f: (STAGES.index(f.stage), f.severity != "error"))
    return {
        "snapshot_at": utc_stamp(snapshot_at),
        "schema_version": version,
        "stages": stages_,
        "findings": [finding.to_dict() for finding in findings],
    }


def run_build(pack_pk: str) -> ContentPack:
    """Build a queued draft. A re-run of a finished or failed build changes nothing."""
    with transaction.atomic():
        pack = ContentPack.objects.select_for_update().get(pk=pack_pk)
        if pack.build_state in (BuildState.FINISHED, BuildState.FAILED):
            return pack
        pack.build_state = BuildState.RUNNING
        pack.save(update_fields=["build_state", "updated_at"])
    try:
        parts = parts_of(pack.rollback_of) if pack.rollback_of else snapshot(pack.schema_version)
        if pack.version is None:
            # Saved at once, so a build redelivered after a worker loss keeps its number.
            pack.version = versioning.next_version()
            pack.save(update_fields=["version", "updated_at"])
        output = produce(parts, pack.version, current_pack(), review=pack.rollback_of is None)
    except versioning.VersionFloorUnavailable as error:
        return _fail(pack, str(error))
    except Exception:
        logger.exception("content build failed", extra={"pack": str(pack.pk)})
        return _fail(pack, "internal error, see the logs")
    pack.snapshot_at = parts.snapshot_at
    pack.file = output.file
    pack.sha256 = output.sha256
    pack.canonical_sha256 = output.canonical_sha256
    pack.size = output.size
    pack.validation_report = output.report
    pack.build_state = BuildState.FINISHED
    pack.built_at = timezone.now()
    pack.failure_reason = ""
    pack.save()
    if output.passed:
        pack.status = Status.VALIDATED
        pack.save(update_fields=["status", "updated_at"])
    return pack


def _fail(pack: ContentPack, reason: str) -> ContentPack:
    pack.build_state = BuildState.FAILED
    pack.failure_reason = reason
    pack.save(update_fields=["build_state", "failure_reason", "updated_at"])
    return pack


def sweep_stuck_builds() -> int:
    """Mark builds still `running` after 30 minutes as failed, so none looks done (R10)."""
    cutoff = timezone.now() - timedelta(seconds=STALE_AFTER_SECONDS)
    stuck = ContentPack.objects.filter(build_state=BuildState.RUNNING, updated_at__lt=cutoff)
    count = 0
    for pack in stuck:
        _fail(pack, "the build stopped: no result after 30 minutes")
        count += 1
    return count
