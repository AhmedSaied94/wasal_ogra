"""Every player endpoint authenticates a player token (B02 FR-013, FR-014, FR-016, R11)."""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING, Any

import pytest
import time_machine
from django.test import Client
from pytest_django import DjangoAssertNumQueries

from apps.accounts import tokens
from apps.accounts.models import Device, Player, User
from apps.accounts.tests.factories import HEADERS, access_for, bearer, make_device, make_player
from apps.common.ids import uuid7

if TYPE_CHECKING:
    from django.test.client import _MonkeyPatchedWSGIResponse as TestResponse

pytestmark = [pytest.mark.django_db, pytest.mark.urls("apps.accounts.tests.urls")]

WHOAMI = "/test/whoami"
NOW = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)


def error_of(response: TestResponse, status: int) -> dict[str, Any]:
    assert response.status_code == status, response.content
    error: dict[str, Any] = json.loads(response.content)["error"]
    if status == 401:
        assert response["WWW-Authenticate"] == "Bearer"
    return error


def test_a_valid_access_token_is_the_player(client: Client) -> None:
    player = make_player()
    response = client.get(WHOAMI, headers=bearer(access_for(player)))
    assert response.status_code == 200
    assert response.json() == {"player_id": str(player.id), "token_type": "access"}


def test_an_expired_access_token(client: Client) -> None:
    player = make_player()
    with time_machine.travel(NOW, tick=False):
        token = access_for(player)
    with time_machine.travel(NOW + timedelta(minutes=15, seconds=1), tick=False):
        response = client.get(WHOAMI, headers=bearer(token))
    assert error_of(response, 401)["code"] == "token_expired"


def test_a_refresh_token_is_not_an_access_token(client: Client) -> None:
    player = make_player()
    now = datetime.now(UTC)
    refresh = tokens.mint_refresh(
        player_id=player.id,
        session_id=uuid7(),
        jti=uuid7(),
        issued_at=now,
        expires_at=now + tokens.REFRESH_LIFETIME,
        kid="test1",
    )
    assert error_of(client.get(WHOAMI, headers=bearer(refresh)), 401)["code"] == "token_invalid"


@pytest.mark.parametrize(
    "authorization",
    [
        None,
        "Basic dXNlcjpwYXNz",
        "Bearer",
        "Bearer a b",
        "Bearer not-a-token",
    ],
)
def test_no_usable_token_is_token_invalid(client: Client, authorization: str | None) -> None:
    headers = {**HEADERS, "authorization": authorization} if authorization else HEADERS
    error = error_of(client.get(WHOAMI, headers=headers), 401)
    assert error["code"] == "token_invalid"
    assert error["details"] == {}


def test_an_altered_token_is_invalid(client: Client) -> None:
    token = access_for(make_player())
    header, payload, signature = token.split(".")
    altered = f"{header}.{payload}.{signature[:-2]}{'AA' if signature[-2:] != 'AA' else 'BB'}"
    assert error_of(client.get(WHOAMI, headers=bearer(altered)), 401)["code"] == "token_invalid"


@pytest.mark.parametrize("status", ["pending_deletion", "deleted"])
def test_a_deleted_player_is_refused_on_the_next_request(client: Client, status: str) -> None:
    player = make_player()
    with time_machine.travel(NOW, tick=False):
        token = access_for(player)
    Player.objects.filter(pk=player.pk).update(status=status)
    with time_machine.travel(NOW + timedelta(minutes=1), tick=False):
        response = client.get(WHOAMI, headers=bearer(token))
    error = error_of(response, 403)
    assert error["code"] == "account_deleted"
    assert "WWW-Authenticate" not in response


def test_a_missing_player_is_token_invalid(client: Client) -> None:
    token = tokens.mint_access(uuid7(), uuid7())
    assert error_of(client.get(WHOAMI, headers=bearer(token)), 401)["code"] == "token_invalid"


def test_a_request_with_an_access_token_writes_nothing(
    client: Client, django_assert_num_queries: DjangoAssertNumQueries
) -> None:
    """Only token issue and renewal record `last_seen_at` (FR-018). One query: the player."""
    player = make_player()
    device = make_device(player)
    token = access_for(player)
    with django_assert_num_queries(1):
        assert client.get(WHOAMI, headers=bearer(token)).status_code == 200
    assert Player.objects.get(pk=player.pk).updated_at == player.updated_at
    assert Device.objects.get(pk=device.pk).updated_at == device.updated_at


def test_the_client_headers_are_required_with_a_token(client: Client) -> None:
    token = access_for(make_player())
    response = client.get(WHOAMI, headers={"authorization": f"Bearer {token}"})
    error = error_of(response, 400)
    assert set(error["details"]["fields"]) == {"X-Client-Version", "X-Platform"}


def test_a_staff_session_does_not_authenticate_the_api(client: Client) -> None:
    staff = User.objects.create_user("ahmed", "a-long-enough-password-1", is_staff=True)
    client.force_login(staff)
    assert error_of(client.get(WHOAMI, headers=HEADERS), 401)["code"] == "token_invalid"


@pytest.mark.urls("config.urls_admin")
def test_a_player_token_opens_no_admin_page(client: Client) -> None:
    token = access_for(make_player())
    response = client.get("/admin/", headers={"authorization": f"Bearer {token}"})
    assert response.status_code == 302
    assert response["Location"].startswith("/admin/login/")
