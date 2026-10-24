"""Account creation: the install id's player, created or returned (B02 research R4, FR-001-FR-008).

The install id is a device credential. It is stored only as the sha256 of its canonical form, on
the `Device`, and it always leads to its device's player, linked or not (FR-005). A device whose
player is no longer active gets a new player (FR-004).
"""

from __future__ import annotations

import hashlib
import uuid

from django.db import IntegrityError, transaction

from apps.accounts.models import Device, Player
from apps.accounts.services.sessions import IssuedTokens, lock_player, now, open_session
from apps.common.client import ClientInfo

# Reads before the lock: a concurrent switch can move the device in between, at most this often.
ATTEMPTS = 5


def install_id_hash(install_id: uuid.UUID) -> str:
    return hashlib.sha256(str(install_id).lower().encode()).hexdigest()


def country_of(locale: str) -> str:
    """The region of `ar-EG` is `EG`. A bare language has none. No address lookup (FR-006)."""
    _, _, region = locale.partition("-")
    return region.upper()


def create_or_return(
    install_id: uuid.UUID, platform: str, locale: str, *, client: ClientInfo
) -> tuple[IssuedTokens, bool]:
    """The device's player and a new session, and whether the player was created."""
    digest = install_id_hash(install_id)
    with transaction.atomic():
        for _ in range(ATTEMPTS):
            found = _device_and_player(digest, platform, locale, client)
            if found is not None:
                device, created = found
                break
        else:  # pragma: no cover - the device moved between every read and its lock
            raise RuntimeError("install id kept moving between players")
        if not created and not device.player.is_active:
            device.player = _new_player(platform, locale, client)
            device.save(update_fields=["player", "updated_at"])
            created = True
        return open_session(device.player, device, client=client), created


def _device_and_player(
    digest: str, platform: str, locale: str, client: ClientInfo
) -> tuple[Device, bool] | None:
    """The device with its player's row locked first (sessions.lock_player), or a new device and
    player. `None` means try again: a race moved or inserted the device meanwhile."""
    device = Device.objects.filter(install_id_hash=digest).only("id", "player_id").first()
    if device is None:
        try:
            with transaction.atomic():  # a savepoint: a lost race rolls the player back too
                new = Device.objects.create(
                    install_id_hash=digest,
                    player=_new_player(platform, locale, client),
                    platform=platform,
                    app_version=client.version,
                    last_seen_at=now(),
                )
        except IntegrityError:
            return None  # another request inserted this install id first; read its device
        return new, True
    lock_player(device.player_id)
    locked = (
        Device.objects.select_for_update(of=("self",)).select_related("player").get(pk=device.pk)
    )
    if locked.player_id != device.player_id:
        return None  # moved to another player (a switch) between the read and the lock
    return locked, False


def _new_player(platform: str, locale: str, client: ClientInfo) -> Player:
    return Player.objects.create(
        locale=locale,
        country=country_of(locale),
        platform=platform,
        client_version=client.version,
        last_seen_at=now(),
    )
