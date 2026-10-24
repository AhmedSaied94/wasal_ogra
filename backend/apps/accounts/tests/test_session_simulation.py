"""SC-002: 30 days of renewals every 15 minutes, one answer in five lost and retried (B02 R3)."""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime, timedelta

import pytest
import time_machine

from apps.accounts.models import PlayerSession
from apps.accounts.services import players, sessions
from apps.accounts.tests.factories import CLIENT

pytestmark = pytest.mark.django_db

T0 = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)
RENEWALS = 30 * 24 * 4  # every 15 minutes for 30 days: 2,880


def test_a_month_of_play_with_lost_answers_keeps_the_session(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="wassal.security")
    with time_machine.travel(T0, tick=False) as clock:
        issued, _ = players.create_or_return(uuid.uuid4(), "android", "ar-EG", client=CLIENT)
        held = issued.refresh
        for renewal in range(1, RENEWALS + 1):
            clock.move_to(T0 + timedelta(minutes=15 * renewal))
            answer = sessions.rotate(held, client=CLIENT)
            if renewal % 5 == 0:
                # The answer is lost: the app retries the same token 5 s later.
                clock.shift(timedelta(seconds=5))
                retried = sessions.rotate(held, client=CLIENT)
                assert retried.refresh == answer.refresh
            held = answer.refresh

    session = PlayerSession.objects.get()
    assert session.status == "active"
    assert session.end_reason == ""
    assert session.current_expires_at == T0 + timedelta(minutes=15 * RENEWALS, days=30)
    assert not [r for r in caplog.records if r.__dict__.get("event") == "refresh_reuse"]
