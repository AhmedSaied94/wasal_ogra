"""Fixtures for the ads tests (B07 tasks.md T004).

Google's AdMob key list is a local `ThreadingHTTPServer` serving the public half of a P-256 key
made for the test session, in AdMob's shape, as B02's `google_jwks` serves Google's keys: a real
HTTP fetch, not a mock. Callbacks are signed with the private half (`signing.signed_query`).
"""

from __future__ import annotations

import json
import threading
import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from django.test import Client
from pytest_django import Settings

from apps.accounts.models import Player
from apps.accounts.services import players
from apps.accounts.tests.factories import CLIENT
from apps.ads.services import dev_signing, keys
from apps.ads.tests import signing
from apps.ads.tests.signing import DEFAULT_KEY_ID, SSV
from apps.content.tests.conftest import (
    author,
    channel,
    packs_dir,
    publisher,
    sample_imported,
    sample_reviewed,
)
from apps.economy.tests.conftest import published_pack, published_packs
from apps.economy.tests.helpers import Api, signed_in_api

# The published sample pack, for the placement caps through sync (test_placement_caps.py).
__all__ = [
    "author",
    "channel",
    "packs_dir",
    "published_pack",
    "published_packs",
    "publisher",
    "sample_imported",
    "sample_reviewed",
]


@dataclass
class AdmobKeys:
    """The served key list. `mode`: `serve`, `error` (a 500) or `garbage` (not JSON). `body`
    replaces the list with any bytes; `extra` adds entries (a rotation)."""

    key: ec.EllipticCurvePrivateKey
    key_id: int = DEFAULT_KEY_ID
    url: str = ""
    mode: str = "serve"
    body: bytes | None = None
    extra: list[tuple[ec.EllipticCurvePrivateKey, int]] = field(default_factory=list)
    requests: list[str] = field(default_factory=list)

    @property
    def fetches(self) -> int:
        return len(self.requests)

    def rotate(self, key: ec.EllipticCurvePrivateKey, key_id: int) -> None:
        self.extra.append((key, key_id))

    def key_list(self) -> dict[str, Any]:
        entries = [(self.key, self.key_id), *self.extra]
        return {"keys": [dev_signing.key_entry(k, i) for k, i in entries]}


class _Handler(BaseHTTPRequestHandler):
    state: AdmobKeys

    def do_GET(self) -> None:
        self.state.requests.append(self.path)
        if self.state.mode == "error":
            self.send_error(500)
            return
        if self.state.mode == "garbage":
            body = b"<html>not json</html>"
        else:
            body = self.state.body or json.dumps(self.state.key_list()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        pass


@pytest.fixture(scope="session")
def admob_key() -> ec.EllipticCurvePrivateKey:
    key = dev_signing.new_key()
    signing.use_key(key)
    return key


@pytest.fixture
def admob_keys(admob_key: ec.EllipticCurvePrivateKey, settings: Settings) -> Iterator[AdmobKeys]:
    state = AdmobKeys(key=admob_key)
    handler = type("Handler", (_Handler,), {"state": state})
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    server.daemon_threads = True
    state.url = f"http://127.0.0.1:{server.server_address[1]}/admob/reward/verifier-keys.json"
    settings.ADS_VERIFIER_KEYS_URL = state.url
    keys.reset()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield state
    finally:
        server.shutdown()
        server.server_close()
        keys.reset()


def new_player() -> Player:
    issued, _ = players.create_or_return(uuid.uuid4(), "android", "ar-EG", client=CLIENT)
    return Player.objects.get(pk=issued.player_id)


@pytest.fixture
def player(db: None) -> Player:
    return new_player()


@pytest.fixture
def api(db: None) -> Api:
    """A player signed in through the API, as the app is."""
    return signed_in_api()


Callback = Callable[..., Any]


@pytest.fixture
def callback(admob_keys: AdmobKeys, client: Client) -> Callback:
    """`callback(user_id=…, …)`: sign a callback and send it; the response, with `.nonce` set."""

    def send(**params: Any) -> Any:
        query, nonce = signing.signed_query(**params)
        response: Any = client.get(f"{SSV}?{query}")
        response.nonce = nonce
        response.query = query
        return response

    return send
