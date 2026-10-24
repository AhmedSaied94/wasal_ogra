"""`POST /v1/auth/anonymous`: the device's player, created or returned (B02 US1, FR-001-FR-008)."""

from __future__ import annotations

import json
import uuid
from typing import Any

import pytest
from django.forms.models import model_to_dict
from django.test import Client
from django.utils import timezone

from apps.accounts import tokens
from apps.accounts.models import Device, Identity, Player, PlayerSession
from apps.accounts.tests.factories import (
    HEADERS,
    install_hash,
    make_device,
    make_player,
    sign_in,
)

pytestmark = pytest.mark.django_db

TOKEN_PAIR = {"player_id", "access", "refresh", "access_expires_in", "providers", "created"}
UUID_MESSAGE = "Must be a version-4 UUID."
V7_ID = "0192f1c3-7d1e-7a4b-9c11-5e2f8a9b0c3d"  # fixed, so every xdist worker collects the same ids


def fields_of(response: Any) -> dict[str, list[str]]:
    assert response.status_code == 400, response.content
    error = json.loads(response.content)["error"]
    assert error["code"] == "validation_error"
    fields: dict[str, list[str]] = error["details"]["fields"]
    return fields


def test_a_new_install_id_creates_a_player_and_a_device(client: Client) -> None:
    install = uuid.uuid4()
    response = sign_in(client, install)

    assert response.status_code == 201
    body = response.json()
    assert set(body) == TOKEN_PAIR
    assert body["created"] is True
    assert body["access_expires_in"] == 900
    assert body["providers"] == []
    player = Player.objects.get()
    device = Device.objects.get()
    assert body["player_id"] == str(player.id)
    assert player.id.version == 7
    assert device.player_id == player.id
    assert device.install_id_hash == install_hash(install)
    assert tokens.read_access(body["access"])["sub"] == str(player.id)
    assert tokens.decode_refresh(body["refresh"]).player_id == player.id


def test_the_raw_install_id_is_stored_nowhere(client: Client) -> None:
    install = uuid.uuid4()
    assert sign_in(client, install).status_code == 201
    rows = [*Player.objects.all(), *Device.objects.all(), *PlayerSession.objects.all()]
    for row in rows:
        assert str(install) not in json.dumps(model_to_dict(row), default=str)
        assert install.hex not in json.dumps(model_to_dict(row), default=str)


def test_the_same_id_in_upper_case_returns_the_player(client: Client) -> None:
    install = uuid.uuid4()
    first = sign_in(client, install).json()
    response = sign_in(client, str(install).upper())

    assert response.status_code == 200
    body = response.json()
    assert body["created"] is False
    assert body["player_id"] == first["player_id"]
    assert body["access"] != first["access"]
    assert body["refresh"] != first["refresh"]
    assert Player.objects.count() == 1
    assert Device.objects.count() == 1


def test_a_linked_player_is_returned_by_its_install_id(client: Client) -> None:
    """FR-005: the install id leads to its device's player, linked or not."""
    install = uuid.uuid4()
    first = sign_in(client, install).json()
    player = Player.objects.get(pk=first["player_id"])
    Identity.objects.create(player=player, provider="google", subject="g", linked_at=timezone.now())

    body = sign_in(client, install).json()
    assert body["player_id"] == first["player_id"]
    assert body["providers"] == ["google"]


@pytest.mark.parametrize("status", ["pending_deletion", "deleted"])
def test_a_player_who_is_not_active_gets_a_new_player(client: Client, status: str) -> None:
    install = uuid.uuid4()
    old = make_player(status=status)
    make_device(old, install_id=install)
    before = model_to_dict(Player.objects.get(pk=old.pk))

    response = sign_in(client, install)

    assert response.status_code == 201
    body = response.json()
    assert body["created"] is True
    assert body["player_id"] != str(old.id)
    assert Device.objects.get().player_id == uuid.UUID(body["player_id"])
    assert model_to_dict(Player.objects.get(pk=old.pk)) == before
    assert not PlayerSession.objects.filter(player=old).exists()


@pytest.mark.parametrize(("locale", "country"), [("ar-EG", "EG"), ("ar", ""), ("en-SA", "SA")])
def test_a_new_player_s_fields(client: Client, locale: str, country: str) -> None:
    headers = {"x-client-version": "2.1.0+77", "x-platform": "ios"}
    response = sign_in(client, uuid.uuid4(), platform="ios", locale=locale, headers=headers)
    assert response.status_code == 201
    player = Player.objects.get()
    assert player.country == country
    assert player.locale == locale
    assert player.driver_level == 1
    assert player.display_name == ""
    assert player.is_tester is False
    assert player.status == "active"
    assert (player.platform, player.client_version) == ("ios", "2.1.0+77")
    device = Device.objects.get()
    assert (device.platform, device.app_version) == ("ios", "2.1.0+77")


@pytest.mark.parametrize(
    ("body", "field"),
    [
        ({"install_id": V7_ID}, "install_id"),
        ({"install_id": "not-a-uuid"}, "install_id"),
        ({"install_id": None}, "install_id"),
        ({"platform": "web"}, "platform"),
        ({"platform": "ios"}, "platform"),  # differs from X-Platform
        ({"locale": "arabic"}, "locale"),
        ({"locale": "ar-EGYPT"}, "locale"),
        ({"locale": "abcdefghijklmnopq"}, "locale"),
        ({"locale": 7}, "locale"),
    ],
)
def test_refused_with_validation_error(client: Client, body: dict[str, Any], field: str) -> None:
    payload = {"install_id": str(uuid.uuid4()), "platform": "android", "locale": "ar-EG", **body}
    payload = {key: value for key, value in payload.items() if value is not None}
    response = client.post(
        "/v1/auth/anonymous", data=payload, content_type="application/json", headers=HEADERS
    )
    assert field in fields_of(response)
    assert not Player.objects.exists()


@pytest.mark.parametrize("missing", ["install_id", "platform", "locale"])
def test_a_missing_field_is_refused(client: Client, missing: str) -> None:
    payload = {"install_id": str(uuid.uuid4()), "platform": "android", "locale": "ar-EG"}
    del payload[missing]
    response = client.post(
        "/v1/auth/anonymous", data=payload, content_type="application/json", headers=HEADERS
    )
    assert fields_of(response)[missing] == ["This field is required."]


@pytest.mark.parametrize("header", ["x-client-version", "x-platform"])
def test_a_missing_header_is_refused(client: Client, header: str) -> None:
    headers = {key: value for key, value in HEADERS.items() if key != header}
    fields = fields_of(sign_in(client, uuid.uuid4(), headers=headers))
    assert list(fields) == [{"x-client-version": "X-Client-Version"}.get(header, "X-Platform")]
    assert not Player.objects.exists()


@pytest.mark.parametrize(
    "value",
    [
        "not-a-uuid",
        V7_ID,
        "a" * 5000,
        "3b0b9d3e-6f1a-4c8e-9f7a-2d5c1e8b4a9z",
        "3b0b9d3e-6f1a-4c8e-9f7a-2d5c1e8b4a90\n",
        " 3b0b9d3e-6f1a-4c8e-9f7a-2d5c1e8b4a90",
    ],
    ids=["malformed", "v7", "long", "bad-hex", "trailing-newline", "leading-space"],
)
def test_errors_never_repeat_the_install_id(client: Client, value: str) -> None:
    """FR-002: the install id is a credential, so no answer echoes it."""
    response = sign_in(client, value)
    assert fields_of(response) == {"install_id": [UUID_MESSAGE]}
    assert value not in response.content.decode()


@pytest.mark.parametrize("field", ["platform", "locale"])
def test_errors_never_repeat_other_values(client: Client, field: str) -> None:
    marker = "<b>marker-value</b>"
    if field == "platform":
        response = sign_in(client, uuid.uuid4(), platform=marker)
    else:
        response = sign_in(client, uuid.uuid4(), locale=marker)
    assert field in fields_of(response)
    assert "marker-value" not in response.content.decode()


def test_a_return_updates_the_device(client: Client) -> None:
    install = uuid.uuid4()
    sign_in(client, install)
    headers = {"x-client-version": "1.6.0", "x-platform": "ios"}
    assert sign_in(client, install, platform="ios", headers=headers).status_code == 200
    device = Device.objects.get()
    assert (device.platform, device.app_version) == ("ios", "1.6.0")


def test_a_return_opens_another_session_and_keeps_the_first(client: Client) -> None:
    install = uuid.uuid4()
    first = sign_in(client, install).json()
    second = sign_in(client, install).json()
    sessions = PlayerSession.objects.filter(status="active")
    assert sessions.count() == 2
    assert {str(s.id) for s in sessions} == {
        str(tokens.decode_refresh(first["refresh"]).session_id),
        str(tokens.decode_refresh(second["refresh"]).session_id),
    }


def test_only_post_is_allowed(client: Client) -> None:
    response = client.get("/v1/auth/anonymous", headers=HEADERS)
    assert response.status_code == 405
