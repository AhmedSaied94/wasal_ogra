"""Opening a session at sign-in (B02 research R3, data-model.md "PlayerSession", FR-018)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
import time_machine
from django.utils import timezone

from apps.accounts import tokens
from apps.accounts.models import Identity, PlayerSession
from apps.accounts.services import sessions
from apps.accounts.tests.factories import make_device, make_player
from apps.common.client import ClientInfo

pytestmark = pytest.mark.django_db

NOW = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)
IOS = ClientInfo(version="1.5.0+60", platform="ios")


def test_open_session_records_the_refresh_claims() -> None:
    player = make_player(last_seen_at=NOW - timedelta(days=3))
    device = make_device(player, last_seen_at=NOW - timedelta(days=3))
    with time_machine.travel(NOW, tick=False):
        issued = sessions.open_session(player, device, client=IOS)

    session = PlayerSession.objects.get(player=player)
    claims = tokens.decode_refresh(issued.refresh, verify_exp=False)
    assert claims.session_id == session.id
    assert session.status == "active"
    assert session.device_id == device.id
    assert session.current_jti == claims.jti
    assert session.current_issued_at == NOW == claims.issued_at
    assert session.current_expires_at == NOW + timedelta(days=30) == claims.expires_at
    assert session.current_kid == "test1"
    assert session.last_renewed_at == NOW
    assert session.previous_jti is None
    assert session.previous_spent_at is None


def test_open_session_answers_a_token_pair() -> None:
    player = make_player()
    with time_machine.travel(NOW, tick=False):
        issued = sessions.open_session(player, make_device(player), client=IOS)
        access = tokens.read_access(issued.access)
    assert issued.player_id == player.id
    assert issued.access_expires_in == 900
    assert issued.providers == ()
    assert access["sub"] == str(player.id)
    assert access["sid"] == str(PlayerSession.objects.get().id)


def test_open_session_lists_the_linked_providers() -> None:
    player = make_player()
    Identity.objects.create(player=player, provider="google", subject="g", linked_at=timezone.now())
    assert sessions.open_session(player, make_device(player), client=IOS).providers == ("google",)


def test_open_session_records_the_client_on_the_player_and_device() -> None:
    player = make_player(last_seen_at=NOW - timedelta(days=3))
    device = make_device(player, last_seen_at=NOW - timedelta(days=3))
    with time_machine.travel(NOW, tick=False):
        sessions.open_session(player, device, client=IOS)
    player.refresh_from_db()
    device.refresh_from_db()
    assert (player.last_seen_at, player.client_version, player.platform) == (
        NOW,
        "1.5.0+60",
        "ios",
    )
    assert (device.last_seen_at, device.app_version, device.platform) == (NOW, "1.5.0+60", "ios")
