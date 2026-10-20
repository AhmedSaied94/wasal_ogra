"""Rebuilding staging's version numbering after losing it (tasks.md T094, US5-6, SC-013).

Staging comes back empty, `content/source` (the last promoted state, `pack.json` version 12) is
imported, and production holds packs 12 and 14 with a floor file of 14: 13 is a gap.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest
from pytest_django import Settings

from apps.accounts.models import User
from apps.content.models import ContentChannel, ContentPack
from apps.content.models.packs import BuildState
from apps.content.services import build, http, importer
from apps.content.tests.conftest import SAMPLE, PackServer
from apps.content.tests.factories import gzip_bytes

pytestmark = pytest.mark.django_db


@pytest.fixture
def rebuilt_staging(
    author: User,
    pack_server: PackServer,
    settings: Settings,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> PackServer:
    """An empty staging database with `content/source` at version 12 imported."""
    assert not ContentPack.objects.exists()
    layout = tmp_path / "source"
    shutil.copytree(SAMPLE, layout)
    meta = json.loads((layout / "pack.json").read_text())
    (layout / "pack.json").write_text(json.dumps({**meta, "version": 12}))
    importer.import_dir(layout, author)
    for version in (12, 14):
        (pack_server.root / f"core-{version}.json.gz").write_bytes(gzip_bytes(version))
    settings.CONTENT_VERSION_FLOOR_URL = pack_server.url
    monkeypatch.setattr(http, "BACKOFF_SECONDS", 0)
    return pack_server


def test_the_next_build_is_above_production_and_its_gap(
    rebuilt_staging: PackServer, author: User
) -> None:
    (rebuilt_staging.root / "core.floor.json").write_bytes(b'{"max_version":14,"pack_id":"core"}')

    pack = build.run_build(str(build.new_draft(author).pk))

    assert pack.build_state == BuildState.FINISHED
    assert pack.version == 15
    assert ContentChannel.objects.get(pack_id="core").last_assigned_version == 15


def test_without_the_floor_file_the_build_is_refused(
    rebuilt_staging: PackServer, author: User
) -> None:
    pack = build.run_build(str(build.new_draft(author).pk))

    assert pack.build_state == BuildState.FAILED
    assert pack.failure_reason == "version_floor_unavailable: status 404"
    assert pack.version is None
    channel = ContentChannel.objects.get(pack_id="core")
    assert (channel.last_assigned_version, channel.imported_version) == (0, 12)
