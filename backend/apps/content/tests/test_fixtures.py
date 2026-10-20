"""The shared fixtures behave as the tests that use them expect (tasks.md T057)."""

from __future__ import annotations

from pathlib import Path

import pytest
import requests
from django.conf import settings

from apps.accounts.models import User
from apps.content.tests.conftest import PackServer


def test_packs_dir_is_the_settings_value(packs_dir: Path) -> None:
    assert packs_dir == settings.CONTENT_PACKS_DIR
    assert packs_dir.is_dir()


def test_the_pack_server_serves_its_directory(pack_server: PackServer) -> None:
    (pack_server.root / "core.floor.json").write_text('{"version": 3}')

    answer = requests.get(f"{pack_server.url}core.floor.json", timeout=2)

    assert answer.status_code == 200
    assert answer.json() == {"version": 3}
    assert pack_server.requests == ["/packs/core.floor.json"]


def test_the_pack_server_can_fail(pack_server: PackServer) -> None:
    (pack_server.root / "core.floor.json").write_text("{}")
    url = f"{pack_server.url}core.floor.json"

    pack_server.mode = "error"
    assert requests.get(url, timeout=2).status_code == 500
    pack_server.mode = "drop"
    with pytest.raises(requests.ConnectionError):
        requests.get(url, timeout=2)
    pack_server.mode, pack_server.delay = "slow", 0.5
    with pytest.raises(requests.Timeout):
        requests.get(url, timeout=0.2)


@pytest.mark.django_db
def test_the_users_have_their_groups(
    author: User, publisher: User, plain_staff: User, inactive_author: User
) -> None:
    assert author.has_perm("content.build_pack")
    assert author.has_perm("content.change_trip")
    assert not author.has_perm("content.publish_pack")
    assert publisher.has_perm("content.publish_pack")
    assert not publisher.has_perm("content.change_trip")
    assert not plain_staff.has_perm("content.change_trip")
    assert not inactive_author.has_perm("content.change_trip")
