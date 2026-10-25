"""One player per install id, under any race (B02 FR-003, SC-001, research R4)."""

from __future__ import annotations

import random
import threading
import uuid
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor

import pytest
from django.db import connection
from django.test import Client

from apps.accounts.models import Device, Player
from apps.accounts.services import players
from apps.accounts.tests.factories import CLIENT, sign_in

pytestmark = [pytest.mark.django_db(transaction=True), pytest.mark.usefixtures("no_throttle")]


def closing[T](work: Callable[[], T]) -> Callable[[], T]:
    """Each thread has its own database connection; close it so teardown can drop the database."""

    def run() -> T:
        try:
            return work()
        finally:
            connection.close()

    return run


def test_ten_simultaneous_requests_with_one_new_id_make_one_player() -> None:
    install = uuid.uuid4()
    barrier = threading.Barrier(10)
    answers: list[tuple[int, str]] = []
    lock = threading.Lock()

    def request() -> None:
        client = Client()
        barrier.wait()
        response = sign_in(client, install)
        with lock:
            answers.append((response.status_code, response.json()["player_id"]))

    threads = [threading.Thread(target=closing(request)) for _ in range(10)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert Player.objects.count() == 1
    assert Device.objects.count() == 1
    player_id = str(Player.objects.get().id)
    assert {player for _, player in answers} == {player_id}
    statuses = sorted(status for status, _ in answers)
    assert statuses.count(201) == 1
    assert statuses.count(200) == 9


def test_a_thousand_ids_called_ten_times_each_make_a_thousand_players() -> None:
    """SC-001, through the service: 10,000 calls on 16 threads."""
    installs = [uuid.uuid4() for _ in range(1000)]
    calls = [install for install in installs for _ in range(10)]
    # Shuffled, so the threads spread over many ids and still meet on some: the barrier test above
    # is the head-on race.
    random.Random(1000).shuffle(calls)  # noqa: S311 - an order, not a secret

    def run(share: list[uuid.UUID]) -> int:
        created = 0
        for install in share:
            created += players.create_or_return(install, "android", "ar-EG", client=CLIENT)[1]
        return created

    shares = [calls[thread::16] for thread in range(16)]
    with ThreadPoolExecutor(max_workers=16) as pool:
        created = sum(pool.map(lambda share: closing(lambda: run(share))(), shares))

    assert Player.objects.count() == 1000
    assert Device.objects.count() == 1000
    assert created == 1000
