"""Verifying Google ID tokens (B02 research R6, FR-022, FR-023)."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateKey
from jwt.algorithms import RSAAlgorithm
from pytest_django import Settings

from apps.accounts.services import google
from apps.accounts.tests.conftest import KID, GoogleKeys, MakeToken
from apps.common.errors import ApiError, ErrorCode

pytestmark = pytest.mark.usefixtures("google_jwks")


def reason_of(raw: str) -> str:
    with pytest.raises(ApiError) as excinfo:
        google.verify_id_token(raw)
    assert excinfo.value.error_code is ErrorCode.PROVIDER_TOKEN_INVALID
    assert excinfo.value.details["provider"] == "google"
    reason: str = excinfo.value.details["reason"]
    return reason


def segment(value: dict[str, object]) -> str:
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()


def test_a_valid_token_gives_only_its_subject(make_google_token: MakeToken) -> None:
    assert google.verify_id_token(make_google_token("g-123")) == "g-123"


@pytest.mark.parametrize("issuer", ["accounts.google.com", "https://accounts.google.com"])
def test_both_issuer_spellings(make_google_token: MakeToken, issuer: str) -> None:
    assert google.verify_id_token(make_google_token(iss=issuer)) == "g-subject-1"


def test_a_minute_of_clock_difference_is_allowed(make_google_token: MakeToken) -> None:
    now = int(time.time())
    assert google.verify_id_token(make_google_token(iat=now - 3600, exp=now - 30))
    assert reason_of(make_google_token(iat=now - 3600, exp=now - 61)) == "expired"


def test_every_audience_in_the_setting_is_accepted(
    make_google_token: MakeToken, settings: Settings
) -> None:
    settings.GOOGLE_OAUTH_CLIENT_IDS = (
        "other.apps.googleusercontent.com",
        "test-client.apps.googleusercontent.com",
    )
    assert google.verify_id_token(make_google_token())


@pytest.mark.parametrize(
    ("overrides", "reason"),
    [
        ({"aud": "someone-else.apps.googleusercontent.com"}, "audience"),
        ({"aud": None}, "malformed"),
        ({"iss": "https://evil.example"}, "issuer"),
        ({"sub": None}, "malformed"),
        ({"sub": ""}, "malformed"),
        ({"sub": "x" * 256}, "malformed"),
        ({"exp": None}, "malformed"),
    ],
)
def test_claims_that_fail(
    make_google_token: MakeToken, overrides: dict[str, object], reason: str
) -> None:
    assert reason_of(make_google_token(**overrides)) == reason


def test_another_key_with_the_same_kid_is_a_bad_signature(make_google_token: MakeToken) -> None:
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    assert reason_of(make_google_token(key=other)) == "signature"


def test_alg_none_is_a_bad_signature(make_google_token: MakeToken) -> None:
    claims = jwt.decode(make_google_token(), options={"verify_signature": False})
    unsigned = f"{segment({'alg': 'none', 'kid': KID})}.{segment(claims)}."
    assert reason_of(unsigned) == "signature"


def test_hs256_with_the_public_key_is_a_bad_signature(
    make_google_token: MakeToken, google_key: RSAPrivateKey
) -> None:
    pem = google_key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    claims = jwt.decode(make_google_token(), options={"verify_signature": False})
    header = segment({"alg": "HS256", "kid": KID, "typ": "JWT"})
    payload = segment(claims)
    signature = hmac.new(pem, f"{header}.{payload}".encode(), hashlib.sha256).digest()
    forged = f"{header}.{payload}.{base64.urlsafe_b64encode(signature).rstrip(b'=').decode()}"
    assert reason_of(forged) == "signature"


@pytest.mark.parametrize("raw", ["not-a-jwt", "a.b.c", "", "e30.e30.e30"])
def test_what_is_not_a_jwt_is_malformed(raw: str) -> None:
    assert reason_of(raw) == "malformed"


def test_an_unknown_kid_refetches_once(
    make_google_token: MakeToken,
    google_jwks: GoogleKeys,
    monkeypatch: pytest.MonkeyPatch,
    settings: Settings,
) -> None:
    settings.GOOGLE_KEYS_CACHE_SECONDS = 3600
    monkeypatch.setattr(google, "REFRESH_COOLDOWN_SECONDS", 0)
    assert google.verify_id_token(make_google_token())
    assert len(google_jwks.requests) == 1
    # Google rotates: the new key is published, then signs.
    new = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public = RSAAlgorithm.to_jwk(new.public_key(), as_dict=True)
    google_jwks.extra_keys.append({**public, "kid": "test-g2", "alg": "RS256", "use": "sig"})
    assert google.verify_id_token(make_google_token(key=new, kid="test-g2"))
    assert len(google_jwks.requests) == 2
    # A kid that isn't there after the refetch is a bad signature, after one more fetch.
    assert reason_of(make_google_token(kid="test-g9")) == "signature"
    assert len(google_jwks.requests) == 3


def test_within_the_cooldown_an_unknown_kid_does_not_refetch(
    make_google_token: MakeToken, google_jwks: GoogleKeys, settings: Settings
) -> None:
    settings.GOOGLE_KEYS_CACHE_SECONDS = 3600
    assert google.verify_id_token(make_google_token())
    assert reason_of(make_google_token(kid="test-g9")) == "signature"
    assert len(google_jwks.requests) == 1


def test_the_key_set_is_cached(
    make_google_token: MakeToken, google_jwks: GoogleKeys, settings: Settings
) -> None:
    settings.GOOGLE_KEYS_CACHE_SECONDS = 3600
    google.verify_id_token(make_google_token("a"))
    google.verify_id_token(make_google_token("b"))
    assert len(google_jwks.requests) == 1


def test_without_a_cache_every_verification_fetches(
    make_google_token: MakeToken, google_jwks: GoogleKeys
) -> None:
    google.verify_id_token(make_google_token("a"))
    google.verify_id_token(make_google_token("b"))
    assert len(google_jwks.requests) == 2


@pytest.mark.parametrize("mode", ["error", "slow"])
def test_unreachable_keys_with_nothing_cached_are_a_dependency_error(
    make_google_token: MakeToken, google_jwks: GoogleKeys, settings: Settings, mode: str
) -> None:
    settings.AUTH_HTTP_TIMEOUT_SECONDS = 1
    google_jwks.mode, google_jwks.delay = mode, 1.5
    with pytest.raises(ApiError) as excinfo:
        google.verify_id_token(make_google_token())
    assert excinfo.value.error_code is ErrorCode.DEPENDENCY_UNAVAILABLE


def test_cached_keys_survive_an_outage(
    make_google_token: MakeToken, google_jwks: GoogleKeys, settings: Settings
) -> None:
    settings.GOOGLE_KEYS_CACHE_SECONDS = 3600
    assert google.verify_id_token(make_google_token())
    google_jwks.mode = "error"
    assert google.verify_id_token(make_google_token("again"))


@pytest.mark.parametrize(
    "body",
    [b"<html>maintenance</html>", b"[]", b'{"keys": []}', b'{"keys": [{"kty": "oct"}]}'],
    ids=["not-json", "not-an-object", "no-keys", "no-signing-key"],
)
def test_a_key_set_that_can_t_be_used_is_a_dependency_error(
    make_google_token: MakeToken, google_jwks: GoogleKeys, body: bytes
) -> None:
    """Google answering with something other than a key set is Google being unavailable: never a
    500, and never the player's token blamed for it."""
    google_jwks.body = body
    with pytest.raises(ApiError) as excinfo:
        google.verify_id_token(make_google_token())
    assert excinfo.value.error_code is ErrorCode.DEPENDENCY_UNAVAILABLE


def test_after_a_failed_fetch_the_process_fails_fast(
    make_google_token: MakeToken, google_jwks: GoogleKeys, monkeypatch: pytest.MonkeyPatch
) -> None:
    """PyJWKClient fetches under a lock: during an outage every waiting link would otherwise hold
    a worker for the whole timeout."""
    google_jwks.mode = "error"
    for _ in range(3):
        with pytest.raises(ApiError) as excinfo:
            google.verify_id_token(make_google_token())
        assert excinfo.value.error_code is ErrorCode.DEPENDENCY_UNAVAILABLE
    assert len(google_jwks.requests) == 1
    google_jwks.mode = "serve"
    monkeypatch.setattr(google, "FAILED_FETCH_SECONDS", 0)
    assert google.verify_id_token(make_google_token())
    assert len(google_jwks.requests) == 2


def test_cached_keys_are_served_while_a_refetch_fails(
    make_google_token: MakeToken,
    google_jwks: GoogleKeys,
    monkeypatch: pytest.MonkeyPatch,
    settings: Settings,
) -> None:
    settings.GOOGLE_KEYS_CACHE_SECONDS = 3600
    monkeypatch.setattr(google, "REFRESH_COOLDOWN_SECONDS", 0)
    assert google.verify_id_token(make_google_token())
    google_jwks.mode = "error"
    with pytest.raises(ApiError) as excinfo:
        google.verify_id_token(make_google_token(kid="test-g9"))  # an unknown kid refetches
    assert excinfo.value.error_code is ErrorCode.DEPENDENCY_UNAVAILABLE
    assert google.verify_id_token(make_google_token("again"))  # the cached kid still works
    assert len(google_jwks.requests) == 2
