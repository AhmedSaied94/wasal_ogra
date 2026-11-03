"""Two callbacks at once (B07 spec edge cases, research R4), on real PostgreSQL."""

from __future__ import annotations

import threading
from collections.abc import Callable

import pytest
from django.db import connection
from django.test import Client

from apps.accounts.models import Player
from apps.ads.models import AdReward
from apps.ads.tests.conftest import AdmobKeys, new_player
from apps.ads.tests.signing import SSV, signed_query
from apps.economy.models import LedgerEntry

pytestmark = pytest.mark.django_db(transaction=True)


def at_once(*queries: str) -> list[int]:
    barrier = threading.Barrier(len(queries))
    codes: list[int] = [0] * len(queries)

    def send(index: int, query: str) -> Callable[[], None]:
        def run() -> None:
            try:
                barrier.wait()
                codes[index] = Client().get(f"{SSV}?{query}").status_code
            finally:
                connection.close()

        return run

    threads = [threading.Thread(target=send(i, q)) for i, q in enumerate(queries)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return codes


@pytest.fixture
def someone(admob_keys: AdmobKeys) -> Player:
    return new_player()


def test_one_transaction_delivered_twice_at_once_grants_once(someone: Player) -> None:
    query, _ = signed_query(user_id=str(someone.pk))
    assert at_once(query, query) == [200, 200]
    assert AdReward.objects.count() == 1
    assert LedgerEntry.objects.filter(player=someone, reason="ssv_grant").count() == 2


def test_two_transactions_for_one_player_at_once_grant_once(someone: Player) -> None:
    first, _ = signed_query(user_id=str(someone.pk))
    second, _ = signed_query(user_id=str(someone.pk))
    assert at_once(first, second) == [200, 200]
    assert sorted(AdReward.objects.values_list("outcome", flat=True)) == [
        "cap_reached",
        "granted",
    ]
    assert LedgerEntry.objects.filter(player=someone, reason="ssv_grant").count() == 2
