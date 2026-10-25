"""Publishing on staging (tasks.md T077, contracts/pack-delivery.md "Publish on staging")."""

from __future__ import annotations

import hashlib
import json
import logging
import os
import stat
from pathlib import Path

import pytest
from pytest_django import DjangoCaptureOnCommitCallbacks, Settings
from wassal_content.canonical import canonical_bytes

from apps.accounts.models import User
from apps.content import tasks
from apps.content.errors import ImmutableError
from apps.content.models import (
    ContentAuditRecord,
    ContentChannel,
    ContentPack,
    PackPriceIndex,
    PackTripIndex,
    PublishedIdentifier,
)
from apps.content.models.packs import Status
from apps.content.services import exporter, files, manifest, permanence, publish
from apps.content.tests.test_build import built

pytestmark = pytest.mark.django_db

Action = ContentAuditRecord.Action
Outcome = ContentAuditRecord.Outcome


@pytest.fixture(autouse=True)
def _packs(packs_dir: Path) -> Path:
    return packs_dir


def published(pack: ContentPack, publisher: User) -> ContentPack:
    result = publish.publish(str(pack.pk), publisher)
    assert result.status == Status.PUBLISHED, result.failure_reason
    return result


def audits(action: str = Action.PUBLISH) -> list[tuple[str, int | None, str]]:
    rows = ContentAuditRecord.objects.filter(action=action).order_by("at")
    return [(row.outcome, row.version, row.actor) for row in rows]


def current() -> ContentPack | None:
    return ContentChannel.objects.get(pack_id="core").current


# -- the happy path (US4-1, US4-8) ----------------------------------------------------------------


def test_a_publish_writes_the_files_and_commits(
    sample_reviewed: User,
    publisher: User,
    packs_dir: Path,
    monkeypatch: pytest.MonkeyPatch,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    pack = built(sample_reviewed)
    invalidated: list[bool] = []
    monkeypatch.setattr(manifest, "invalidate", lambda: invalidated.append(True))

    with django_capture_on_commit_callbacks(execute=True):
        pack = published(pack, publisher)

    pack_file, record_file = packs_dir / "core-1.json.gz", packs_dir / "core-1.release.json"
    assert pack_file.read_bytes() == bytes(pack.file)
    assert record_file.read_bytes() == bytes(pack.release_file)
    assert hashlib.sha256(record_file.read_bytes()).hexdigest() == pack.release_sha256
    for path in (pack_file, record_file):
        assert stat.S_IMODE(path.stat().st_mode) == files.FILE_MODE
    assert sorted(p.name for p in packs_dir.iterdir()) == [
        "core-1.json.gz",
        "core-1.release.json",
    ]
    assert current() == pack
    assert (pack.published_by, pack.failure_reason) == ("publisher1", "")
    assert pack.published_at is not None
    data = exporter.stored_pack(pack)
    assert PublishedIdentifier.objects.count() == len(set(permanence.identifiers(data)))
    assert PackTripIndex.objects.filter(pack=pack).count() == len(data["trips"])
    assert PackPriceIndex.objects.filter(pack=pack).count() == len(data["catalog"]["prices"])
    assert audits() == [(Outcome.SUCCEEDED, 1, "publisher1")]
    assert invalidated == [True]


def test_the_sixth_newest_is_retired_and_keeps_its_file(
    sample_reviewed: User, publisher: User, packs_dir: Path, settings: Settings
) -> None:
    settings.CONTENT_INDEX_KEEP = 5  # B04's number; B03 made it a setting
    packs = [published(built(sample_reviewed), publisher) for _ in range(6)]

    first = ContentPack.objects.get(pk=packs[0].pk)
    assert first.status == Status.RETIRED
    assert not PackTripIndex.objects.filter(pack=first).exists()
    assert not PackPriceIndex.objects.filter(pack=first).exists()
    assert (packs_dir / "core-1.json.gz").read_bytes() == bytes(first.file)
    statuses = ContentPack.objects.order_by("version").values_list("status", flat=True)
    assert list(statuses) == [Status.RETIRED] + [Status.PUBLISHED] * 5
    assert current() == packs[-1]
    assert sorted(set(PackTripIndex.objects.values_list("version", flat=True))) == [2, 3, 4, 5, 6]


def test_request_publish_queues_the_job_on_commit(
    sample_reviewed: User,
    publisher: User,
    monkeypatch: pytest.MonkeyPatch,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    pack = built(sample_reviewed)
    calls: list[tuple[str, str]] = []
    monkeypatch.setattr(tasks.publish_pack, "delay", lambda *args: calls.append(args))

    with django_capture_on_commit_callbacks(execute=True):
        publish.request_publish(pack, publisher)

    assert calls == [(str(pack.pk), "publisher1")]
    assert ContentPack.objects.get(pk=pack.pk).status == Status.VALIDATED


def test_the_job_publishes_with_its_actor_checked_again(
    sample_reviewed: User, publisher: User
) -> None:
    pack = built(sample_reviewed)

    tasks.publish_pack.apply(args=(str(pack.pk), "publisher1")).get()
    tasks.publish_pack.apply(args=(str(pack.pk), "nobody")).get()

    assert ContentPack.objects.get(pk=pack.pk).status == Status.PUBLISHED
    assert audits() == [(Outcome.SUCCEEDED, 1, "publisher1"), (Outcome.FAILED, 1, "")]


# -- files already there --------------------------------------------------------------------------


def test_the_same_bytes_under_an_existing_name_count_as_stored(
    sample_reviewed: User, publisher: User, packs_dir: Path
) -> None:
    pack = built(sample_reviewed)
    (packs_dir / "core-1.json.gz").write_bytes(bytes(pack.file))

    assert published(pack, publisher).status == Status.PUBLISHED


def test_different_bytes_under_an_existing_name_are_refused(
    sample_reviewed: User,
    publisher: User,
    packs_dir: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    pack = built(sample_reviewed)
    (packs_dir / "core-1.json.gz").write_bytes(b"something else")

    with caplog.at_level(logging.ERROR):
        result = publish.publish(str(pack.pk), publisher)

    assert result.status == Status.VALIDATED
    assert (
        result.failure_reason == "file_conflict: core-1.json.gz already exists with different bytes"
    )
    assert (packs_dir / "core-1.json.gz").read_bytes() == b"something else"
    assert any(
        r.levelno == logging.ERROR and r.message == "pack file conflict" for r in caplog.records
    )
    assert current() is None
    assert audits() == [(Outcome.FAILED, 1, "publisher1")]


# -- a read-only directory (US4-2, SC-010) ------------------------------------------------------


@pytest.mark.skipif(os.geteuid() == 0, reason="root writes to read-only directories")
def test_a_read_only_directory_fails_and_a_retry_succeeds(
    sample_reviewed: User, publisher: User, packs_dir: Path
) -> None:
    pack = built(sample_reviewed)
    packs_dir.chmod(0o555)
    try:
        failed = publish.publish(str(pack.pk), publisher)
    finally:
        packs_dir.chmod(0o755)

    assert failed.status == Status.VALIDATED
    assert failed.failure_reason == "storage_error: the packs directory isn't writable"
    assert current() is None
    assert not list(packs_dir.iterdir())
    record = ContentPack.objects.get(pk=pack.pk).release_file

    retried = published(pack, publisher)

    assert current() == retried
    assert bytes(retried.release_file) == bytes(record)
    assert audits() == [(Outcome.FAILED, 1, "publisher1"), (Outcome.SUCCEEDED, 1, "publisher1")]


# -- refusals -------------------------------------------------------------------------------------


def test_a_version_not_above_the_current_one_is_refused(
    sample_reviewed: User, publisher: User
) -> None:
    older, newer = built(sample_reviewed), built(sample_reviewed)
    published(newer, publisher)

    result = publish.publish(str(older.pk), publisher)

    assert result.status == Status.VALIDATED
    assert "isn't above the current pack, version 2" in result.failure_reason
    assert current() == newer


def test_a_solver_stage_that_did_not_pass_is_refused(
    sample_reviewed: User, publisher: User, settings: Settings
) -> None:
    settings.CONTENT_SOLVER_STAGE = "none"
    pack = built(sample_reviewed)

    result = publish.publish(str(pack.pk), publisher)

    assert result.status == Status.VALIDATED
    assert "solver stage is not_available" in result.failure_reason
    with pytest.raises(publish.PublishRefused, match="not_available"):
        publish.request_publish(pack, publisher)


def with_solver(pack: ContentPack, result: str) -> ContentPack:
    """The pack with its solver stage's result set, as the real stage would leave it (B05)."""
    report = pack.validation_report
    report["stages"]["solver"]["result"] = result
    ContentPack.objects.filter(pk=pack.pk).update(validation_report=report)
    pack.refresh_from_db()
    return pack


def test_a_solver_warning_still_publishes(sample_reviewed: User, publisher: User) -> None:
    pack = with_solver(built(sample_reviewed), "warning")

    result = published(pack, publisher)

    assert json.loads(bytes(result.release_file))["stages"]["solver"] == "warning"


@pytest.mark.parametrize("result", ["failed", "not_available"])
def test_a_solver_stage_that_failed_or_did_not_run_is_refused(
    sample_reviewed: User, publisher: User, result: str
) -> None:
    pack = with_solver(built(sample_reviewed), result)

    refused = publish.publish(str(pack.pk), publisher)

    assert refused.status == Status.VALIDATED
    assert f"solver stage is {result}, not passed" in refused.failure_reason


def test_a_draft_is_refused(sample_imported: User, publisher: User) -> None:
    pack = built(sample_imported)

    result = publish.publish(str(pack.pk), publisher)

    assert result.status == Status.DRAFT
    assert "not validated" in result.failure_reason


def test_publishing_needs_publish_pack_on_the_source(
    sample_reviewed: User, publisher: User, plain_staff: User, settings: Settings
) -> None:
    pack = built(sample_reviewed)
    for actor in (None, plain_staff, sample_reviewed):
        assert publish.publish(str(pack.pk), actor).status == Status.VALIDATED
    settings.CONTENT_ROLE = "target"
    assert publish.publish(str(pack.pk), publisher).status == Status.VALIDATED

    assert current() is None
    assert [outcome for outcome, _, _ in audits()] == [Outcome.FAILED] * 4


def test_publishing_twice_changes_nothing(sample_reviewed: User, publisher: User) -> None:
    pack = published(built(sample_reviewed), publisher)

    again = publish.publish(str(pack.pk), publisher)

    assert again.status == Status.PUBLISHED
    assert again.failure_reason == ""
    assert audits() == [(Outcome.SUCCEEDED, 1, "publisher1"), (Outcome.FAILED, 1, "publisher1")]


# -- the release record ---------------------------------------------------------------------------


def test_the_release_record_is_canonical_and_names_no_one(
    sample_reviewed: User, publisher: User
) -> None:
    pack = published(built(sample_reviewed), publisher)
    data = bytes(pack.release_file)
    record = json.loads(data)

    assert canonical_bytes(record) == data
    assert hashlib.sha256(data).hexdigest() == pack.release_sha256
    assert sorted(record) == [
        "built_at",
        "min_client_version",
        "pack_id",
        "published_at",
        "schema_version",
        "sha256",
        "size",
        "solver",
        "stages",
        "version",
        "warnings",
    ]
    assert (record["version"], record["sha256"], record["size"]) == (1, pack.sha256, pack.size)
    assert record["solver"] == {"stand_in": True, "trips": []}
    assert set(record["stages"].values()) == {"passed"}
    assert record["warnings"] == []
    for name in ("author1", "publisher1"):
        assert name not in data.decode()


def test_a_size_warning_is_listed_in_the_record(
    sample_reviewed: User, publisher: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    from wassal_content.rules import size

    monkeypatch.setattr(size, "SIZE_WARNING_BYTES", 100)
    pack = published(built(sample_reviewed), publisher)

    record = json.loads(bytes(pack.release_file))
    assert record["stages"]["size"] == "warning"
    assert [w["code"] for w in record["warnings"]] == ["V-S1"]
    assert sorted(record["warnings"][0]) == ["code", "entity", "id", "message", "path"]


def test_staging_never_writes_a_floor_file(
    sample_reviewed: User, publisher: User, packs_dir: Path
) -> None:
    published(built(sample_reviewed), publisher)

    assert not (packs_dir / "core.floor.json").exists()
    with pytest.raises(RuntimeError, match="only production"):
        files.write_floor(5)


# -- immutability (US4-3, FR-027) -----------------------------------------------------------------


def test_a_published_pack_changes_only_its_minimum_app_version(
    sample_reviewed: User, publisher: User
) -> None:
    pack = published(built(sample_reviewed), publisher)

    for name, value in (("sha256", "0" * 64), ("size", 1), ("release_sha256", "1" * 64)):
        stored = ContentPack.objects.get(pk=pack.pk)
        setattr(stored, name, value)
        with pytest.raises(ImmutableError, match=name):
            stored.save()
    stored = ContentPack.objects.get(pk=pack.pk)
    stored.min_client_version = "1.2.0"
    stored.save()
