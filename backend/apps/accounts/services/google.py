"""Verifying Google ID tokens (B02 research R6, FR-022, FR-023).

PyJWT's `PyJWKClient` reads Google's published keys and keeps them for
`GOOGLE_KEYS_CACHE_SECONDS`. A token must be RS256, signed by the key its `kid` names, issued by
Google for one of `GOOGLE_OAUTH_CLIENT_IDS`, and within its time window (60 s of clock difference
allowed). Only its `sub` is kept: every other claim is dropped here, unlogged and unstored. The
token itself is never logged or echoed.
"""

from __future__ import annotations

import logging
import time
from typing import Any

import jwt
from django.conf import settings

from apps.common.errors import ApiError, ErrorCode

logger = logging.getLogger(__name__)

ISSUERS = frozenset({"accounts.google.com", "https://accounts.google.com"})
ALGORITHM = "RS256"
LEEWAY_SECONDS = 60
MAX_SUBJECT = 255  # Identity.subject
# An unknown `kid` refetches the key set at most this often, so made-up kids can't make every
# request fetch from Google. Google publishes a key days before signing with it (research R6).
REFRESH_COOLDOWN_SECONDS = 30
# After a failed fetch, the process answers 503 at once for this long instead of fetching again.
FAILED_FETCH_SECONDS = 15
# How PyJWT fails on Google's document: PyJWTError for its own checks, ValueError for a body that
# isn't JSON, KeyError and TypeError for a key without its fields.
UNUSABLE_KEYS = (jwt.PyJWTError, ValueError, KeyError, TypeError)


class GoogleKeyClient(jwt.PyJWKClient):
    """PyJWKClient, where every way of not getting usable keys is Google being unavailable.

    Unreachable, not JSON, not a key set, no signing key: each is a `PyJWKClientConnectionError`
    (a 503), never a 500 and never the player's token blamed for it. PyJWKClient fetches under a
    lock, so during an outage every waiting link would hold a worker for the whole timeout: after a
    failure, a fetch fails at once for `FAILED_FETCH_SECONDS`. Keys already cached still serve.
    """

    failed_at: float | None = None

    def get_signing_keys(self, refresh: bool = False) -> list[jwt.PyJWK]:
        cache = self.jwk_set_cache
        cached = not refresh and cache is not None and cache.get() is not None
        if not cached and self._failed_recently():
            raise jwt.PyJWKClientConnectionError("Google's keys failed moments ago")
        try:
            return super().get_signing_keys(refresh)
        except UNUSABLE_KEYS as error:
            self.failed_at = time.monotonic()
            raise jwt.PyJWKClientConnectionError("Google's keys are unusable") from error

    def _failed_recently(self) -> bool:
        return (
            self.failed_at is not None and time.monotonic() - self.failed_at < FAILED_FETCH_SECONDS
        )


_client: tuple[tuple[Any, ...], GoogleKeyClient] | None = None


def keys() -> GoogleKeyClient:
    """One client per process, rebuilt when its settings change (as tests change them)."""
    global _client
    config = (
        settings.GOOGLE_JWKS_URL,
        settings.GOOGLE_KEYS_CACHE_SECONDS,
        settings.AUTH_HTTP_TIMEOUT_SECONDS,
        REFRESH_COOLDOWN_SECONDS,
    )
    if _client is None or _client[0] != config:
        url, cache_seconds, timeout, cooldown = config
        client = GoogleKeyClient(
            url,
            cache_jwk_set=cache_seconds > 0,
            lifespan=max(1, cache_seconds),
            timeout=timeout,
            cooldown_duration=cooldown,
        )
        _client = (config, client)
    return _client[1]


def reset() -> None:
    """Forget the cached keys (tests)."""
    global _client
    _client = None


def invalid(reason: str) -> ApiError:
    return ApiError(ErrorCode.PROVIDER_TOKEN_INVALID, {"provider": "google", "reason": reason})


def verify_id_token(raw: str) -> str:
    """The Google account number (`sub`) of a valid ID token, or `422 provider_token_invalid`
    with a reason, or `503 dependency_unavailable` when Google's keys can't be had."""
    try:
        algorithm = jwt.get_unverified_header(raw).get("alg")
    except jwt.InvalidTokenError:
        raise invalid("malformed") from None
    if not isinstance(algorithm, str):
        raise invalid("malformed")
    if algorithm != ALGORITHM:
        raise invalid("signature")  # `none`, or HS256 keyed with the public key
    try:
        key = keys().get_signing_key_from_jwt(raw).key
    except jwt.PyJWKClientConnectionError:
        logger.warning("google keys unavailable")
        raise ApiError(ErrorCode.DEPENDENCY_UNAVAILABLE) from None
    except jwt.PyJWKClientError:
        raise invalid("signature") from None  # no published key has this kid
    except jwt.InvalidTokenError:
        raise invalid("malformed") from None
    claims = _decode(raw, key)
    if claims.get("iss") not in ISSUERS:
        raise invalid("issuer")
    subject = claims.get("sub")
    if not isinstance(subject, str) or not subject or len(subject) > MAX_SUBJECT:
        raise invalid("malformed")
    return subject


def _decode(raw: str, key: Any) -> dict[str, Any]:
    try:
        claims: dict[str, Any] = jwt.decode(
            raw,
            key,
            algorithms=[ALGORITHM],
            audience=list(settings.GOOGLE_OAUTH_CLIENT_IDS),
            leeway=LEEWAY_SECONDS,
            options={"require": ["exp", "iat", "iss", "aud", "sub"]},
        )
    except (jwt.ExpiredSignatureError, jwt.ImmatureSignatureError):
        raise invalid("expired") from None  # outside its time window, either side
    except jwt.InvalidAudienceError:
        raise invalid("audience") from None
    except jwt.InvalidSignatureError:
        raise invalid("signature") from None
    except jwt.InvalidTokenError:
        raise invalid("malformed") from None
    return claims
