"""Promotion on production (tasks.md T093, contracts/pack-delivery.md "Promotion on production").

Production runs with `CONTENT_ROLE=target`, and `pack_server` stands in for staging's public
packs URL. Staging's files are made in memory from the sample content, because staging and
production can't share one test database.
"""

from __future__ import annotations

import gzip
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest
from django.core.exceptions import PermissionDenied
from pytest_django import DjangoCaptureOnCommitCallbacks, Settings
from wassal_content.canonical import canonical_bytes
from wassal_content.packfile import build_pack_file

from apps.accounts.models import User
from apps.content import tasks
from apps.content.models import ContentAuditRecord, ContentChannel, ContentPack, PackTripIndex
from apps.content.models.packs import Origin, Status
from apps.content.services import build, files, http, lookups, promote
from apps.content.services.snapshot import snapshot
from apps.content.tests.conftest import PackServer, admin_client

pytestmark = pytest.mark.django_db

Action = ContentAuditRecord.Action
Outcome = ContentAuditRecord.Outcome
PASSED = {
    s: "passed" for s in ("schema", "references", "content_rules", "review", "solver", "size")
}


@dataclass
class Staging:
    """Writes what staging would publish into `pack_server`, and returns the promotion code."""

    server: PackServer
    pack: dict[str, Any]

    def publish(
        self,
        version: int,
        *,
        pack: dict[str, Any] | None = None,
        file: bytes | None = None,
        **record: Any,
    ) -> str:
        data = {**(pack or self.pack), "version": version}
        pack_file = file if file is not None else build_pack_file(canonical_bytes(data))
        document = {
            "built_at": "2026-11-02T10:00:00Z",
            "min_client_version": "1.0.0",
            "pack_id": "core",
            "published_at": "2026-11-02T10:05:00Z",
            "schema_version": "1.0",
            "sha256": hashlib.sha256(pack_file).hexdigest(),
            "size": len(pack_file),
            "stages": PASSED,
            "version": version,
            "warnings": [],
            **record,
        }
        record_bytes = canonical_bytes(document)
        (self.server.root / f"core-{version}.json.gz").write_bytes(pack_file)
        (self.server.root / f"core-{version}.release.json").write_bytes(record_bytes)
        return f"core-{version}:{hashlib.sha256(record_bytes).hexdigest()}"


@pytest.fixture
def staging(
    sample_imported: User,
    pack_server: PackServer,
    packs_dir: Path,
    settings: Settings,
    monkeypatch: pytest.MonkeyPatch,
) -> Staging:
    """The sample as staging's pack, and this test as production."""
    content = build.produce(snapshot("1.0"), 1, None, review=False).pack
    settings.CONTENT_ROLE = "target"
    settings.CONTENT_PROMOTION_SOURCE_URL = pack_server.url
    monkeypatch.setattr(http, "BACKOFF_SECONDS", 0)
    return Staging(server=pack_server, pack=content)


def current() -> ContentPack | None:
    return ContentChannel.objects.get(pack_id="core").current


def failures() -> list[str]:
    rows = ContentAuditRecord.objects.filter(action=Action.PROMOTE, outcome=Outcome.FAILED)
    return [row.details["reason"] for row in rows.order_by("at")]


def floor(packs_dir: Path) -> int | None:
    path = packs_dir / "core.floor.json"
    return int(json.loads(path.read_bytes())["max_version"]) if path.exists() else None


# -- the happy path (US5-1) -----------------------------------------------------------------------


def test_a_promotion_stores_the_identical_pack(
    staging: Staging,
    publisher: User,
    packs_dir: Path,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    code = staging.publish(15)

    with django_capture_on_commit_callbacks(execute=True):
        pack = promote.promote(code, publisher)

    assert pack is not None
    served = staging.server.root
    assert (pack.origin, pack.status, pack.version) == (Origin.PROMOTED, Status.PUBLISHED, 15)
    assert bytes(pack.file) == (served / "core-15.json.gz").read_bytes()
    assert bytes(pack.release_file) == (served / "core-15.release.json").read_bytes()
    assert (packs_dir / "core-15.json.gz").read_bytes() == bytes(pack.file)
    assert (packs_dir / "core-15.release.json").read_bytes() == bytes(pack.release_file)
    assert pack.release_sha256 == code.split(":")[1]
    assert (pack.promoted_by, pack.build_state, pack.min_client_version) == (
        "publisher1",
        "",
        "1.0.0",
    )
    assert current() == pack
    assert PackTripIndex.objects.filter(pack=pack).count() == len(staging.pack["trips"])
    assert floor(packs_dir) == 15
    [record] = ContentAuditRecord.objects.filter(action=Action.PROMOTE)
    assert (record.outcome, record.version, record.actor) == (Outcome.SUCCEEDED, 15, "publisher1")
    assert record.details["record"]["sha256"] == pack.sha256
    assert staging.server.requests == ["/packs/core-15.release.json", "/packs/core-15.json.gz"]


def test_a_size_warning_still_promotes(staging: Staging, publisher: User) -> None:
    code = staging.publish(3, stages={**PASSED, "size": "warning"})
    assert promote.promote(code, publisher) is not None


def test_the_job_promotes_with_its_actor_checked_again(staging: Staging, publisher: User) -> None:
    code = staging.publish(4)

    tasks.promote_pack.apply(args=(code, "nobody")).get()
    assert current() is None
    tasks.promote_pack.apply(args=(code, "publisher1")).get()

    assert current() is not None
    assert len(failures()) == 1


# -- failures (US5-2, US5-3, US5-4) ---------------------------------------------------------------


def refused(staging: Staging, publisher: User, code: str, reason: str) -> None:
    before = current()
    assert promote.promote(code, publisher) is None
    assert current() == before
    assert failures()[-1].startswith(reason), failures()


@pytest.mark.parametrize(
    "code", ["core-3", "core-3:abc", "core-x:" + "0" * 64, "", "CORE-3:" + "a" * 64]
)
def test_a_malformed_code_is_refused_before_any_fetch(
    staging: Staging, publisher: User, code: str
) -> None:
    refused(staging, publisher, code, "A promotion code looks like")
    assert staging.server.requests == []


def test_a_wrong_code_is_a_release_mismatch(staging: Staging, publisher: User) -> None:
    staging.publish(3)
    refused(staging, publisher, "core-3:" + "0" * 64, "release_mismatch")


def test_a_tampered_pack_is_a_pack_mismatch(staging: Staging, publisher: User) -> None:
    code = staging.publish(3)
    (staging.server.root / "core-3.json.gz").write_bytes(b"tampered")
    refused(staging, publisher, code, "pack_mismatch")


def test_a_size_mismatch_is_a_pack_mismatch(staging: Staging, publisher: User) -> None:
    pack_file = build_pack_file(canonical_bytes({**staging.pack, "version": 3}))
    code = staging.publish(3, size=len(pack_file) + 1)
    refused(staging, publisher, code, "pack_mismatch")


def test_a_version_not_above_current_is_refused(staging: Staging, publisher: User) -> None:
    assert promote.promote(staging.publish(5), publisher) is not None
    code = staging.publish(4)
    staging.server.requests.clear()

    refused(staging, publisher, code, "Version 4 isn't above production's current pack, 5")
    assert staging.server.requests == []


@pytest.mark.parametrize(
    "stages",
    [
        {**PASSED, "solver": "not_available"},
        {**PASSED, "references": "failed"},
        {**PASSED, "review": "warning"},
        {k: v for k, v in PASSED.items() if k != "solver"},
    ],
)
def test_a_stage_that_did_not_pass_is_release_not_passed(
    staging: Staging, publisher: User, stages: dict[str, str]
) -> None:
    refused(staging, publisher, staging.publish(3, stages=stages), "release_not_passed")


def test_a_release_record_over_64_kib_is_refused(staging: Staging, publisher: User) -> None:
    code = staging.publish(3, warnings=[{"message": "x" * (65 * 1024)}])
    refused(staging, publisher, code, "release_mismatch")


def test_a_pack_over_16_mib_is_refused(staging: Staging, publisher: User) -> None:
    big = gzip.compress(b"x", mtime=0) + b"\0" * (16 * 1024 * 1024)
    refused(staging, publisher, staging.publish(3, file=big), "pack_mismatch")


def test_a_pack_over_32_mib_decompressed_is_invalid(staging: Staging, publisher: User) -> None:
    bomb = gzip.compress(b" " * (33 * 1024 * 1024), mtime=0)
    refused(staging, publisher, staging.publish(3, file=bomb), "pack_invalid")


def test_a_pack_that_fails_its_schema_is_invalid(staging: Staging, publisher: User) -> None:
    broken = {k: v for k, v in staging.pack.items() if k != "tasks"}
    refused(staging, publisher, staging.publish(3, pack=broken), "pack_invalid")
    details = ContentAuditRecord.objects.filter(outcome=Outcome.FAILED).get().details
    assert details["findings"]
    assert {f["code"] for f in details["findings"]} == {"V-SC"}


def test_a_pack_that_differs_from_its_record_is_invalid(staging: Staging, publisher: User) -> None:
    refused(staging, publisher, staging.publish(3, schema_version="1.1"), "pack_invalid")


def test_a_minimum_below_the_floor_is_invalid(staging: Staging, publisher: User) -> None:
    code = staging.publish(3, min_client_version="0.9.0")
    refused(staging, publisher, code, "pack_invalid")


def test_staging_unreachable_then_a_retry_succeeds(
    staging: Staging, publisher: User, packs_dir: Path
) -> None:
    code = staging.publish(3)
    staging.server.mode = "error"
    refused(staging, publisher, code, "release_unreachable")
    assert len(staging.server.requests) == http.RETRIES + 1
    assert floor(packs_dir) is None

    staging.server.mode = "serve"
    assert promote.promote(code, publisher) is not None


def test_the_same_bytes_already_stored_count_as_stored(
    staging: Staging, publisher: User, packs_dir: Path
) -> None:
    code = staging.publish(3)
    (packs_dir / "core-3.json.gz").write_bytes(
        (staging.server.root / "core-3.json.gz").read_bytes()
    )

    assert promote.promote(code, publisher) is not None


def test_different_bytes_already_stored_are_a_storage_error(
    staging: Staging, publisher: User, packs_dir: Path
) -> None:
    code = staging.publish(3)
    (packs_dir / "core-3.json.gz").write_bytes(b"other")
    refused(staging, publisher, code, "storage_error")
    assert (packs_dir / "core-3.json.gz").read_bytes() == b"other"


# -- the floor file -------------------------------------------------------------------------------


def test_the_floor_is_raised_before_the_commit(
    staging: Staging, publisher: User, packs_dir: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    def broken(*args: Any) -> None:
        raise RuntimeError("the commit fails")

    monkeypatch.setattr(lookups, "index_pack", broken)

    refused(staging, publisher, staging.publish(15), "storage_error")

    assert floor(packs_dir) == 15
    assert not ContentPack.objects.exists()


def test_the_floor_never_goes_down(staging: Staging, publisher: User, packs_dir: Path) -> None:
    (packs_dir / "core.floor.json").write_bytes(b'{"max_version":20,"pack_id":"core"}')

    assert promote.promote(staging.publish(16), publisher) is not None
    assert floor(packs_dir) == 20


def test_a_failure_before_the_files_are_confirmed_leaves_the_floor(
    staging: Staging, publisher: User, packs_dir: Path
) -> None:
    (packs_dir / "core.floor.json").write_bytes(b'{"max_version":2,"pack_id":"core"}')
    code = staging.publish(3)
    (staging.server.root / "core-3.json.gz").write_bytes(b"tampered")

    refused(staging, publisher, code, "pack_mismatch")
    assert floor(packs_dir) == 2


def test_sync_raises_a_floor_behind_the_database(
    staging: Staging, publisher: User, packs_dir: Path
) -> None:
    assert promote.promote(staging.publish(7), publisher) is not None
    (packs_dir / "core.floor.json").write_bytes(b'{"max_version":3,"pack_id":"core"}')

    files.sync_files(verify=True)

    assert floor(packs_dir) == 7


# -- roles and the admin (US5-5) ------------------------------------------------------------------


def test_promotion_is_refused_on_the_source(
    staging: Staging, publisher: User, settings: Settings
) -> None:
    code = staging.publish(3)
    settings.CONTENT_ROLE = "source"
    with pytest.raises(PermissionDenied):
        promote.request_promotion(code, publisher)
    assert promote.promote(code, publisher) is None
    assert staging.server.requests == []


def test_promotion_needs_promote_pack(staging: Staging, sample_imported: User) -> None:
    code = staging.publish(3)
    assert promote.promote(code, sample_imported) is None
    assert staging.server.requests == []


@pytest.mark.urls("config.urls_admin")
def test_production_admin_offers_promotion_and_no_authoring(
    staging: Staging,
    publisher: User,
    monkeypatch: pytest.MonkeyPatch,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    calls: list[tuple[str, str]] = []
    monkeypatch.setattr(tasks.promote_pack, "delay", lambda *args: calls.append(args))
    client = admin_client(publisher)

    changelist = client.get("/admin/content/contentpack/").content.decode()
    assert "Promote from staging" in changelist
    for offered in ("Build a new pack", "Import zip", "Export current content"):
        assert offered not in changelist
    assert client.get("/admin/content/trip/add/").status_code == 403
    assert client.post("/admin/content/contentpack/build/").status_code == 403

    bad = client.post("/admin/content/contentpack/promote/", {"code": "core-3"})
    assert "A promotion code looks like" in bad.content.decode()
    code = staging.publish(3)
    with django_capture_on_commit_callbacks(execute=True):
        response = client.post("/admin/content/contentpack/promote/", {"code": code})

    assert response.status_code == 302
    assert calls == [(code, "publisher1")]


@pytest.mark.urls("config.urls_admin")
def test_the_promotion_form_needs_the_permission_on_production(
    staging: Staging, plain_staff: User, publisher: User, settings: Settings
) -> None:
    assert admin_client(plain_staff).get("/admin/content/contentpack/promote/").status_code == 403
    settings.CONTENT_ROLE = "source"
    assert admin_client(publisher).get("/admin/content/contentpack/promote/").status_code == 403
