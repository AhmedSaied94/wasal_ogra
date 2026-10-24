"""The daily prune of old sessions and the signing key generator (B02 research R3, R13)."""

from __future__ import annotations

import io
import re
from datetime import timedelta

import pytest
from django.core.management import call_command
from django.utils import timezone
from django_celery_beat.models import PeriodicTask

from apps.accounts.models import PlayerSession
from apps.accounts.tasks import prune_sessions
from apps.accounts.tests.factories import make_device, make_player
from apps.common.ids import uuid7
from config.env import Env

pytestmark = pytest.mark.django_db

ENTRY = re.compile(r"^k\d{8}:[A-Za-z0-9_-]{43}$")


def session(*, ended_days_ago: int | None = None, lapsed_days_ago: int | None = None) -> str:
    now = timezone.now()
    player = make_player()
    expires = now - timedelta(days=lapsed_days_ago) if lapsed_days_ago is not None else now
    row = PlayerSession.objects.create(
        player=player,
        device=make_device(player),
        current_jti=uuid7(),
        current_issued_at=expires - timedelta(days=30),
        current_expires_at=expires + timedelta(days=0 if lapsed_days_ago is not None else 30),
        current_kid="test1",
        last_renewed_at=expires - timedelta(days=30),
    )
    if ended_days_ago is not None:
        row.status = PlayerSession.Status.ENDED
        row.end_reason = PlayerSession.EndReason.REUSE
        row.ended_at = now - timedelta(days=ended_days_ago)
        row.save()
    return str(row.id)


def test_prune_deletes_only_sessions_over_30_days_gone() -> None:
    old_ended = session(ended_days_ago=31)
    old_lapsed = session(lapsed_days_ago=31)
    keep = [
        session(),  # live
        session(ended_days_ago=29),
        session(lapsed_days_ago=29),
    ]
    assert prune_sessions.apply().get() == 2
    remaining = {str(pk) for pk in PlayerSession.objects.values_list("id", flat=True)}
    assert remaining == set(keep)
    assert old_ended not in remaining
    assert old_lapsed not in remaining


def test_prune_retry_policy() -> None:
    assert prune_sessions.name == "accounts.tasks.prune_sessions"
    assert prune_sessions.max_retries == 3


def test_the_beat_row_is_created_by_migration() -> None:
    task = PeriodicTask.objects.select_related("crontab").get(name="accounts.prune_sessions")
    assert task.task == "accounts.tasks.prune_sessions"
    assert task.queue == "default"
    assert task.enabled
    assert (task.crontab.minute, task.crontab.hour) == ("30", "4")
    assert str(task.crontab.timezone) == "Africa/Cairo"


def test_the_key_generator_prints_one_entry_the_settings_accept() -> None:
    out = io.StringIO()
    call_command("auth_signing_key", stdout=out)
    lines = out.getvalue().splitlines()
    assert len(lines) == 1
    assert ENTRY.match(lines[0])
    (key,) = Env("prod", {"AUTH_SIGNING_KEYS": lines[0]}).signing_keys()
    assert len(key.key) == 32
    other = io.StringIO()
    call_command("auth_signing_key", stdout=other)
    assert other.getvalue() != out.getvalue()
