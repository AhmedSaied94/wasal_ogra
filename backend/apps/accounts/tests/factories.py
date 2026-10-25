"""Players, devices and tokens for the accounts tests (B02)."""

from __future__ import annotations

import hashlib
import uuid
from typing import TYPE_CHECKING, Any

from django.test import Client
from django.utils import timezone

from apps.accounts import tokens
from apps.accounts.models import Device, Player
from apps.common.client import ClientInfo
from apps.common.ids import uuid7

if TYPE_CHECKING:
    from django.test.client import _MonkeyPatchedWSGIResponse as TestResponse

CLIENT = ClientInfo(version="1.4.0+57", platform="android")
HEADERS = {"x-client-version": "1.4.0+57", "x-platform": "android"}


def make_player(**fields: Any) -> Player:
    values: dict[str, Any] = {
        "locale": "ar-EG",
        "country": "EG",
        "platform": "android",
        "client_version": "1.4.0+57",
        "last_seen_at": timezone.now(),
        **fields,
    }
    return Player.objects.create(**values)


def make_device(player: Player, install_id: uuid.UUID | None = None, **fields: Any) -> Device:
    install = install_id or uuid.uuid4()
    values: dict[str, Any] = {
        "install_id_hash": install_hash(install),
        "player": player,
        "platform": "android",
        "app_version": "1.4.0+57",
        "last_seen_at": timezone.now(),
        **fields,
    }
    return Device.objects.create(**values)


def access_for(player: Player) -> str:
    """An access token for `player`. Access tokens are stateless, so no session row is needed."""
    return tokens.mint_access(player.id, uuid7())


def bearer(token: str) -> dict[str, str]:
    return {**HEADERS, "authorization": f"Bearer {token}"}


ANONYMOUS = "/v1/auth/anonymous"
REFRESH = "/v1/auth/refresh"
LINK = "/v1/auth/link"


def install_hash(install_id: uuid.UUID | str) -> str:
    return hashlib.sha256(str(install_id).lower().encode()).hexdigest()


def sign_in(
    client: Client,
    install_id: uuid.UUID | str,
    *,
    platform: str = "android",
    locale: str = "ar-EG",
    headers: dict[str, str] | None = None,
    **extra: str,
) -> TestResponse:
    """`POST /v1/auth/anonymous` as the app sends it."""
    body = {"install_id": str(install_id), "platform": platform, "locale": locale}
    return client.post(
        ANONYMOUS,
        data={**body, **extra},
        content_type="application/json",
        headers=HEADERS if headers is None else headers,
    )


def renew(client: Client, refresh: str, headers: dict[str, str] | None = None) -> TestResponse:
    """`POST /v1/auth/refresh`."""
    return client.post(
        REFRESH,
        data={"refresh": refresh},
        content_type="application/json",
        headers=HEADERS if headers is None else headers,
    )
