"""The read-only player admin (B02 US5, FR-036, contracts/admin.md)."""

from __future__ import annotations

import uuid
from dataclasses import dataclass

import pytest
from django.contrib.admin.models import CHANGE, LogEntry
from django.contrib.auth.models import Group
from django.test import Client
from django.utils import timezone

from apps.accounts.models import Device, Identity, Player, User
from apps.accounts.services import sessions
from apps.accounts.tests.factories import CLIENT, install_hash, make_device, make_player
from apps.content.tests.conftest import admin_client

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

CHANGELIST = "/admin/accounts/player/"
INSTALL_ID = uuid.UUID("6f1c2b9a-3d4e-4f5a-8b6c-7d8e9f0a1b2c")
SUBJECT = "109876543210987654321"


@dataclass(frozen=True)
class Linked:
    player: Player
    device: Device
    refresh: str

    @property
    def page(self) -> str:
        return f"{CHANGELIST}{self.player.pk}/change/"

    @property
    def delete_page(self) -> str:
        return f"{CHANGELIST}{self.player.pk}/delete/"


@pytest.fixture
def linked() -> Linked:
    """A player on one phone, linked to Google, with one live session."""
    player = make_player()
    device = make_device(player, INSTALL_ID)
    Identity.objects.create(
        player=player, provider="google", subject=SUBJECT, linked_at=timezone.now()
    )
    issued = sessions.open_session(player, device, client=CLIENT)
    return Linked(player, device, issued.refresh)


def staff(username: str, group: str | None = None) -> Client:
    user = User.objects.create_user(username, is_staff=True)
    if group:
        # Migration accounts/0003 made player_support; B04's content_author is made on demand.
        user.groups.add(Group.objects.get_or_create(name=group)[0])
    return admin_client(user)


@pytest.fixture
def support() -> Client:
    return staff("support1", "player_support")


def test_an_exact_player_id_finds_the_player(support: Client, linked: Linked) -> None:
    player_id = str(linked.player.pk)
    assert player_id in support.get(CHANGELIST, {"q": player_id}).content.decode()
    assert player_id in support.get(CHANGELIST, {"q": player_id.upper()}).content.decode()
    for partial in (player_id[:8], player_id[-12:]):
        response = support.get(CHANGELIST, {"q": partial})
        assert response.status_code == 200
        assert player_id not in response.content.decode()


def test_the_player_page_shows_the_account_without_secrets(support: Client, linked: Linked) -> None:
    response = support.get(linked.page)
    assert response.status_code == 200
    html = response.content.decode()
    for shown in ("Active", "Android", "1.4.0+57", "google (linked", str(linked.device.pk)):
        assert shown in html
    assert 'class="readonly">1</div>' in html  # one live session
    session = linked.player.sessions.get()
    for secret in (
        install_hash(INSTALL_ID),
        str(INSTALL_ID),
        SUBJECT,
        str(session.current_jti),
        linked.refresh,
    ):
        assert secret not in html


def change(client: Client, linked: Linked, **fields: str) -> int:
    """POST the change form, with the device inline's management form as the page renders it."""
    devices = linked.player.devices.count()
    data = {
        "devices-TOTAL_FORMS": str(devices),
        "devices-INITIAL_FORMS": str(devices),
        "devices-MIN_NUM_FORMS": "0",
        "devices-MAX_NUM_FORMS": "1000",
        **fields,
    }
    response = client.post(linked.page, data)
    return response.status_code


def test_only_the_tester_flag_saves(support: Client, linked: Linked) -> None:
    status = change(support, linked, is_tester="on", display_name="someone", status="deleted")
    assert status == 302
    player = Player.objects.get(pk=linked.player.pk)
    assert player.is_tester
    assert (player.display_name, player.status) == ("", "active")
    entry = LogEntry.objects.get(object_id=str(player.pk))
    assert entry.action_flag == CHANGE
    assert entry.get_change_message() == "Changed Is tester."


def test_a_superuser_can_set_the_tester_flag(linked: Linked) -> None:
    superuser = admin_client(User.objects.create_superuser("root1"))
    assert change(superuser, linked, is_tester="on") == 302
    assert Player.objects.get(pk=linked.player.pk).is_tester


def test_players_are_never_added_or_deleted(support: Client, linked: Linked) -> None:
    superuser = admin_client(User.objects.create_superuser("root1"))
    for client in (support, superuser):
        assert client.get(f"{CHANGELIST}add/").status_code == 403
        assert client.get(linked.delete_page).status_code == 403
        assert client.post(linked.delete_page, {"post": "yes"}).status_code == 403
        assert 'name="action"' not in client.get(CHANGELIST).content.decode()
    assert Player.objects.filter(pk=linked.player.pk).exists()


def test_other_staff_see_no_players(linked: Linked) -> None:
    author = staff("author1", "content_author")
    assert author.get(CHANGELIST).status_code == 403
    assert author.get(linked.page).status_code == 403
    assert CHANGELIST not in author.get("/admin/").content.decode()
