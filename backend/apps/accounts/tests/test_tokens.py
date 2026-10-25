"""Player tokens and the signing key ring (B02 research R2, R13, contracts/tokens.md)."""

from __future__ import annotations

import base64
import json
import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

import jwt
import pytest
import time_machine
from django.conf import settings as django_settings
from pytest_django import Settings
from rest_framework_simplejwt.exceptions import ExpiredTokenError, TokenError

from apps.accounts import tokens
from apps.common.errors import ApiError, ErrorCode
from apps.common.ids import uuid7
from config.env import SigningKey

NOW = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)
PLAYER = uuid.UUID("0192f1c3-7d1e-7a4b-9c11-5e2f8a9b0c3d")
SESSION = uuid.UUID("0192f1c3-7d1e-7a4b-9c11-5e2f8a9b0c3e")
NEW_KEY = SigningKey("new-1", b"n" * 32)
CLAIMS = {"token_type", "sub", "sid", "jti", "iat", "exp"}


def unverified(raw: str) -> dict[str, object]:
    claims: dict[str, object] = jwt.decode(raw, options={"verify_signature": False})
    return claims


def segment(value: dict[str, object]) -> str:
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()


def refresh_at(issued_at: datetime = NOW, kid: str = "test1", jti: uuid.UUID | None = None) -> str:
    return tokens.mint_refresh(
        player_id=PLAYER,
        session_id=SESSION,
        jti=jti or uuid7(),
        issued_at=issued_at,
        expires_at=issued_at + tokens.REFRESH_LIFETIME,
        kid=kid,
    )


@pytest.fixture
def ring(settings: Settings) -> None:
    """A rotated ring: a new key signs, the test key still verifies."""
    settings.AUTH_SIGNING_KEYS = (NEW_KEY, *django_settings.AUTH_SIGNING_KEYS)


@time_machine.travel(NOW, tick=False)
def test_access_token_claims_and_header() -> None:
    raw = tokens.mint_access(PLAYER, SESSION)
    claims = unverified(raw)
    assert set(claims) == CLAIMS
    assert claims["token_type"] == "access"
    assert claims["sub"] == str(PLAYER)
    assert claims["sid"] == str(SESSION)
    assert uuid.UUID(str(claims["jti"])).version == 7
    assert claims["iat"] == int(NOW.timestamp())
    assert claims["exp"] == int(NOW.timestamp()) + 900
    assert jwt.get_unverified_header(raw) == {"alg": "HS256", "kid": "test1", "typ": "JWT"}


def test_lifetimes_are_the_constitution_s() -> None:
    assert timedelta(minutes=15) == tokens.ACCESS_LIFETIME
    assert timedelta(days=30) == tokens.REFRESH_LIFETIME


def test_refresh_token_claims() -> None:
    jti = uuid7()
    claims = unverified(refresh_at(jti=jti))
    assert set(claims) == CLAIMS
    assert claims["token_type"] == "refresh"
    assert claims["jti"] == str(jti)
    assert claims["exp"] == int(NOW.timestamp()) + 30 * 86400


def test_re_minting_a_refresh_token_is_byte_identical() -> None:
    jti = uuid7()
    assert refresh_at(jti=jti) == refresh_at(jti=jti)


@time_machine.travel(NOW, tick=False)
def test_decode_refresh_returns_the_claims() -> None:
    jti = uuid7()
    claims = tokens.decode_refresh(refresh_at(jti=jti))
    assert claims.player_id == PLAYER
    assert claims.session_id == SESSION
    assert claims.jti == jti
    assert claims.issued_at == NOW
    assert claims.expires_at == NOW + tokens.REFRESH_LIFETIME
    assert claims.kid == "test1"


@pytest.mark.usefixtures("ring")
@time_machine.travel(NOW, tick=False)
def test_the_first_key_signs_and_every_key_verifies() -> None:
    assert jwt.get_unverified_header(tokens.mint_access(PLAYER, SESSION))["kid"] == "new-1"
    old = refresh_at(kid="test1")
    assert tokens.decode_refresh(old).kid == "test1"
    assert tokens.decode_refresh(refresh_at(kid="new-1")).kid == "new-1"


def forged(header: dict[str, object], key: bytes | None = None) -> str:
    """A token with the claims of a real access token and the given header."""
    claims = unverified(tokens.mint_access(PLAYER, SESSION))
    if key is None:
        return f"{segment(header)}.{segment(claims)}."
    return jwt.encode(claims, key, algorithm="HS256", headers=header)


@pytest.mark.parametrize(
    "raw",
    [
        pytest.param(lambda: forged({"alg": "HS256", "kid": "gone"}, b"g" * 32), id="unknown kid"),
        pytest.param(lambda: jwt.encode({"a": 1}, b"k" * 32, algorithm="HS256"), id="no kid"),
        pytest.param(lambda: forged({"alg": "none", "kid": "test1"}), id="alg none"),
        pytest.param(lambda: forged({"alg": "HS256", "kid": "test1"}, b"o" * 32), id="other key"),
        pytest.param(lambda: "not.a.jwt", id="garbage"),
        pytest.param(lambda: "", id="empty"),
    ],
)
def test_tokens_that_do_not_verify_are_invalid(raw: Callable[[], str]) -> None:
    value = raw()
    with pytest.raises(TokenError):
        tokens.read_access(value)
    with pytest.raises(ApiError) as excinfo:
        tokens.decode_refresh(value)
    assert excinfo.value.error_code is ErrorCode.TOKEN_INVALID


def test_a_retired_kid_is_invalid(settings: Settings) -> None:
    raw = refresh_at(kid="test1")
    settings.AUTH_SIGNING_KEYS = (NEW_KEY,)
    with pytest.raises(ApiError) as excinfo:
        tokens.decode_refresh(raw)
    assert excinfo.value.error_code is ErrorCode.TOKEN_INVALID


def test_token_types_do_not_cross() -> None:
    with pytest.raises(TokenError):
        tokens.read_access(refresh_at(issued_at=datetime.now(UTC)))
    with pytest.raises(ApiError) as excinfo:
        tokens.decode_refresh(tokens.mint_access(PLAYER, SESSION))
    assert excinfo.value.error_code is ErrorCode.TOKEN_INVALID


def test_access_expiry_has_no_leeway() -> None:
    with time_machine.travel(NOW, tick=False):
        raw = tokens.mint_access(PLAYER, SESSION)
    with time_machine.travel(NOW + timedelta(seconds=899), tick=False):
        assert tokens.read_access(raw)["sub"] == str(PLAYER)
    with (
        time_machine.travel(NOW + timedelta(seconds=901), tick=False),
        pytest.raises(ExpiredTokenError),
    ):
        tokens.read_access(raw)


def test_refresh_expiry_has_no_leeway() -> None:
    raw = refresh_at()
    with time_machine.travel(NOW + tokens.REFRESH_LIFETIME - timedelta(seconds=1), tick=False):
        tokens.decode_refresh(raw)
    with time_machine.travel(NOW + tokens.REFRESH_LIFETIME + timedelta(seconds=1), tick=False):
        with pytest.raises(ApiError) as excinfo:
            tokens.decode_refresh(raw)
        assert excinfo.value.error_code is ErrorCode.TOKEN_EXPIRED
        # The throttle still reads the session of an expired, well-signed token.
        assert tokens.decode_refresh(raw, verify_exp=False).session_id == SESSION


def test_claims_with_the_wrong_shape_are_invalid() -> None:
    key = django_settings.AUTH_SIGNING_KEYS[0].key
    exp = int((datetime.now(UTC) + timedelta(days=1)).timestamp())
    base = {"token_type": "refresh", "sub": str(PLAYER), "sid": str(SESSION), "jti": str(uuid7())}
    for claims in (
        {**base, "iat": exp - 10},  # no exp
        {**base, "sid": "not-a-uuid", "iat": exp - 10, "exp": exp},
        {**base, "sub": 7, "iat": exp - 10, "exp": exp},
    ):
        raw = jwt.encode(claims, key, algorithm="HS256", headers={"kid": "test1"})
        with pytest.raises(ApiError) as excinfo:
            tokens.decode_refresh(raw)
        assert excinfo.value.error_code is ErrorCode.TOKEN_INVALID
