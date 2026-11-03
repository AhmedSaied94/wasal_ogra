"""What a callback logs (B07 FR-007, research R13): one line, never the player or the reference."""

from __future__ import annotations

import hashlib
import logging
from typing import Any

import pytest
import sentry_sdk
from django.test import Client

from apps.accounts.models import Player
from apps.ads.tests.conftest import Callback
from apps.common.logging import ContextFilter, JsonLineFormatter

pytestmark = pytest.mark.django_db


def written(records: list[logging.LogRecord], values: list[str]) -> list[str]:
    """Each value found in a line as the stdout handler writes it (`config.settings.LOGGING`):
    Django's 4xx record carries the request object, which the formatter never serializes."""
    formatter, context = JsonLineFormatter(), ContextFilter()
    lines = []
    for record in records:
        context.filter(record)
        lines.append(formatter.format(record))
    return [value for value in values if any(value in line for line in lines)]


def test_one_line_per_callback(
    player: Player, callback: Callback, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO, logger="apps.ads")
    callback(user_id=str(player.pk), transaction_id="txn-log-1", ad_unit="unit-7")
    lines = [r for r in caplog.records if r.name == "apps.ads"]
    assert len(lines) == 1
    line: Any = lines[0]
    assert (line.msg, line.outcome, line.ad_unit, line.reward_item) == (
        "ad_ssv_callback",
        "granted",
        "unit-7",
        "piggy",
    )
    assert line.transaction == hashlib.sha256(b"txn-log-1").hexdigest()[:12]
    assert isinstance(line.key_id, int)


def test_no_player_reference_or_query_is_logged_or_sent(
    player: Player,
    callback: Callback,
    caplog: pytest.LogCaptureFixture,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    sent: list[str] = []
    monkeypatch.setattr(sentry_sdk, "capture_message", lambda m, **k: sent.append(repr((m, k))))
    caplog.set_level(logging.DEBUG)
    responses = [
        callback(user_id=str(player.pk), transaction_id="txn-secret-1"),
        callback(user_id=str(player.pk)),  # cap_reached
        callback(user_id="not-a-player"),
    ]
    forged = responses[0].query.replace("reward_item=piggy", "reward_item=pigge", 1)
    for _ in range(25):  # past the threshold, so the alert is sent too
        Client().get(f"/v1/ads/ssv?{forged}")
    assert sent, "the signature alert should have been sent"
    secrets = [str(player.pk), "txn-secret-1", "not-a-player"]
    secrets += [r.nonce for r in responses] + [r.query for r in responses]
    assert written(caplog.records, secrets) == []
    assert caplog.records
    assert not [s for s in secrets if any(s in event for event in sent)]
