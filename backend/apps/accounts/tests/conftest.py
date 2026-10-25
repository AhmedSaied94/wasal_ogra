"""Fixtures for the accounts tests: Google's key set and ID tokens, and signed-in players (B02).

Google is a local `ThreadingHTTPServer` serving a JWKS of a test RSA key, as B04's `pack_server`
serves packs: a real HTTP fetch, not a mock (research R15).
"""

from __future__ import annotations

import json
import threading
import time
import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateKey
from django.test import Client
from jwt.algorithms import RSAAlgorithm
from pytest_django import Settings

from apps.accounts.services import google
from apps.accounts.tests.factories import bearer, sign_in

CLIENT_ID = "test-client.apps.googleusercontent.com"
ISSUER = "https://accounts.google.com"
KID = "test-g1"


@dataclass
class GoogleKeys:
    """The served key set. Set `mode` to `error` (a 500) or `slow` (sleep past the timeout)."""

    key: RSAPrivateKey
    kid: str = KID
    url: str = ""
    mode: str = "serve"
    delay: float = 3.0
    requests: list[str] = field(default_factory=list)
    extra_keys: list[dict[str, Any]] = field(default_factory=list)
    body: bytes | None = None  # served as is, with a 200, in place of the key set

    def jwks(self) -> dict[str, Any]:
        public = RSAAlgorithm.to_jwk(self.key.public_key(), as_dict=True)
        return {
            "keys": [{**public, "kid": self.kid, "alg": "RS256", "use": "sig"}, *self.extra_keys]
        }


class _Handler(BaseHTTPRequestHandler):
    state: GoogleKeys

    def do_GET(self) -> None:
        self.state.requests.append(self.path)
        if self.state.mode == "error":
            self.send_error(500)
            return
        if self.state.mode == "slow":
            time.sleep(self.state.delay)
        body = self.state.body or json.dumps(self.state.jwks()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        pass


@pytest.fixture(scope="session")
def google_key() -> RSAPrivateKey:
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture
def google_jwks(google_key: RSAPrivateKey, settings: Settings) -> Iterator[GoogleKeys]:
    state = GoogleKeys(key=google_key)
    handler = type("Handler", (_Handler,), {"state": state})
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    server.daemon_threads = True
    state.url = f"http://127.0.0.1:{server.server_address[1]}/oauth2/v3/certs"
    settings.GOOGLE_JWKS_URL = state.url
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield state
    finally:
        server.shutdown()
        server.server_close()
        google.reset()


MakeToken = Callable[..., str]


@pytest.fixture
def make_google_token(google_key: RSAPrivateKey) -> MakeToken:
    """An ID token as Google signs it. Keyword overrides replace claims (`None` drops one), and
    `key`, `kid` and `algorithm` change the signature."""

    def make(sub: str = "g-subject-1", **overrides: Any) -> str:
        key = overrides.pop("key", google_key)
        kid = overrides.pop("kid", KID)
        algorithm = overrides.pop("algorithm", "RS256")
        now = int(time.time())
        claims: dict[str, Any] = {
            "iss": ISSUER,
            "aud": CLIENT_ID,
            "azp": CLIENT_ID,
            "sub": sub,
            "iat": now,
            "exp": now + 3600,
            "email": f"{sub}@example.test",
            "email_verified": True,
            "name": f"Name of {sub}",
            "picture": f"https://example.test/{sub}.png",
        }
        claims.update(overrides)
        claims = {name: value for name, value in claims.items() if value is not None}
        return jwt.encode(claims, key, algorithm=algorithm, headers={"kid": kid})

    return make


@dataclass
class SignedIn:
    """A player signed in through `POST /v1/auth/anonymous`, with a client and its tokens."""

    client: Client
    install: uuid.UUID
    player_id: str
    access: str
    refresh: str

    @property
    def headers(self) -> dict[str, str]:
        return bearer(self.access)

    def link(self, id_token: str, **extra: Any) -> Any:
        return self.client.post(
            "/v1/auth/link",
            data={"provider": "google", "id_token": id_token, **extra},
            content_type="application/json",
            headers=self.headers,
        )


def signed_in(install: uuid.UUID | None = None) -> SignedIn:
    client = Client()
    install = install or uuid.uuid4()
    body = sign_in(client, install).json()
    return SignedIn(client, install, body["player_id"], body["access"], body["refresh"])


@pytest.fixture
def player_client(db: None) -> SignedIn:
    return signed_in()
