"""The Google account already has other progress: the player chooses (B02 US4, FR-025-FR-031)."""

from __future__ import annotations

import json
import uuid
from typing import Any

import pytest
from django.apps import apps
from django.db import models
from django.forms.models import model_to_dict
from django.test import Client

from apps.accounts import tokens
from apps.accounts.models import Device, Identity, Player, PlayerSession
from apps.accounts.services import linking, sessions
from apps.accounts.tests.conftest import MakeToken, SignedIn, signed_in
from apps.accounts.tests.factories import CLIENT, HEADERS, LINK, make_device, renew, sign_in

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("google_jwks")]

START = {"driver_level": 1, "chapter_id": "ch1_first_job", "bonat": 0}
# What a token issue writes (FR-018); every other player field must stay as it was (FR-028).
ISSUE_FIELDS = {"last_seen_at", "client_version", "platform", "updated_at"}
AUTH_MODELS = {Player, Device, Identity, PlayerSession}


@pytest.fixture
def existing(make_google_token: MakeToken) -> SignedIn:
    """E: signed in on its own phone and linked to G."""
    player = signed_in()
    assert player.link(make_google_token("G")).status_code == 200
    return player


@pytest.fixture
def current(db: None) -> SignedIn:
    """C: signed in on another phone, unlinked."""
    return signed_in()


def error_of(response: Any, status: int) -> dict[str, Any]:
    assert response.status_code == status, response.content
    error: dict[str, Any] = json.loads(response.content)["error"]
    return error


def session_of(refresh: str) -> PlayerSession:
    return PlayerSession.objects.get(pk=tokens.decode_refresh(refresh).session_id)


def snapshot() -> dict[str, Any]:
    """Every player's fields but FR-018's, and the row count of every table outside B02's."""
    players = {
        str(row.pk): {k: v for k, v in model_to_dict(row).items() if k not in ISSUE_FIELDS}
        for row in Player.objects.order_by("pk")
    }
    counts = {
        model._meta.label: model._default_manager.count()
        for model in apps.get_models()
        if model not in AUTH_MODELS and model._meta.managed and not model._meta.proxy
    }
    return {"players": players, "counts": counts}


def test_the_conflict_shows_both_summaries_and_changes_nothing(
    existing: SignedIn, current: SignedIn, make_google_token: MakeToken
) -> None:
    before = snapshot()
    error = error_of(current.link(make_google_token("G")), 409)
    assert error["code"] == "provider_in_use"
    assert error["message"] == "Provider linked to another player"
    assert error["details"] == {
        "current": START,
        "existing": {"player_id": existing.player_id, **START},
    }
    assert str(Identity.objects.get(subject="G").player_id) == existing.player_id
    assert snapshot() == before


def test_switch_to_existing(
    existing: SignedIn, current: SignedIn, make_google_token: MakeToken
) -> None:
    c_player = Player.objects.get(pk=current.player_id)
    other_device = make_device(c_player)
    other_session = sessions.open_session(c_player, other_device, client=CLIENT)
    before = snapshot()

    response = current.link(
        make_google_token("G"), resolve="switch_to_existing", existing_player_id=existing.player_id
    )

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"player_id", "access", "refresh", "access_expires_in", "providers"}
    assert body["player_id"] == existing.player_id
    assert body["providers"] == ["google"]
    assert tokens.read_access(body["access"])["sub"] == existing.player_id
    request_session = session_of(current.refresh)
    assert (request_session.status, request_session.end_reason) == ("ended", "switch")
    assert renew(current.client, current.refresh).json()["error"]["code"] == "token_invalid"
    assert str(Device.objects.get(pk=request_session.device_id).player_id) == existing.player_id
    assert sign_in(Client(), current.install).json()["player_id"] == existing.player_id
    # C's other phone is untouched, and so is everything but links, devices and sessions.
    assert Device.objects.get(pk=other_device.pk).player_id == c_player.id
    assert renew(Client(), other_session.refresh).status_code == 200
    assert snapshot() == before


def test_keep_current(existing: SignedIn, current: SignedIn, make_google_token: MakeToken) -> None:
    before = snapshot()
    response = current.link(
        make_google_token("G"), resolve="keep_current", existing_player_id=existing.player_id
    )
    assert response.status_code == 200
    assert response.json() == {"player_id": current.player_id, "providers": ["google"]}
    assert str(Identity.objects.get(subject="G").player_id) == current.player_id
    assert not Identity.objects.filter(player_id=existing.player_id).exists()
    assert renew(existing.client, existing.refresh).status_code == 200  # E's sessions stay
    assert snapshot() == before


def test_a_retry_after_the_holder_changed_shows_the_new_conflict(
    existing: SignedIn, current: SignedIn, make_google_token: MakeToken
) -> None:
    error_of(current.link(make_google_token("G")), 409)
    third = signed_in()
    Identity.objects.filter(subject="G").update(player_id=third.player_id)

    error = error_of(
        current.link(
            make_google_token("G"), resolve="keep_current", existing_player_id=existing.player_id
        ),
        409,
    )
    assert error["code"] == "provider_in_use"
    assert error["details"]["existing"]["player_id"] == third.player_id
    assert str(Identity.objects.get(subject="G").player_id) == third.player_id


def test_a_retry_after_the_holder_was_deleted_links(
    existing: SignedIn, current: SignedIn, make_google_token: MakeToken
) -> None:
    error_of(current.link(make_google_token("G")), 409)
    Player.objects.filter(pk=existing.player_id).update(status="deleted")
    response = current.link(
        make_google_token("G"), resolve="switch_to_existing", existing_player_id=existing.player_id
    )
    assert response.status_code == 200
    assert response.json() == {"player_id": current.player_id, "providers": ["google"]}
    assert str(Identity.objects.get(subject="G").player_id) == current.player_id
    assert session_of(current.refresh).status == "active"


def test_resolve_without_a_conflict_is_ignored(
    current: SignedIn, make_google_token: MakeToken
) -> None:
    response = current.link(
        make_google_token("free"),
        resolve="switch_to_existing",
        existing_player_id=str(uuid.uuid4()),
    )
    assert response.status_code == 200
    assert response.json() == {"player_id": current.player_id, "providers": ["google"]}


def test_a_holder_pending_deletion_frees_the_account(
    existing: SignedIn, current: SignedIn, make_google_token: MakeToken
) -> None:
    Player.objects.filter(pk=existing.player_id).update(status="pending_deletion")
    response = current.link(make_google_token("G"))
    assert response.status_code == 200
    assert str(Identity.objects.get(subject="G").player_id) == current.player_id


def rows() -> dict[str, Any]:
    def dump(model: type[models.Model]) -> list[dict[str, Any]]:
        return [model_to_dict(row) for row in model._default_manager.order_by("pk")]

    return {"devices": dump(Device), "identities": dump(Identity), "sessions": dump(PlayerSession)}


def failing_client(signed: SignedIn) -> Client:
    return Client(raise_request_exception=False, headers=signed.headers)


def test_a_failed_switch_changes_nothing(
    existing: SignedIn,
    current: SignedIn,
    make_google_token: MakeToken,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    before = rows()

    def boom(*args: object, **kwargs: object) -> None:
        raise RuntimeError("open_session failed")

    monkeypatch.setattr(linking, "open_session", boom)
    response = failing_client(current).post(
        LINK,
        data={
            "provider": "google",
            "id_token": make_google_token("G"),
            "resolve": "switch_to_existing",
            "existing_player_id": existing.player_id,
        },
        content_type="application/json",
    )
    assert response.status_code == 500
    assert rows() == before


def test_a_failed_keep_current_changes_nothing(
    existing: SignedIn,
    current: SignedIn,
    make_google_token: MakeToken,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    before = rows()

    def boom(self: Identity, *args: object, **kwargs: object) -> None:
        raise RuntimeError("save failed")

    monkeypatch.setattr(Identity, "save", boom)
    response = failing_client(current).post(
        LINK,
        data={
            "provider": "google",
            "id_token": make_google_token("G"),
            "resolve": "keep_current",
            "existing_player_id": existing.player_id,
        },
        content_type="application/json",
    )
    assert response.status_code == 500
    assert rows() == before
    assert str(Identity.objects.get(subject="G").player_id) == existing.player_id


def test_a_switch_ends_every_session_of_the_current_player_on_that_device(
    existing: SignedIn, current: SignedIn, make_google_token: MakeToken
) -> None:
    """The device belongs to the existing player now, so none of C's sessions on it stay (a
    second sign-in on the same phone, or a phone restored from its backup)."""
    second = sign_in(current.client, current.install).json()
    current.link(
        make_google_token("G"), resolve="switch_to_existing", existing_player_id=existing.player_id
    )
    session = session_of(second["refresh"])
    assert (session.status, session.end_reason) == ("ended", "switch")
    assert renew(Client(), second["refresh"]).json()["error"]["code"] == "token_invalid"


def test_a_device_that_moved_can_t_be_switched_again_from_a_stale_token(
    existing: SignedIn, current: SignedIn, make_google_token: MakeToken
) -> None:
    """C's access token outlives its session by up to 15 minutes. It can't take the phone, which
    is now E's, to a third player F."""
    second = sign_in(current.client, current.install).json()
    current.link(
        make_google_token("G"), resolve="switch_to_existing", existing_player_id=existing.player_id
    )
    third = signed_in()
    assert third.link(make_google_token("F")).status_code == 200
    stale = Client(headers={**HEADERS, "authorization": f"Bearer {second['access']}"})
    response = stale.post(
        LINK,
        data={
            "provider": "google",
            "id_token": make_google_token("F"),
            "resolve": "switch_to_existing",
            "existing_player_id": third.player_id,
        },
        content_type="application/json",
    )
    assert error_of(response, 401)["code"] == "token_invalid"
    device = Device.objects.get(pk=session_of(second["refresh"]).device_id)
    assert str(device.player_id) == existing.player_id
