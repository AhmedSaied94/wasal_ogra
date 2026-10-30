"""Fixtures for the content tests (tasks.md T057)."""

from __future__ import annotations

import importlib
import threading
import time
from collections.abc import Iterator
from dataclasses import dataclass, field
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import pytest
from django.conf import settings as django_settings
from django.contrib.auth.models import Group, Permission
from django.test import Client
from django_otp.oath import TOTP
from django_otp.plugins.otp_totp.models import TOTPDevice
from pytest_django import Settings

from apps.accounts.models import User
from apps.content.models import ContentChannel, SpeechLine, SpeechPool
from apps.content.services import importer, review
from apps.content.tests import factories as make

SAMPLE = django_settings.BASE_DIR.parent / "content" / "examples" / "sample"
PASSWORD = "a-long-enough-password-1"

# A copy: mutating the migration's own dict would break it when it runs before 0011's table.
GROUPS: dict[str, list[str]] = {
    name: list(codenames)
    for name, codenames in importlib.import_module(
        "apps.content.migrations.0003_groups"
    ).GROUPS.items()
}
# M10's model, granted by its own migration (0012), so the tests' groups match a fresh database.
GROUPS["content_author"] = [
    *GROUPS["content_author"],
    *importlib.import_module("apps.content.migrations.0012_rider_permissions").RIDER_CODENAMES,
]


@pytest.fixture
def packs_dir(tmp_path: Path, settings: Settings) -> Path:
    path = tmp_path / "packs"
    path.mkdir()
    settings.CONTENT_PACKS_DIR = path
    return path


@pytest.fixture
def channel(db: None) -> ContentChannel:
    """The `core` channel. Migration 0004 creates it; a transactional test's flush removes it."""
    return ContentChannel.objects.get_or_create(pack_id="core")[0]


# -- a pack server ------------------------------------------------------------------------------


@dataclass
class PackServer:
    """Serves `root` at `url`. Set `mode` to answer `500`, stall for `delay` seconds, or drop the
    connection. `requests` records each path asked for."""

    root: Path
    url: str = ""
    mode: str = "serve"  # serve | error | slow | drop
    delay: float = 3.0
    requests: list[str] = field(default_factory=list)


class _Handler(SimpleHTTPRequestHandler):
    server_state: PackServer

    def do_GET(self) -> None:
        self.server_state.requests.append(self.path)
        mode = self.server_state.mode
        if mode == "error":
            self.send_error(500)
        elif mode == "drop":
            self.close_connection = True
            self.connection.close()
        else:
            if mode == "slow":
                time.sleep(self.server_state.delay)
            super().do_GET()

    def log_message(self, format: str, *args: Any) -> None:
        pass


@pytest.fixture
def pack_server(tmp_path: Path) -> Iterator[PackServer]:
    root = tmp_path / "served"
    (root / "packs").mkdir(parents=True)
    state = PackServer(root=root / "packs")
    handler = type("Handler", (_Handler,), {"server_state": state})
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(handler, directory=str(root)))
    server.daemon_threads = True
    state.url = f"http://127.0.0.1:{server.server_address[1]}/packs/"
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield state
    finally:
        server.shutdown()
        server.server_close()


# -- users ----------------------------------------------------------------------------------------


def _group(name: str) -> Group:
    """The group as migration 0003 makes it. A transactional test's flush removes groups."""
    group, created = Group.objects.get_or_create(name=name)
    if created:
        group.permissions.set(
            Permission.objects.filter(content_type__app_label="content", codename__in=GROUPS[name])
        )
    return group


def _staff(username: str, *groups: str, is_active: bool = True) -> User:
    user = User.objects.create_user(username, is_staff=True, is_active=is_active)
    user.groups.set([_group(name) for name in groups])
    return user


@pytest.fixture
def author(db: None) -> User:
    return _staff("author1", "content_author")


@pytest.fixture
def publisher(db: None) -> User:
    return _staff("publisher1", "content_publisher")


@pytest.fixture
def plain_staff(db: None) -> User:
    return _staff("staff1")


@pytest.fixture
def inactive_author(db: None) -> User:
    return _staff("former1", "content_author", is_active=False)


# -- the sample content ---------------------------------------------------------------------------


@pytest.fixture
def sample_imported(author: User) -> User:
    """`content/examples/sample`, imported as `author1`. Its speech lines are unreviewed."""
    importer.import_dir(SAMPLE, author)
    return author


@pytest.fixture
def sample_reviewed(sample_imported: User) -> User:
    """The sample with every speech line reviewed by `author1`, ready to build green."""
    review.review_lines(SpeechLine.objects.order_by("pool", "order"), sample_imported)
    return sample_imported


@pytest.fixture
def engine_pools(sample_reviewed: User) -> User:
    """The reviewed sample with its speech swapped for `make.engine_speech_pools()`, reviewed: the
    least speech a pack builds green with (V-T10).

    M10's riders draw from their own pools (`story.*`), which the chapters name, so they stay: a
    rider's comment with no pool is V-C8.
    """
    story = {
        pool.speech_key: list(
            pool.lines.order_by("order").values_list("order", "text_ar_eg", "text_ar")
        )
        for pool in SpeechPool.objects.filter(speech_key__startswith="story.")
    }
    SpeechPool.objects.all().delete()
    make.engine_speech_pools()
    for key, lines in story.items():
        pool = SpeechPool.objects.create(speech_key=key)
        for order, ar_eg, ar in lines:
            SpeechLine.objects.create(pool=pool, order=order, text_ar_eg=ar_eg, text_ar=ar)
    review.review_lines(SpeechLine.objects.order_by("pool", "order"), sample_reviewed)
    return sample_reviewed


# -- the admin ------------------------------------------------------------------------------------


def admin_client(user: User) -> Client:
    """A client signed in to the admin as `user`, with password and TOTP code (B01)."""
    user.set_password(PASSWORD)
    user.save()
    device = TOTPDevice.objects.create(user=user, name="default", confirmed=True)
    token = TOTP(device.bin_key, device.step, device.t0, device.digits, device.drift).token()
    client = Client()
    response = client.post(
        "/admin/login/",
        {"username": user.username, "password": PASSWORD, "otp_token": str(token).zfill(6)},
    )
    assert response.status_code == 302, response.content[:500]
    return client
