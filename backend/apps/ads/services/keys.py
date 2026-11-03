"""Google's AdMob verifier keys (B07 research R2, FR-003, FR-004).

One key set per process, the shape of B02's `accounts/services/google.py`. The list
(`{"keys": [{"keyId", "pem", "base64"}]}`) is held for `ADS_KEYS_CACHE_SECONDS`. A key id the set
doesn't hold refetches it at most once per `REFRESH_COOLDOWN_SECONDS`, so made-up ids can't make
every callback fetch from Google. After a failed fetch, the process fails at once for
`FAILED_FETCH_SECONDS` instead of holding a worker on the timeout; keys already held keep
verifying. Every way of not getting usable keys is `KeysUnavailable` (a 503, which AdMob retries).
"""

from __future__ import annotations

import contextlib
import json
import logging
import time
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit

import requests
from cryptography.exceptions import UnsupportedAlgorithm
from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePublicKey
from cryptography.hazmat.primitives.serialization import load_pem_public_key
from django.conf import settings

logger = logging.getLogger("apps.ads")

# An unknown key id refetches the list at most this often (FR-003). Google publishes a key before
# signing with it.
REFRESH_COOLDOWN_SECONDS = 60
# After a failed fetch, fail at once for this long.
FAILED_FETCH_SECONDS = 15
# Google's list is well under 1 KB; anything this large is not it.
MAX_KEY_LIST_BYTES = 64 * 1024
# `ads_dev_callback`'s key list is a file, read only where its key can sign (B07 plan, structure).
FILE_ENVIRONMENTS = ("dev", "test")
# How the list fails to be a key list: not JSON, not the shape, not a P-256 PEM.
UNUSABLE = (ValueError, KeyError, TypeError, AttributeError, UnsupportedAlgorithm)


class KeysUnavailable(Exception):
    """Google's keys can't be had, and the key needed isn't held."""


class _KeySet:
    def __init__(self, config: tuple[Any, ...]) -> None:
        self.config = config
        self.keys: dict[int, EllipticCurvePublicKey] | None = None
        self.fetched_at = 0.0
        self.refetched_at: float | None = None
        self.failed_at: float | None = None

    def public_key(self, key_id: int) -> EllipticCurvePublicKey | None:
        now = time.time()
        if self.keys is None:
            self._fetch(now)
        elif now - self.fetched_at >= settings.ADS_KEYS_CACHE_SECONDS:
            with contextlib.suppress(KeysUnavailable):  # the held keys keep verifying (FR-004)
                self._fetch(now)
        key = (self.keys or {}).get(key_id)
        if key is not None:
            return key
        if self.refetched_at is not None and now - self.refetched_at < REFRESH_COOLDOWN_SECONDS:
            return None
        self.refetched_at = now
        self._fetch(now)
        return (self.keys or {}).get(key_id)

    def _fetch(self, now: float) -> None:
        if self.failed_at is not None and now - self.failed_at < FAILED_FETCH_SECONDS:
            raise KeysUnavailable("the key list failed moments ago")
        try:
            self.keys = _parse(_download())
        except (requests.RequestException, OSError, *UNUSABLE) as error:
            self.failed_at = now
            logger.warning("admob_keys_unavailable", extra={"error": type(error).__name__})
            raise KeysUnavailable("the key list is unusable") from error
        self.fetched_at = now
        self.failed_at = None


def _download() -> Any:
    url = settings.ADS_VERIFIER_KEYS_URL
    parts = urlsplit(url)
    if parts.scheme == "file":
        if settings.WASSAL_ENV not in FILE_ENVIRONMENTS:
            raise ValueError("a file key list is for dev and test only")
        return json.loads(Path(unquote(parts.path)).read_text(encoding="utf-8"))
    response = requests.get(url, timeout=settings.ADS_HTTP_TIMEOUT_SECONDS, allow_redirects=False)
    response.raise_for_status()
    if response.status_code != 200 or len(response.content) > MAX_KEY_LIST_BYTES:
        raise ValueError("not the key list")
    return response.json()


def _parse(document: Any) -> dict[int, EllipticCurvePublicKey]:
    entries = document["keys"]
    if not isinstance(entries, list) or not entries:
        raise ValueError("no keys")
    parsed: dict[int, EllipticCurvePublicKey] = {}
    for entry in entries:
        try:
            key_id = entry["keyId"]
            key = load_pem_public_key(entry["pem"].encode())
        except UNUSABLE:
            continue  # one bad entry doesn't take the others down (security review L1)
        if type(key_id) is int and isinstance(key, EllipticCurvePublicKey):
            parsed[key_id] = key
    if not parsed:
        raise ValueError("no usable key")
    return parsed


_set: _KeySet | None = None


def public_key(key_id: int) -> EllipticCurvePublicKey | None:
    """The key with this id, or None if Google doesn't publish one. Raises `KeysUnavailable`."""
    global _set
    config = (settings.ADS_VERIFIER_KEYS_URL, settings.WASSAL_ENV)
    if _set is None or _set.config != config:
        _set = _KeySet(config)
    return _set.public_key(key_id)


def reset() -> None:
    """Forget the held keys (tests)."""
    global _set
    _set = None
