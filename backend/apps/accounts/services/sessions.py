"""Sessions: opening, renewal, the retry window, reuse and the cap (B02 research R3, FR-009+).

A session is the chain of refresh tokens from one sign-in on one device. Its row holds the claims
of the current and the previous refresh token, never a token. Everything is in PostgreSQL, under
row locks, so a cache outage can't let a spent token fork a session.

Lock order: the player's row first (`lock_player`; two players in id order), then its sessions,
devices and identities.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.accounts import tokens
from apps.accounts.models import Device, Player, PlayerSession
from apps.common.client import ClientInfo
from apps.common.errors import ApiError, ErrorCode
from apps.common.ids import uuid7

security = logging.getLogger("wassal.security")

ACCESS_EXPIRES_IN = int(tokens.ACCESS_LIFETIME.total_seconds())


@dataclass(frozen=True)
class IssuedTokens:
    """What every token answer carries (contracts/api.md "TokenPair")."""

    player_id: uuid.UUID
    access: str
    refresh: str
    providers: tuple[str, ...]
    access_expires_in: int = ACCESS_EXPIRES_IN


def now() -> datetime:
    """Token times are whole seconds, so a row and its token's `iat` and `exp` agree exactly."""
    return timezone.now().replace(microsecond=0)


def open_session(player: Player, device: Device, *, client: ClientInfo) -> IssuedTokens:
    """A sign-in: a new session for `player` on `device`, and its first token pair.

    Other sessions stay (FR-010), except the least recently renewed when the player's live
    sessions reach the cap. Runs in the caller's transaction, or its own.
    """
    with transaction.atomic(savepoint=False):  # nothing to roll back on its own
        at = now()
        _make_room(player, at)
        session = PlayerSession.objects.create(
            player=player,
            device=device,
            current_jti=uuid7(),
            current_issued_at=at,
            current_expires_at=at + tokens.REFRESH_LIFETIME,
            current_kid=settings.AUTH_SIGNING_KEYS[0].kid,
            last_renewed_at=at,
        )
        record_client(player, device, client, at)
        return issue(session, player)


def rotate(raw_refresh: str, *, client: ClientInfo) -> IssuedTokens:
    """`POST /v1/auth/refresh` (research R3, contracts/tokens.md "Rotation").

    The current token rotates. The previous one, spent within the retry window, gets the same
    successor again, byte for byte. Any other spent token ends the session.
    """
    claims = tokens.decode_refresh(raw_refresh)  # token_expired or token_invalid
    with transaction.atomic():
        player = lock_player(claims.player_id)
        session = (
            PlayerSession.objects.select_for_update(of=("self",))
            .select_related("device")
            .filter(pk=claims.session_id, player_id=claims.player_id)
            .first()
        )
        if player is None or session is None or session.status == PlayerSession.Status.ENDED:
            raise ApiError(ErrorCode.TOKEN_INVALID)
        if not player.is_active:
            raise ApiError(ErrorCode.ACCOUNT_DELETED)
        at = now()
        if claims.jti == session.current_jti:
            _advance(session, at)
            record_client(player, session.device, client, at)
            return issue(session, player)
        if _is_replay(session, claims.jti, at):
            _keep_kid_in_ring(session)
            return issue(session, player)
        end_session(session, PlayerSession.EndReason.REUSE)
    # Outside the block, so the ending commits before the refusal.
    security.warning(
        "spent refresh token used again, session ended",
        extra={
            "event": "refresh_reuse",
            "player_id": str(session.player_id),
            "session_id": str(session.id),
            "session_age_s": int((at - session.created_at).total_seconds()),
        },
    )
    raise ApiError(ErrorCode.TOKEN_INVALID)


def end_session(session: PlayerSession, reason: PlayerSession.EndReason) -> None:
    session.status = PlayerSession.Status.ENDED
    session.end_reason = reason
    session.ended_at = timezone.now()
    session.save(update_fields=["status", "end_reason", "ended_at", "updated_at"])


def live_sessions(player: Player, at: datetime) -> list[PlayerSession]:
    """Active and not lapsed, least recently renewed first."""
    return list(
        PlayerSession.objects.filter(
            player=player, status=PlayerSession.Status.ACTIVE, current_expires_at__gt=at
        ).order_by("last_renewed_at", "id")
    )


def issue(session: PlayerSession, player: Player) -> IssuedTokens:
    """A new access token, and the refresh token the session's current claims make."""
    providers = tuple(sorted(player.identities.values_list("provider", flat=True)))
    return IssuedTokens(
        player_id=player.id,
        access=tokens.mint_access(player.id, session.id),
        refresh=tokens.mint_refresh(
            player_id=player.id,
            session_id=session.id,
            jti=session.current_jti,
            issued_at=session.current_issued_at,
            expires_at=session.current_expires_at,
            kid=session.current_kid,
        ),
        providers=providers,
    )


def record_client(player: Player, device: Device, client: ClientInfo, at: datetime) -> None:
    """The headers of a token issue, on the player and the device. No other request writes them
    (FR-018)."""
    player.last_seen_at = at
    player.client_version = client.version
    player.platform = client.platform
    player.save(update_fields=["last_seen_at", "client_version", "platform", "updated_at"])
    device.last_seen_at = at
    device.app_version = client.version
    device.platform = client.platform
    device.save(update_fields=["last_seen_at", "app_version", "platform", "updated_at"])


def _advance(session: PlayerSession, at: datetime) -> None:
    """The current token becomes the previous one, spent now, and a new one is current."""
    session.previous_jti = session.current_jti
    session.previous_spent_at = at
    session.current_jti = uuid7()
    session.current_issued_at = at
    session.current_expires_at = at + tokens.REFRESH_LIFETIME
    session.current_kid = settings.AUTH_SIGNING_KEYS[0].kid
    session.last_renewed_at = at
    session.save(
        update_fields=[
            "previous_jti",
            "previous_spent_at",
            "current_jti",
            "current_issued_at",
            "current_expires_at",
            "current_kid",
            "last_renewed_at",
            "updated_at",
        ]
    )


def _is_replay(session: PlayerSession, jti: uuid.UUID, at: datetime) -> bool:
    window = timedelta(seconds=settings.AUTH_REFRESH_RETRY_SECONDS)
    return (
        jti == session.previous_jti
        and session.previous_spent_at is not None
        and at - session.previous_spent_at <= window
    )


def _keep_kid_in_ring(session: PlayerSession) -> None:
    """A replay re-signs with the session's stored key. If that key has been retired since, the
    successor is re-signed with the current key, which then becomes the stored one (R13)."""
    ring = {key.kid for key in settings.AUTH_SIGNING_KEYS}
    if session.current_kid not in ring:
        session.current_kid = settings.AUTH_SIGNING_KEYS[0].kid
        session.save(update_fields=["current_kid", "updated_at"])


def lock_player(player_id: uuid.UUID) -> Player | None:
    """The player's row, locked. Every flow that writes a player's sessions, devices or links
    takes this lock first, so two flows never wait on each other's rows in opposite order."""
    return Player.objects.select_for_update().filter(pk=player_id).first()


def _make_room(player: Player, at: datetime) -> None:
    """Hold the player's row, then end sessions until a new one fits under the cap."""
    lock_player(player.pk)
    live = live_sessions(player, at)
    excess = len(live) - settings.AUTH_MAX_SESSIONS_PER_PLAYER + 1
    for session in live[: max(0, excess)]:
        end_session(session, PlayerSession.EndReason.LIMIT)
        security.info(
            "session ended by the cap",
            extra={
                "event": "session_limit",
                "player_id": str(player.id),
                "session_id": str(session.id),
            },
        )
