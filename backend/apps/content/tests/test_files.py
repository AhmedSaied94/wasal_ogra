"""Pack files on the host (tasks.md T082, contracts/pack-delivery.md)."""

from __future__ import annotations

import fcntl
import hashlib
import json
import logging
import os
import stat
import threading
from io import StringIO
from pathlib import Path

import pytest
from django.core.management import CommandError, call_command
from pytest_django import Settings

from apps.content import checks, tasks
from apps.content.models import ContentPack
from apps.content.models.packs import Status
from apps.content.services import files
from apps.content.tests.factories import pack, promoted

pytestmark = pytest.mark.django_db


@pytest.fixture
def target(settings: Settings) -> None:
    settings.CONTENT_ROLE = "target"


def stored(version: int, status: str = Status.PUBLISHED) -> ContentPack:
    """A stored pack whose release record is kept, as publish keeps it."""
    made = pack(version, status)
    record = json.dumps({"version": version}).encode()
    ContentPack.objects.filter(pk=made.pk).update(
        release_file=record, release_sha256=hashlib.sha256(record).hexdigest()
    )
    return ContentPack.objects.get(pk=made.pk)


# -- create-only writes ---------------------------------------------------------------------------


def test_create_only_writes_once(packs_dir: Path) -> None:
    path = packs_dir / "core-1.json.gz"

    assert files.write_create_only(path, b"abc") is True
    assert files.write_create_only(path, b"abc") is False
    with pytest.raises(files.FileConflict, match=r"core-1\.json\.gz"):
        files.write_create_only(path, b"other")

    assert path.read_bytes() == b"abc"
    assert stat.S_IMODE(path.stat().st_mode) == 0o644
    assert [p.name for p in packs_dir.iterdir()] == ["core-1.json.gz"]  # no temporary left


def test_a_failed_write_leaves_no_file(packs_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    def broken_link(*args: object) -> None:
        raise OSError("disk full")

    monkeypatch.setattr(os, "link", broken_link)

    with pytest.raises(OSError, match="disk full"):
        files.write_create_only(packs_dir / "core-1.json.gz", b"abc")
    assert list(packs_dir.iterdir()) == []


# -- the floor file -------------------------------------------------------------------------------


def floor(packs_dir: Path) -> dict[str, object]:
    return dict(json.loads((packs_dir / "core.floor.json").read_bytes()))


@pytest.mark.usefixtures("target")
def test_the_floor_only_goes_up(packs_dir: Path) -> None:
    assert files.write_floor(7) == 7
    assert (packs_dir / "core.floor.json").read_bytes() == b'{"max_version":7,"pack_id":"core"}'
    assert files.write_floor(3) == 7
    assert files.write_floor(9) == 9

    assert floor(packs_dir) == {"max_version": 9, "pack_id": "core"}
    assert stat.S_IMODE((packs_dir / "core.floor.json").stat().st_mode) == 0o644
    assert sorted(p.name for p in packs_dir.iterdir()) == ["core.floor.json"]


@pytest.mark.usefixtures("target")
def test_raising_the_floor_waits_for_the_directory_lock(packs_dir: Path) -> None:
    files.write_floor(1)  # so the thread below needs no database
    held = os.open(packs_dir, os.O_RDONLY)
    fcntl.flock(held, fcntl.LOCK_EX)
    done = threading.Event()

    def raise_floor() -> None:
        files.write_floor(4)
        done.set()

    worker = threading.Thread(target=raise_floor)
    worker.start()
    try:
        assert not done.wait(0.3)
    finally:
        os.close(held)
    worker.join(timeout=5)

    assert done.is_set()
    assert floor(packs_dir)["max_version"] == 4


@pytest.mark.usefixtures("target")
def test_a_floor_that_does_not_parse_is_replaced_from_the_database(
    packs_dir: Path, caplog: pytest.LogCaptureFixture
) -> None:
    promoted(12)
    (packs_dir / "core.floor.json").write_bytes(b"{broken")

    with caplog.at_level(logging.ERROR):
        assert files.write_floor(5) == 12

    assert floor(packs_dir)["max_version"] == 12
    assert any(r.levelno == logging.ERROR for r in caplog.records)


@pytest.mark.usefixtures("target")
def test_ensure_floor_creates_a_missing_file(packs_dir: Path) -> None:
    files.ensure_floor()
    assert floor(packs_dir)["max_version"] == 0

    promoted(4)
    files.ensure_floor()  # present: left alone
    assert floor(packs_dir)["max_version"] == 0


def test_ensure_floor_does_nothing_on_the_source(packs_dir: Path) -> None:
    files.ensure_floor()
    assert not (packs_dir / "core.floor.json").exists()


@pytest.mark.usefixtures("target")
def test_the_worker_start_check_creates_the_floor(packs_dir: Path) -> None:
    promoted(3)
    checks.check_packs_dir_on_worker_start()
    assert floor(packs_dir)["max_version"] == 3


# -- sync (contracts/pack-delivery.md "Keeping files and records together") -----------------------


def test_sync_rewrites_missing_files(packs_dir: Path) -> None:
    one, two = stored(1, Status.RETIRED), stored(2)
    pack(3, Status.VALIDATED)

    result = files.sync_files(verify=False)

    assert result.written == [
        "core-1.json.gz",
        "core-1.release.json",
        "core-2.json.gz",
        "core-2.release.json",
    ]
    assert (packs_dir / "core-1.json.gz").read_bytes() == bytes(one.file)
    assert (packs_dir / "core-2.release.json").read_bytes() == bytes(two.release_file)
    assert files.sync_files(verify=False).written == []


def test_verify_reports_a_mismatch_and_leaves_the_file(
    packs_dir: Path, caplog: pytest.LogCaptureFixture
) -> None:
    stored(1)
    files.sync_files(verify=False)
    (packs_dir / "core-1.json.gz").write_bytes(b"tampered")

    with caplog.at_level(logging.ERROR):
        result = files.sync_files(verify=True)

    assert result.problems == ["core-1.json.gz doesn't match its record"]
    assert result.verified == 1
    assert (packs_dir / "core-1.json.gz").read_bytes() == b"tampered"
    assert any(r.levelno == logging.ERROR for r in caplog.records)


def test_sync_never_writes_a_database_copy_that_does_not_match(packs_dir: Path) -> None:
    broken = stored(1)
    ContentPack.objects.filter(pk=broken.pk).update(sha256="0" * 64)

    result = files.sync_files(verify=False)

    assert result.written == ["core-1.release.json"]
    assert "core-1.json.gz: the database copy doesn't match its record" in result.problems
    assert not (packs_dir / "core-1.json.gz").exists()


@pytest.mark.usefixtures("target")
def test_sync_raises_the_floor_on_production(packs_dir: Path) -> None:
    stored(6)
    files.sync_files(verify=True)
    assert floor(packs_dir)["max_version"] == 6


def test_the_command_and_the_task(packs_dir: Path) -> None:
    stored(1)
    out = StringIO()
    call_command("content_files", "sync", "--verify", stdout=out)
    assert "wrote core-1.json.gz\n" in out.getvalue()
    assert "files in sync" in out.getvalue()

    tasks.sync_files.apply(kwargs={"verify": True}).get()

    (packs_dir / "core-1.json.gz").write_bytes(b"tampered")
    with pytest.raises(CommandError, match="1 problems"):
        call_command("content_files", "sync", "--verify", stdout=StringIO(), stderr=StringIO())
