"""Linking Google, and resolving a conflict (B02 research R7, FR-020-FR-031).

The Google token is verified first, outside the transaction, since that may fetch Google's keys.
Then, in one transaction, under the players' row locks (in id order), the link is decided:

- G is already the current player's: nothing changes (FR-024).
- The current player has another Google account: `409 provider_already_linked`.
- G has no holder, or one who isn't active: G is linked to the current player (FR-030).
- G belongs to another active player E: `409 provider_in_use` with both summaries, unless the
  request resolves that very conflict (FR-029): `switch_to_existing` moves this device to E, and
  `keep_current` moves G here (FR-026, FR-027).

Only links, devices and sessions change, plus FR-018's fields on a token issue (FR-028).
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass

from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.accounts.models import Device, Identity, Player, PlayerSession
from apps.accounts.services import google
from apps.accounts.services.sessions import (
    IssuedTokens,
    end_session,
    lock_player,
    open_session,
)
from apps.accounts.services.summary import summarize
from apps.common.client import ClientInfo
from apps.common.errors import ApiError, ErrorCode

security = logging.getLogger("wassal.security")

# Reads before the locks: a concurrent link can move G in between, at most this often.
ATTEMPTS = 5


@dataclass(frozen=True)
class Linked:
    player_id: uuid.UUID
    providers: tuple[str, ...]


class _HolderMoved(Exception):
    """G changed hands between the read and the locks: decide again from the start."""


def link(
    player: Player,
    provider: str,
    id_token: str,
    *,
    session_id: uuid.UUID,
    client: ClientInfo,
    resolve: str | None = None,
    existing_player_id: uuid.UUID | None = None,
) -> Linked | IssuedTokens:
    """`POST /v1/auth/link`. A switch answers with the existing player's tokens."""
    subject = google.verify_id_token(id_token)
    for _ in range(ATTEMPTS):
        try:
            with transaction.atomic():
                return _decide(
                    player.pk, provider, subject, session_id, client, resolve, existing_player_id
                )
        except _HolderMoved:
            continue
    raise RuntimeError("the provider account kept changing hands")  # pragma: no cover


def _decide(
    player_id: uuid.UUID,
    provider: str,
    subject: str,
    session_id: uuid.UUID,
    client: ClientInfo,
    resolve: str | None,
    existing_player_id: uuid.UUID | None,
) -> Linked | IssuedTokens:
    holder_id = (
        Identity.objects.filter(provider=provider, subject=subject)
        .values_list("player_id", flat=True)
        .first()
    )
    involved = {player_id} if holder_id is None else {player_id, holder_id}
    locked = {pk: lock_player(pk) for pk in sorted(involved)}  # id order: no deadlock
    current = locked[player_id]
    if current is None:
        raise ApiError(ErrorCode.TOKEN_INVALID)
    if not current.is_active:
        raise ApiError(ErrorCode.ACCOUNT_DELETED)
    identity = (
        Identity.objects.select_for_update().filter(provider=provider, subject=subject).first()
    )
    if (identity.player_id if identity else None) != holder_id:
        raise _HolderMoved

    if identity is not None and identity.player_id == current.pk:
        return _linked(current)
    if Identity.objects.filter(player=current, provider=provider).exists():
        _refused(current, "provider_already_linked")
        raise ApiError(ErrorCode.PROVIDER_ALREADY_LINKED, {"provider": provider})
    if identity is None:
        try:
            with transaction.atomic():
                Identity.objects.create(
                    player=current, provider=provider, subject=subject, linked_at=timezone.now()
                )
        except IntegrityError:
            raise _HolderMoved from None  # linked elsewhere at the same moment
        return _linked(current)

    holder = locked[identity.player_id]
    if holder is None or not holder.is_active:
        _move(identity, current)  # only an active holder blocks a link (FR-030)
        return _linked(current)
    if resolve is None or existing_player_id != holder.pk:
        _refused(current, "provider_in_use")
        raise ApiError(
            ErrorCode.PROVIDER_IN_USE,
            {
                "current": summarize(current),
                "existing": {"player_id": str(holder.pk), **summarize(holder)},
            },
        )
    if resolve == "keep_current":
        _move(identity, current)
        _event("keep_current", current, holder)
        return _linked(current)
    return _switch(current, holder, session_id, client)


def _switch(
    current: Player, holder: Player, session_id: uuid.UUID, client: ClientInfo
) -> IssuedTokens:
    """This device's sign-in becomes the existing player's (FR-026). C's sessions on the device
    end, and the device and a new session go to that player. C's other devices stay.

    A repeat of the same switch finds the device already the holder's and answers again. A device
    that went to anyone else can't move on a stale access token of C's.
    """
    session = (
        PlayerSession.objects.select_for_update(of=("self",))
        .filter(pk=session_id, player=current)
        .first()
    )
    if session is None:
        raise ApiError(ErrorCode.TOKEN_INVALID)
    on_device = PlayerSession.objects.select_for_update(of=("self",)).filter(
        player=current, device_id=session.device_id, status=PlayerSession.Status.ACTIVE
    )
    for live in on_device.order_by("id"):
        end_session(live, PlayerSession.EndReason.SWITCH)
    device = Device.objects.select_for_update().get(pk=session.device_id)
    if device.player_id not in (current.pk, holder.pk):
        raise ApiError(ErrorCode.TOKEN_INVALID)
    if device.player_id != holder.pk:
        device.player = holder
        device.save(update_fields=["player", "updated_at"])
    issued = open_session(holder, device, client=client)
    _event("switch", current, holder, device_id=str(device.pk))
    return issued


def _move(identity: Identity, player: Player) -> None:
    identity.player = player
    identity.linked_at = timezone.now()
    identity.save(update_fields=["player", "linked_at", "updated_at"])


def _linked(player: Player) -> Linked:
    providers = tuple(sorted(player.identities.values_list("provider", flat=True)))
    return Linked(player_id=player.pk, providers=providers)


def _refused(player: Player, reason: str) -> None:
    security.info(
        "link refused",
        extra={"event": "link_refused", "player_id": str(player.pk), "reason": reason},
    )


def _event(event: str, current: Player, holder: Player, **ids: str) -> None:
    security.info(
        "link resolved",
        extra={
            "event": event,
            "player_id": str(current.pk),
            "existing_player_id": str(holder.pk),
            **ids,
        },
    )
