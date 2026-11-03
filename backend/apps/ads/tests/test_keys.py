"""Holding Google's verifier keys (B07 research R2, FR-003, FR-004)."""

from __future__ import annotations

import json
from datetime import timedelta
from pathlib import Path

import pytest
import requests
import time_machine
from pytest_django import Settings

from apps.ads.services import dev_signing, keys
from apps.ads.services.keys import KeysUnavailable
from apps.ads.tests.conftest import AdmobKeys


def test_keys_are_fetched_once_and_held(admob_keys: AdmobKeys, settings: Settings) -> None:
    with time_machine.travel("2026-11-03 06:00:00Z", tick=False) as traveller:
        assert keys.public_key(admob_keys.key_id) is not None
        assert keys.public_key(admob_keys.key_id) is not None
        assert admob_keys.fetches == 1
        traveller.shift(timedelta(seconds=settings.ADS_KEYS_CACHE_SECONDS - 1))
        keys.public_key(admob_keys.key_id)
        assert admob_keys.fetches == 1
        traveller.shift(timedelta(seconds=1))
        keys.public_key(admob_keys.key_id)
        assert admob_keys.fetches == 2


def test_an_unknown_id_refetches_at_most_once_a_minute(admob_keys: AdmobKeys) -> None:
    with time_machine.travel("2026-11-03 06:00:00Z", tick=False) as traveller:
        assert keys.public_key(1) is None
        assert admob_keys.fetches == 2  # the first load, then one refetch for the unknown id
        assert keys.public_key(2) is None
        traveller.shift(timedelta(seconds=keys.REFRESH_COOLDOWN_SECONDS - 1))
        assert keys.public_key(3) is None
        assert admob_keys.fetches == 2
        traveller.shift(timedelta(seconds=1))
        assert keys.public_key(4) is None
        assert admob_keys.fetches == 3


@pytest.mark.parametrize(
    "body",
    [
        None,  # mode error: a 500
        b"<html>",
        b'{"no": "keys"}',
        b'{"keys": []}',
        b'{"keys": [{"keyId": 1, "pem": "not a key"}]}',
        b'{"keys": [{"keyId": "x", "pem": ""}]}',
        b'{"keys": "nope"}',
        b"[]",
    ],
)
def test_a_failed_fetch_fails_fast(admob_keys: AdmobKeys, body: bytes | None) -> None:
    if body is None:
        admob_keys.mode = "error"
    else:
        admob_keys.body = body
    with time_machine.travel("2026-11-03 06:00:00Z", tick=False) as traveller:
        with pytest.raises(KeysUnavailable):
            keys.public_key(admob_keys.key_id)
        assert admob_keys.fetches == 1
        traveller.shift(timedelta(seconds=keys.FAILED_FETCH_SECONDS - 1))
        with pytest.raises(KeysUnavailable):
            keys.public_key(admob_keys.key_id)
        assert admob_keys.fetches == 1
        admob_keys.mode, admob_keys.body = "serve", None
        traveller.shift(timedelta(seconds=1))
        assert keys.public_key(admob_keys.key_id) is not None
        assert admob_keys.fetches == 2


def test_an_rsa_key_is_not_a_verifier_key(admob_keys: AdmobKeys) -> None:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    pem = (
        rsa.generate_private_key(public_exponent=65537, key_size=2048)
        .public_key()
        .public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    )
    admob_keys.body = json.dumps({"keys": [{"keyId": 5, "pem": pem.decode()}]}).encode()
    with pytest.raises(KeysUnavailable):
        keys.public_key(5)


def test_a_timeout_is_unavailable(admob_keys: AdmobKeys, monkeypatch: pytest.MonkeyPatch) -> None:
    def timeout(*args: object, **kwargs: object) -> None:
        raise requests.Timeout("slow")

    monkeypatch.setattr(requests, "get", timeout)
    with pytest.raises(KeysUnavailable):
        keys.public_key(admob_keys.key_id)


def test_held_keys_keep_verifying_while_the_source_fails(
    admob_keys: AdmobKeys, settings: Settings
) -> None:
    with time_machine.travel("2026-11-03 06:00:00Z", tick=False) as traveller:
        held = keys.public_key(admob_keys.key_id)
        admob_keys.mode = "error"
        traveller.shift(timedelta(seconds=settings.ADS_KEYS_CACHE_SECONDS))
        assert keys.public_key(admob_keys.key_id) == held
        assert keys.public_key(admob_keys.key_id) == held
        assert admob_keys.fetches == 2  # the failure is not retried at once
        with pytest.raises(KeysUnavailable):
            keys.public_key(12345)  # a new key can't be had


def test_a_file_url_is_read_in_dev_and_test(tmp_path: Path, settings: Settings) -> None:
    key = dev_signing.new_key()
    path = tmp_path / "keys.json"
    path.write_text(json.dumps({"keys": [dev_signing.key_entry(key, 9)]}))
    settings.ADS_VERIFIER_KEYS_URL = path.as_uri()
    keys.reset()
    try:
        assert keys.public_key(9) is not None
        settings.WASSAL_ENV = "staging"
        keys.reset()
        with pytest.raises(KeysUnavailable):
            keys.public_key(9)
    finally:
        keys.reset()


def test_a_missing_file_is_unavailable(tmp_path: Path, settings: Settings) -> None:
    settings.ADS_VERIFIER_KEYS_URL = (tmp_path / "none.json").as_uri()
    keys.reset()
    try:
        with pytest.raises(KeysUnavailable):
            keys.public_key(9)
    finally:
        keys.reset()
