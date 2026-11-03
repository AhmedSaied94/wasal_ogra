"""Signed AdMob callbacks for the tests (B07 tasks.md T004), with the session's key."""

from __future__ import annotations

from typing import Any

from apps.ads.services import dev_signing
from apps.ads.services.dev_signing import DEFAULT_KEY_ID, custom_data

__all__ = ["DEFAULT_KEY_ID", "SSV", "custom_data", "signed_query"]

SSV = "/v1/ads/ssv"
_KEY: list[Any] = []


def use_key(key: Any) -> None:
    """Set by the `admob_key` fixture: the key `signed_query` signs with by default."""
    _KEY[:] = [key]


def signed_query(**params: Any) -> tuple[str, str]:
    """`(query, nonce)`, signed with the session's key unless `key=` names another."""
    key = params.pop("key", None) or _KEY[0]
    return dev_signing.signed_query(key, **params)
