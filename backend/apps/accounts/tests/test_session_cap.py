"""Sessions stay until they lapse, with a cap per player (B02 FR-010, US2-8, research R3)."""

from __future__ import annotations

import threading
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
import time_machine
from django.db import connection
from django.test import Client
from django.utils import timezone
from pytest_django import Settings

from apps.accounts import tokens
from apps.accounts.models import PlayerSession
from apps.accounts.tests.factories import renew, sign_in

T0 = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)


def at(seconds: float) -> time_machine.travel:
    return time_machine.travel(T0 + timedelta(seconds=seconds), tick=False)


def session_id(body: dict[str, Any]) -> uuid.UUID:
    return tokens.decode_refresh(body["refresh"], verify_exp=False).session_id


@pytest.mark.django_db
def test_a_second_sign_in_keeps_the_first_session(client: Client) -> None:
    install = uuid.uuid4()
    with at(0):
        first = sign_in(client, install).json()
    with at(10):
        second = sign_in(client, install).json()
    with at(20):
        assert renew(client, first["refresh"]).status_code == 200
        assert renew(client, second["refresh"]).status_code == 200
    assert PlayerSession.objects.filter(status="active").count() == 2


@pytest.mark.django_db
def test_the_cap_ends_the_least_recently_renewed(client: Client, settings: Settings) -> None:
    settings.AUTH_MAX_SESSIONS_PER_PLAYER = 3
    install = uuid.uuid4()
    with at(0):
        oldest = sign_in(client, install).json()
    with at(10):
        middle = sign_in(client, install).json()
    with at(20):
        newest = sign_in(client, install).json()
    with at(30):
        oldest = renew(client, oldest["refresh"]).json()  # now `middle` is the least renewed
    with at(40):
        fourth = sign_in(client, install).json()

    ended = PlayerSession.objects.get(pk=session_id(middle))
    assert (ended.status, ended.end_reason) == ("ended", "limit")
    with at(50):
        for body in (oldest, newest, fourth):
            assert renew(client, body["refresh"]).status_code == 200
        assert renew(client, middle["refresh"]).status_code == 401


@pytest.mark.django_db
def test_lapsed_sessions_do_not_count(client: Client, settings: Settings) -> None:
    settings.AUTH_MAX_SESSIONS_PER_PLAYER = 3
    install = uuid.uuid4()
    with at(0):
        for _ in range(3):
            sign_in(client, install)
    with at(timedelta(days=31).total_seconds()):
        assert sign_in(client, install).status_code == 200
    assert not PlayerSession.objects.filter(end_reason="limit").exists()


@pytest.mark.django_db(transaction=True)
@pytest.mark.usefixtures("no_throttle")
def test_simultaneous_sign_ins_stay_under_the_cap(settings: Settings) -> None:
    settings.AUTH_MAX_SESSIONS_PER_PLAYER = 3
    install = uuid.uuid4()
    sign_in(Client(), install)
    barrier = threading.Barrier(10)
    statuses: list[int] = []

    def request() -> None:
        try:
            barrier.wait()
            statuses.append(sign_in(Client(), install).status_code)
        finally:
            connection.close()

    threads = [threading.Thread(target=request) for _ in range(10)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert statuses == [200] * 10
    live = PlayerSession.objects.filter(status="active", current_expires_at__gt=timezone.now())
    assert live.count() <= 3
