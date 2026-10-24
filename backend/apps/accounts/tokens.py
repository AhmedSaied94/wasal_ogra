"""Player tokens (B02 research R1, R2, R13, contracts/tokens.md).

simplejwt's token classes over a key ring: `AUTH_SIGNING_KEYS` holds `kid:key` entries, the first
signs, and the `kid` header picks the key that verifies. Both kinds carry `token_type`, `sub` (the
player id), `sid` (the session id), `jti`, `iat` and `exp`, and nothing personal (FR-015).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, cast

import jwt
from django.conf import settings
from rest_framework_simplejwt.backends import TokenBackend
from rest_framework_simplejwt.exceptions import TokenBackendError, TokenBackendExpiredToken
from rest_framework_simplejwt.tokens import AccessToken, Token

from apps.common.errors import ApiError, ErrorCode
from apps.common.ids import uuid7
from config.env import SigningKey

# Fixed by the constitution ("Security & privacy"), not settings.
ACCESS_LIFETIME = timedelta(minutes=15)
REFRESH_LIFETIME = timedelta(days=30)
ALGORITHM = "HS256"
# The longest token a request may carry (contracts/api.md): ours are about 400 characters.
MAX_TOKEN_LENGTH = 4096
INVALID = "Token is invalid"


class KeyRingBackend(TokenBackend):
    """HS256 over the key ring. Every decode verifies the signature and the `kid`."""

    def __init__(self, ring: Sequence[SigningKey]) -> None:
        super().__init__(ALGORITHM, leeway=0)
        self.keys = {key.kid: key.key for key in ring}
        self.current_kid = ring[0].kid

    def encode(self, payload: dict[str, Any], kid: str | None = None) -> str:
        """Sign with `kid`'s key, the current one by default. One payload, one token: HS256 is
        deterministic and PyJWT keeps the payload's order, so a re-sign is byte-identical."""
        kid = kid or self.current_kid
        return jwt.encode(payload, self.keys[kid], algorithm=ALGORITHM, headers={"kid": kid})

    def get_verifying_key(self, token: Token) -> bytes:
        try:
            kid = jwt.get_unverified_header(cast("str | bytes", token)).get("kid")
        except (jwt.InvalidTokenError, TypeError) as exc:
            raise TokenBackendError(INVALID) from exc
        key = self.keys.get(kid) if isinstance(kid, str) else None
        if key is None:
            raise TokenBackendError(INVALID)  # no kid, or one retired from the ring
        return key

    def decode(
        self, token: Token, verify: bool = True, *, verify_exp: bool = True
    ) -> dict[str, Any]:
        """The payload of a token this service signed. The signature is checked even when
        `verify` is false: nothing may read an unverified player token. `exp` is checked with no
        leeway unless `verify_exp` is false, which only the renewal limit uses."""
        try:
            payload: dict[str, Any] = jwt.decode(
                cast("str | bytes", token),
                self.get_verifying_key(token),
                algorithms=[ALGORITHM],
                leeway=0,
                options={"verify_exp": verify_exp, "require": ["exp", "iat", "jti"]},
            )
        except jwt.ExpiredSignatureError as exc:
            raise TokenBackendExpiredToken("Token is expired") from exc
        except (jwt.InvalidTokenError, TypeError) as exc:
            raise TokenBackendError(INVALID) from exc
        return payload


def backend() -> KeyRingBackend:
    """Built per call from the settings, so a test or a key rotation needs no reset."""
    return KeyRingBackend(settings.AUTH_SIGNING_KEYS)


class PlayerAccessToken(AccessToken):
    lifetime = ACCESS_LIFETIME

    def get_token_backend(self) -> TokenBackend:
        return backend()

    def set_jti(self) -> None:
        self.payload["jti"] = str(uuid7())


class PlayerRefreshToken(Token):
    """The refresh token's type and lifetime. Its claims are minted by `mint_refresh`, from the
    session row, so a replay can re-sign them (research R3)."""

    token_type = "refresh"  # noqa: S105 - a claim value, not a secret
    lifetime = REFRESH_LIFETIME

    def get_token_backend(self) -> TokenBackend:
        return backend()

    def set_jti(self) -> None:
        self.payload["jti"] = str(uuid7())


@dataclass(frozen=True)
class RefreshClaims:
    player_id: uuid.UUID
    session_id: uuid.UUID
    jti: uuid.UUID
    issued_at: datetime
    expires_at: datetime
    kid: str


def read_access(raw: str | bytes) -> PlayerAccessToken:
    """A verified access token, or simplejwt's `TokenError` (`ExpiredTokenError` once expired)."""
    return PlayerAccessToken(cast("Token", raw))  # simplejwt types the raw token as `Token`


def mint_access(player_id: uuid.UUID, session_id: uuid.UUID) -> str:
    token = PlayerAccessToken()
    token["sub"] = str(player_id)
    token["sid"] = str(session_id)
    return str(token)


def mint_refresh(
    *,
    player_id: uuid.UUID,
    session_id: uuid.UUID,
    jti: uuid.UUID,
    issued_at: datetime,
    expires_at: datetime,
    kid: str,
) -> str:
    """The refresh token with exactly these claims. The claims are built in one fixed order, so the
    same arguments always give the same token, byte for byte (research R3)."""
    payload = {
        "token_type": PlayerRefreshToken.token_type,
        "sub": str(player_id),
        "sid": str(session_id),
        "jti": str(jti),
        "iat": int(issued_at.timestamp()),
        "exp": int(expires_at.timestamp()),
    }
    return backend().encode(payload, kid)


def decode_refresh(raw: str, *, verify_exp: bool = True) -> RefreshClaims:
    """A refresh token's claims, or `401 token_expired` / `401 token_invalid`."""
    try:
        header = jwt.get_unverified_header(raw)
        payload = backend().decode(cast("Token", raw), verify_exp=verify_exp)
    except TokenBackendExpiredToken:
        raise ApiError(ErrorCode.TOKEN_EXPIRED) from None
    except (TokenBackendError, jwt.InvalidTokenError, TypeError):
        raise ApiError(ErrorCode.TOKEN_INVALID) from None
    if payload.get("token_type") != PlayerRefreshToken.token_type:
        raise ApiError(ErrorCode.TOKEN_INVALID)
    try:
        return RefreshClaims(
            player_id=_uuid(payload["sub"]),
            session_id=_uuid(payload["sid"]),
            jti=_uuid(payload["jti"]),
            issued_at=datetime.fromtimestamp(payload["iat"], UTC),
            expires_at=datetime.fromtimestamp(payload["exp"], UTC),
            kid=header["kid"],
        )
    except (KeyError, TypeError, ValueError, OverflowError, OSError):
        raise ApiError(ErrorCode.TOKEN_INVALID) from None


def _uuid(value: object) -> uuid.UUID:
    if not isinstance(value, str):
        raise TypeError("claim is not a string")
    return uuid.UUID(value)
