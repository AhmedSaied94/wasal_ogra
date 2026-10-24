"""Two renewals racing with one token both get the same successor (B02 spec Edge Cases, R3)."""

from __future__ import annotations

import threading
import uuid

import pytest
from django.db import connection
from django.test import Client

from apps.accounts import tokens
from apps.accounts.models import PlayerSession
from apps.accounts.tests.factories import renew, sign_in

pytestmark = [pytest.mark.django_db(transaction=True), pytest.mark.usefixtures("no_throttle")]


def test_two_simultaneous_renewals_get_the_same_successor() -> None:
    first = sign_in(Client(), uuid.uuid4()).json()
    barrier = threading.Barrier(2)
    answers: list[tuple[int, str]] = []
    lock = threading.Lock()

    def request() -> None:
        try:
            barrier.wait()
            response = renew(Client(), first["refresh"])
            with lock:
                answers.append((response.status_code, response.json()["refresh"]))
        finally:
            connection.close()

    threads = [threading.Thread(target=request) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert [status for status, _ in answers] == [200, 200]
    assert answers[0][1] == answers[1][1]
    session = PlayerSession.objects.get(pk=tokens.decode_refresh(first["refresh"]).session_id)
    assert session.status == "active"
    assert session.current_jti == tokens.decode_refresh(answers[0][1]).jti
