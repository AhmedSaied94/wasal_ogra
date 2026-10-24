"""Rotating the signing key signs no one out (B02 SC-004, US2-7, research R13)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pytest
import time_machine
from django.conf import settings as django_settings
from django.test import Client
from pytest_django import Settings

from apps.accounts.tests.factories import renew, sign_in
from config.env import SigningKey

pytestmark = pytest.mark.django_db

T0 = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)
NEW_KEY = SigningKey("k20261124", b"n" * 32)


def at(seconds: float) -> time_machine.travel:
    return time_machine.travel(T0 + timedelta(seconds=seconds), tick=False)


def kid_of(token: str) -> str:
    kid: str = jwt.get_unverified_header(token)["kid"]
    return kid


def test_a_token_signed_by_the_old_key_renews_with_the_new_one(
    client: Client, settings: Settings
) -> None:
    with at(0):
        first = sign_in(client, uuid.uuid4()).json()
    assert kid_of(first["refresh"]) == "test1"
    settings.AUTH_SIGNING_KEYS = (NEW_KEY, *django_settings.AUTH_SIGNING_KEYS)
    with at(600):
        response = renew(client, first["refresh"])
    assert response.status_code == 200
    assert kid_of(response.json()["refresh"]) == "k20261124"
    assert kid_of(response.json()["access"]) == "k20261124"


def test_a_replay_re_signs_with_the_stored_key(client: Client, settings: Settings) -> None:
    with at(0):
        first = sign_in(client, uuid.uuid4()).json()
    with at(600):
        successor = renew(client, first["refresh"]).json()  # signed by test1
    settings.AUTH_SIGNING_KEYS = (NEW_KEY, *django_settings.AUTH_SIGNING_KEYS)
    with at(630):
        replay = renew(client, first["refresh"]).json()
    assert replay["refresh"] == successor["refresh"]
    assert kid_of(replay["refresh"]) == "test1"


def test_a_retired_key_s_tokens_are_invalid_and_the_install_id_gets_back_in(
    client: Client, settings: Settings
) -> None:
    install = uuid.uuid4()
    with at(0):
        first = sign_in(client, install).json()
    settings.AUTH_SIGNING_KEYS = (NEW_KEY,)
    with at(600):
        response = renew(client, first["refresh"])
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "token_invalid"
        back = sign_in(client, install)
    assert back.status_code == 200
    assert back.json()["player_id"] == first["player_id"]
    assert kid_of(back.json()["refresh"]) == "k20261124"
