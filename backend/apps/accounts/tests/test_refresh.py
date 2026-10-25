"""`POST /v1/auth/refresh`: rotation, the retry window and reuse (B02 US2, contracts/tokens.md)."""

from __future__ import annotations

import json
import logging
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
import time_machine
from django.forms.models import model_to_dict
from django.test import Client

from apps.accounts import tokens
from apps.accounts.models import Player, PlayerSession
from apps.accounts.tests.factories import HEADERS, renew, sign_in

pytestmark = pytest.mark.django_db

T0 = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)


def at(seconds: float) -> time_machine.travel:
    return time_machine.travel(T0 + timedelta(seconds=seconds), tick=False)


def code_of(response: Any) -> str:
    code: str = json.loads(response.content)["error"]["code"]
    return code


@pytest.fixture
def first(client: Client) -> dict[str, Any]:
    """A sign-in at T0, and its install id."""
    install = uuid.uuid4()
    with at(0):
        body: dict[str, Any] = sign_in(client, install).json()
    return {**body, "install": install}


def session_of(refresh: str) -> PlayerSession:
    return PlayerSession.objects.get(pk=tokens.decode_refresh(refresh, verify_exp=False).session_id)


def test_the_current_token_rotates(client: Client, first: dict[str, Any]) -> None:
    with at(600):
        response = renew(client, first["refresh"])
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"player_id", "access", "refresh", "access_expires_in", "providers"}
    assert body["player_id"] == first["player_id"]
    assert body["refresh"] != first["refresh"]
    assert body["access_expires_in"] == 900

    session = session_of(first["refresh"])
    spent, current = tokens.decode_refresh(first["refresh"], verify_exp=False), session
    assert current.previous_jti == spent.jti
    assert current.previous_spent_at == T0 + timedelta(seconds=600)
    assert current.current_jti == tokens.decode_refresh(body["refresh"], verify_exp=False).jti
    assert current.current_expires_at == T0 + timedelta(seconds=600, days=30)
    assert current.last_renewed_at == T0 + timedelta(seconds=600)


@pytest.mark.parametrize("delay", [59, 60])
def test_a_replay_within_the_window_gets_the_same_successor(
    client: Client, first: dict[str, Any], delay: int
) -> None:
    with at(600):
        successor = renew(client, first["refresh"]).json()
    before = model_to_dict(session_of(first["refresh"]))
    with at(600 + delay):
        replay = renew(client, first["refresh"])
    assert replay.status_code == 200
    body = replay.json()
    assert body["refresh"] == successor["refresh"]  # byte for byte
    assert body["access"] != successor["access"]
    assert model_to_dict(session_of(first["refresh"])) == before
    # The successor is still the current token.
    with at(600 + delay + 1):
        assert renew(client, successor["refresh"]).status_code == 200


def test_a_replay_after_the_window_is_reuse(
    client: Client, first: dict[str, Any], caplog: pytest.LogCaptureFixture
) -> None:
    with at(600):
        successor = renew(client, first["refresh"]).json()
    caplog.set_level(logging.DEBUG)
    with at(661):
        response = renew(client, first["refresh"])

    assert response.status_code == 401
    assert code_of(response) == "token_invalid"
    assert response["WWW-Authenticate"] == "Bearer"
    session = session_of(first["refresh"])
    assert session.status == "ended"
    assert session.end_reason == "reuse"
    with at(662):
        current = renew(client, successor["refresh"])
    assert code_of(current) == "token_invalid"

    events = [r for r in caplog.records if r.name == "wassal.security"]
    assert [(r.levelname, r.__dict__.get("event")) for r in events] == [
        ("WARNING", "refresh_reuse")
    ]
    assert events[0].__dict__["player_id"] == first["player_id"]
    assert events[0].__dict__["session_id"] == str(session.id)
    secrets = (first["refresh"], first["access"], successor["refresh"], str(first["install"]))
    for record in caplog.records:
        text = record.getMessage() + json.dumps(record.__dict__, default=str)
        for secret in secrets:
            assert secret not in text


def test_an_older_token_is_reuse(client: Client, first: dict[str, Any]) -> None:
    with at(600):
        second = renew(client, first["refresh"]).json()
    with at(1200):
        assert renew(client, second["refresh"]).status_code == 200
    with at(1210):
        response = renew(client, first["refresh"])  # two rotations back, inside 60 s of nothing
    assert code_of(response) == "token_invalid"
    assert session_of(first["refresh"]).end_reason == "reuse"


def test_an_ended_session_refuses_without_changing(client: Client, first: dict[str, Any]) -> None:
    with at(600):
        renew(client, first["refresh"])
    with at(700):
        renew(client, first["refresh"])  # reuse: ends the session
    ended = model_to_dict(session_of(first["refresh"]))
    with at(800):
        assert code_of(renew(client, first["refresh"])) == "token_invalid"
    assert model_to_dict(session_of(first["refresh"])) == ended


def test_a_token_past_its_30_days_is_expired(client: Client, first: dict[str, Any]) -> None:
    with at(timedelta(days=30).total_seconds()):
        response = renew(client, first["refresh"])
    assert response.status_code == 401
    assert code_of(response) == "token_expired"
    session = session_of(first["refresh"])
    assert session.status == "active"  # lapsed, which is not a stored status


def test_a_player_pending_deletion_is_refused(client: Client, first: dict[str, Any]) -> None:
    Player.objects.filter(pk=first["player_id"]).update(status="pending_deletion")
    with at(600):
        response = renew(client, first["refresh"])
    assert response.status_code == 403
    assert code_of(response) == "account_deleted"


def test_an_access_token_is_not_a_refresh_token(client: Client, first: dict[str, Any]) -> None:
    with at(60):
        assert code_of(renew(client, first["access"])) == "token_invalid"


# Any string the schema allows is judged by its signature: a NUL is a bad token, not a bad field.
@pytest.mark.parametrize("token", ["garbage", "a.b.c", "q\x00;\x00\xda"])
def test_a_token_that_does_not_verify(client: Client, token: str) -> None:
    response = renew(client, token)
    assert response.status_code == 401
    assert code_of(response) == "token_invalid"


@pytest.mark.parametrize("token", ["", "x" * 4097])
def test_an_empty_or_over_long_token_is_a_validation_error(client: Client, token: str) -> None:
    response = renew(client, token)
    assert response.status_code == 400
    assert code_of(response) == "validation_error"
    assert "x" * 4097 not in response.content.decode()


def test_a_missing_field_or_header_is_a_validation_error(
    client: Client, first: dict[str, Any]
) -> None:
    response = client.post(
        "/v1/auth/refresh", data={}, content_type="application/json", headers=HEADERS
    )
    assert response.status_code == 400
    assert json.loads(response.content)["error"]["details"]["fields"] == {
        "refresh": ["This field is required."]
    }
    response = renew(client, first["refresh"], headers={"x-platform": "android"})
    assert response.status_code == 400
    assert first["refresh"] not in response.content.decode()


def test_another_device_s_session_keeps_renewing(client: Client, first: dict[str, Any]) -> None:
    """One session ending never ends another (FR-010, FR-012)."""
    with at(10):
        other = sign_in(client, first["install"]).json()  # the same player, a second session
    with at(600):
        renew(client, first["refresh"])
    with at(700):
        renew(client, first["refresh"])  # reuse ends the first session only
    with at(800):
        response = renew(client, other["refresh"])
    assert response.status_code == 200
    assert response.json()["player_id"] == first["player_id"]
