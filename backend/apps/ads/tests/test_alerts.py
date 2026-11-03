"""The operator's alerts (B07 FR-007, research R11, SC-007), on the real Valkey cache."""

from __future__ import annotations

from datetime import timedelta
from typing import Any

import pytest
import sentry_sdk
import time_machine
from django.test import Client

from apps.ads.services import alerts
from apps.ads.tests.conftest import AdmobKeys
from apps.ads.tests.signing import SSV, signed_query

pytestmark = pytest.mark.django_db


@pytest.fixture
def captured(monkeypatch: pytest.MonkeyPatch) -> list[tuple[str, dict[str, Any]]]:
    calls: list[tuple[str, dict[str, Any]]] = []

    def capture(message: str, **kwargs: Any) -> str:
        calls.append((message, kwargs))
        return "event-id"

    monkeypatch.setattr(sentry_sdk, "capture_message", capture)
    return calls


def test_refused_signatures_alert_once_an_hour(
    admob_keys: AdmobKeys, client: Client, captured: list[tuple[str, dict[str, Any]]]
) -> None:
    forged = signed_query()[0].replace("reward_item=piggy", "reward_item=pigge", 1)
    with time_machine.travel("2026-11-03 06:00:00Z", tick=False) as traveller:
        for _ in range(alerts.ALERT_SIGNATURE_THRESHOLD):
            assert client.get(f"{SSV}?{forged}").status_code == 403
        assert captured == []
        client.get(f"{SSV}?{forged}")  # the 21st
        assert captured == [
            (
                "AdMob SSV: refused signatures",
                {"level": "warning", "fingerprint": ["ads", "ssv-signature"]},
            )
        ]
        for _ in range(19):  # up to the 40th
            client.get(f"{SSV}?{forged}")
        assert len(captured) == 1
        traveller.shift(timedelta(hours=1, minutes=5))  # the old buckets have left the hour
        for _ in range(alerts.ALERT_SIGNATURE_THRESHOLD + 1):
            client.get(f"{SSV}?{forged}")
        assert len(captured) == 2


def test_unavailable_keys_alert_under_their_own_guard(
    admob_keys: AdmobKeys, client: Client, captured: list[tuple[str, dict[str, Any]]]
) -> None:
    admob_keys.mode = "error"
    with time_machine.travel("2026-11-03 06:00:00Z", tick=False) as traveller:
        for _ in range(3):
            assert client.get(f"{SSV}?{signed_query()[0]}").status_code == 503
            traveller.shift(timedelta(seconds=20))  # past the fast-fail window
        assert captured == [
            (
                "AdMob SSV: verifier keys unavailable",
                {"level": "warning", "fingerprint": ["ads", "ssv-keys"]},
            )
        ]


def test_a_cache_outage_loses_a_count_not_a_request(
    monkeypatch: pytest.MonkeyPatch, captured: list[tuple[str, dict[str, Any]]]
) -> None:
    from redis.exceptions import RedisError

    def down(*args: object, **kwargs: object) -> None:
        raise RedisError("down")

    from django.core.cache import cache

    monkeypatch.setattr(cache, "add", down)
    alerts.signature_refused()
    alerts.keys_unavailable()
    assert captured == []
