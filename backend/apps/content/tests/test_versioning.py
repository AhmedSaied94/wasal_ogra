"""Version numbers (tasks.md T070, contracts/pack-delivery.md "Version numbers", research R7)."""

from __future__ import annotations

import json
import shutil
import threading
import time
from pathlib import Path

import pytest
from django.db import connection, transaction
from pytest_django import Settings

from apps.accounts.models import User
from apps.content.models import ContentChannel, ContentPack
from apps.content.models.packs import BuildState
from apps.content.services import build, http, importer, versioning
from apps.content.tests.conftest import SAMPLE, PackServer
from apps.content.tests.factories import gzip_bytes

pytestmark = pytest.mark.django_db


@pytest.fixture
def floor_server(pack_server: PackServer, settings: Settings) -> PackServer:
    """`pack_server` as production's packs URL, with no backoff between retries."""
    settings.CONTENT_VERSION_FLOOR_URL = pack_server.url
    return pack_server


@pytest.fixture(autouse=True)
def _no_backoff(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(http, "BACKOFF_SECONDS", 0)


def assigned(channel: ContentChannel, last: int) -> ContentChannel:
    ContentChannel.objects.filter(pk=channel.pk).update(last_assigned_version=last)
    channel.refresh_from_db()
    return channel


def floor(server: PackServer, body: bytes) -> None:
    (server.root / versioning.FLOOR_FILE).write_bytes(body)


def floor_json(max_version: object, pack_id: str = "core") -> bytes:
    return json.dumps({"max_version": max_version, "pack_id": pack_id}).encode()


def last_assigned() -> int:
    return ContentChannel.objects.get(pack_id="core").last_assigned_version


# -- the floor file -------------------------------------------------------------------------------


def test_a_floor_above_staging_raises_the_next_version(
    channel: ContentChannel, floor_server: PackServer
) -> None:
    assigned(channel, 12)
    floor(floor_server, floor_json(14))

    assert versioning.next_version() == 15
    assert last_assigned() == 15
    assert floor_server.requests == ["/packs/core.floor.json"]


def test_a_floor_below_staging_changes_nothing(
    channel: ContentChannel, floor_server: PackServer
) -> None:
    assigned(channel, 12)
    floor(floor_server, floor_json(3))

    assert versioning.next_version() == 13


def test_gaps_in_production_do_not_matter(
    channel: ContentChannel, floor_server: PackServer
) -> None:
    assigned(channel, 12)
    for version in (12, 14):
        (floor_server.root / f"core-{version}.json.gz").write_bytes(gzip_bytes(version))
    floor(floor_server, floor_json(14))

    assert versioning.next_version() == 15


REFUSALS = {
    "404": lambda server: None,
    "500": lambda server: setattr(server, "mode", "error"),
    "dropped connection": lambda server: setattr(server, "mode", "drop"),
    "over 1 KiB": lambda server: floor(
        server, json.dumps({"max_version": 14, "pack_id": "core", "pad": "x" * 1100}).encode()
    ),
    "invalid JSON": lambda server: floor(server, b'{"max_version": 14,'),
    "float max_version": lambda server: floor(server, floor_json(14.0)),
    "negative max_version": lambda server: floor(server, floor_json(-1)),
    "string max_version": lambda server: floor(server, floor_json("14")),
    "wrong pack_id": lambda server: floor(server, floor_json(14, pack_id="other")),
    "not an object": lambda server: floor(server, b"[14]"),
}


@pytest.mark.parametrize("case", sorted(REFUSALS))
def test_any_other_answer_refuses_the_build(
    case: str, channel: ContentChannel, floor_server: PackServer, author: User
) -> None:
    assigned(channel, 12)
    REFUSALS[case](floor_server)
    draft = build.new_draft(author)

    with pytest.raises(versioning.VersionFloorUnavailable):
        versioning.next_version()
    pack = build.run_build(str(draft.pk))

    assert pack.build_state == BuildState.FAILED
    assert pack.failure_reason.startswith("version_floor_unavailable: ")
    assert ContentPack.objects.get(pk=draft.pk).version is None
    assert last_assigned() == 12


def test_a_timeout_refuses_the_build_after_the_retries(
    channel: ContentChannel, floor_server: PackServer, settings: Settings
) -> None:
    settings.CONTENT_HTTP_TIMEOUT_SECONDS = 1
    floor_server.mode, floor_server.delay = "slow", 1.5
    floor(floor_server, floor_json(14))

    with pytest.raises(versioning.VersionFloorUnavailable, match="unreachable"):
        versioning.next_version()

    assert len(floor_server.requests) == http.RETRIES + 1
    assert last_assigned() == 0


def test_a_server_error_is_retried(
    channel: ContentChannel, floor_server: PackServer, monkeypatch: pytest.MonkeyPatch
) -> None:
    floor(floor_server, floor_json(14))
    answers = iter([http.FetchError("status", 503)])
    real = http._get

    def flaky(url: str, max_bytes: int) -> bytes:
        error = next(answers, None)
        if error is not None:
            raise error
        return real(url, max_bytes)

    monkeypatch.setattr(http, "_get", flaky)

    assert versioning.next_version() == 15


def test_a_404_is_not_retried(channel: ContentChannel, floor_server: PackServer) -> None:
    with pytest.raises(versioning.VersionFloorUnavailable, match="status 404"):
        versioning.next_version()
    assert len(floor_server.requests) == 1


def test_without_a_floor_url_nothing_is_fetched(
    channel: ContentChannel, pack_server: PackServer, settings: Settings
) -> None:
    settings.CONTENT_VERSION_FLOOR_URL = ""
    floor(pack_server, floor_json(40))

    assert versioning.next_version() == 1
    assert pack_server.requests == []


def test_a_dry_run_peeks_without_assigning(
    channel: ContentChannel, floor_server: PackServer
) -> None:
    assigned(channel, 12)
    floor(floor_server, floor_json(14))

    assert versioning.peek_next_version() == 15
    assert last_assigned() == 12


# -- imports (research R7, input B) ---------------------------------------------------------------


def test_an_imported_version_raises_the_next_version(
    channel: ContentChannel, author: User, tmp_path: Path
) -> None:
    layout = tmp_path / "source"
    shutil.copytree(SAMPLE, layout)
    meta = json.loads((layout / "pack.json").read_text())
    (layout / "pack.json").write_text(json.dumps({**meta, "version": 9}))

    importer.import_dir(layout, author)

    assert ContentChannel.objects.get(pack_id="core").imported_version == 9
    assert versioning.next_version() == 10


# -- concurrency -------------------------------------------------------------------------------


@pytest.mark.django_db(transaction=True)
def test_concurrent_builds_get_distinct_consecutive_versions(channel: ContentChannel) -> None:
    assigned(channel, 4)
    start = threading.Barrier(2)
    versions: list[int] = []

    def assign() -> None:
        try:
            start.wait(timeout=5)
            versions.append(versioning.next_version())
        finally:
            connection.close()

    workers = [threading.Thread(target=assign) for _ in range(2)]
    for worker in workers:
        worker.start()
    for worker in workers:
        worker.join(timeout=10)

    assert sorted(versions) == [5, 6]
    assert last_assigned() == 6


@pytest.mark.django_db(transaction=True)
def test_the_floor_is_read_before_the_row_lock(
    channel: ContentChannel, floor_server: PackServer
) -> None:
    floor_server.mode, floor_server.delay = "slow", 2.0
    floor(floor_server, floor_json(14))
    versions: list[int] = []

    def assign() -> None:
        try:
            versions.append(versioning.next_version())
        finally:
            connection.close()

    worker = threading.Thread(target=assign)
    worker.start()
    deadline = time.monotonic() + 5
    while not floor_server.requests and time.monotonic() < deadline:
        time.sleep(0.05)
    assert floor_server.requests, "the floor file was never asked for"

    # The build waits on production; the channel row must still be free.
    with transaction.atomic():
        locked = ContentChannel.objects.select_for_update(nowait=True).get(pack_id="core")
        assert locked.last_assigned_version == 0

    worker.join(timeout=10)
    assert versions == [15]
