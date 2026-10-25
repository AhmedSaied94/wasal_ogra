"""`POST /v1/auth/link` without a conflict (B02 US3, FR-020-FR-024, contracts/api.md)."""

from __future__ import annotations

import json
from typing import Any

import pytest
from django.forms.models import model_to_dict
from django.test import Client
from pytest_django import Settings

from apps.accounts.models import Identity, Player
from apps.accounts.tests.conftest import GoogleKeys, MakeToken, SignedIn, signed_in
from apps.accounts.tests.factories import HEADERS, LINK

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("google_jwks")]


def error_of(response: Any, status: int) -> dict[str, Any]:
    assert response.status_code == status, response.content
    error: dict[str, Any] = json.loads(response.content)["error"]
    return error


def test_a_new_link(player_client: SignedIn, make_google_token: MakeToken) -> None:
    response = player_client.link(make_google_token("g-1"))
    assert response.status_code == 200
    assert response.json() == {"player_id": player_client.player_id, "providers": ["google"]}
    identity = Identity.objects.get()
    assert (str(identity.player_id), identity.provider, identity.subject) == (
        player_client.player_id,
        "google",
        "g-1",
    )


def test_nothing_from_the_token_but_its_subject_is_stored(
    player_client: SignedIn, make_google_token: MakeToken
) -> None:
    player_client.link(make_google_token("g-1"))
    rows = [*Player.objects.all(), *Identity.objects.all()]
    text = json.dumps([model_to_dict(row) for row in rows], default=str)
    for value in ("g-1@example.test", "Name of g-1", "https://example.test/g-1.png"):
        assert value not in text


def test_linking_again_changes_nothing(
    player_client: SignedIn, make_google_token: MakeToken
) -> None:
    player_client.link(make_google_token("g-1"))
    before = model_to_dict(Identity.objects.get())
    response = player_client.link(make_google_token("g-1"))
    assert response.status_code == 200
    assert Identity.objects.count() == 1
    assert model_to_dict(Identity.objects.get()) == before


def test_a_second_google_account_is_refused(
    player_client: SignedIn, make_google_token: MakeToken
) -> None:
    player_client.link(make_google_token("g-1"))
    error = error_of(player_client.link(make_google_token("g-2")), 409)
    assert error["code"] == "provider_already_linked"
    assert error["details"] == {"provider": "google"}
    assert list(Identity.objects.values_list("subject", flat=True)) == ["g-1"]


def test_a_link_freed_by_a_player_who_is_not_active_moves(make_google_token: MakeToken) -> None:
    """FR-030: only an active holder blocks a link."""
    old, new = signed_in(), signed_in()
    old.link(make_google_token("g-1"))
    Player.objects.filter(pk=old.player_id).update(status="pending_deletion")
    response = new.link(make_google_token("g-1"))
    assert response.status_code == 200
    assert str(Identity.objects.get().player_id) == new.player_id


@pytest.mark.parametrize(
    "body",
    [
        {"provider": "apple", "id_token": "x"},
        {"provider": "google"},
        {"provider": "google", "id_token": "x" * 4097},
        {"provider": "google", "id_token": "x", "resolve": "keep_current"},
        {
            "provider": "google",
            "id_token": "x",
            "existing_player_id": "0192f1c3-7d1e-7a4b-9c11-5e2f8a9b0c3d",
        },
        {
            "provider": "google",
            "id_token": "x",
            "resolve": "merge",
            "existing_player_id": "0192f1c3-7d1e-7a4b-9c11-5e2f8a9b0c3d",
        },
    ],
    ids=["apple", "no-token", "long-token", "resolve-alone", "id-alone", "bad-resolve"],
)
def test_refused_with_validation_error(player_client: SignedIn, body: dict[str, Any]) -> None:
    response = player_client.client.post(
        LINK, data=body, content_type="application/json", headers=player_client.headers
    )
    error = error_of(response, 400)
    assert error["code"] == "validation_error"
    assert "x" * 50 not in response.content.decode()
    assert not Identity.objects.exists()


def test_google_is_refused_where_no_client_id_is_set(
    player_client: SignedIn, make_google_token: MakeToken, settings: Settings
) -> None:
    settings.GOOGLE_OAUTH_CLIENT_IDS = ()
    error = error_of(player_client.link(make_google_token()), 400)
    assert error["details"]["fields"] == {"provider": ["This provider is not enabled here."]}


def test_a_tampered_token_is_422_never_401(
    player_client: SignedIn, make_google_token: MakeToken
) -> None:
    token = make_google_token(aud="someone-else.apps.googleusercontent.com")
    response = player_client.link(token)
    error = error_of(response, 422)
    assert error["code"] == "provider_token_invalid"
    assert error["details"] == {"provider": "google", "reason": "audience"}
    assert token not in response.content.decode()
    assert "WWW-Authenticate" not in response


def test_a_string_with_a_nul_is_malformed(player_client: SignedIn) -> None:
    error = error_of(player_client.link("q\x00;\x00\xda"), 422)
    assert error["details"] == {"provider": "google", "reason": "malformed"}


def test_google_s_keys_down_with_nothing_cached(
    player_client: SignedIn, make_google_token: MakeToken, google_jwks: GoogleKeys
) -> None:
    google_jwks.mode = "error"
    error = error_of(player_client.link(make_google_token()), 503)
    assert error["code"] == "dependency_unavailable"
    assert not Identity.objects.exists()


def test_no_bearer_token(make_google_token: MakeToken) -> None:
    response = Client().post(
        LINK,
        data={"provider": "google", "id_token": make_google_token()},
        content_type="application/json",
        headers=HEADERS,
    )
    assert error_of(response, 401)["code"] == "token_invalid"


def test_a_player_pending_deletion(player_client: SignedIn, make_google_token: MakeToken) -> None:
    Player.objects.filter(pk=player_client.player_id).update(status="pending_deletion")
    assert error_of(player_client.link(make_google_token()), 403)["code"] == "account_deleted"


def test_the_11th_link_in_a_minute_is_limited(
    player_client: SignedIn, make_google_token: MakeToken
) -> None:
    token = make_google_token("g-1")
    statuses = [player_client.link(token).status_code for _ in range(11)]
    assert statuses == [200] * 10 + [429]
