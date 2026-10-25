"""A full batch costs a bounded number of queries (B03 tasks.md T037, research R20)."""

from __future__ import annotations

from datetime import timedelta
from typing import Any

import pytest
import time_machine
from django.utils import timezone
from pytest_django import DjangoAssertNumQueries

from apps.accounts.models import Player
from apps.economy.tests.helpers import reasons, run, trip_result, trip_start

pytestmark = pytest.mark.django_db

PAIRS = 50  # 100 operations, the most a batch holds
MAX_QUERIES = 40


def test_100_operations_run_in_at_most_40_queries(
    player: Player, published_pack: int, django_assert_max_num_queries: DjangoAssertNumQueries
) -> None:
    t0 = timezone.now() - timedelta(hours=24)
    with time_machine.travel(t0, tick=False):
        run(player)  # the wallet, created a day ago
    envelopes: list[dict[str, Any]] = []
    for n in range(PAIRS):
        at = t0 + timedelta(minutes=25 * (n + 1))
        start = trip_start("line_hay.01", published_pack, at=at)
        envelopes += [start, trip_result(start, "line_hay.01", at=at + timedelta(minutes=2))]
    with django_assert_max_num_queries(MAX_QUERIES):
        result = run(player, *envelopes)
    assert reasons(result) == ["accepted"] * (2 * PAIRS)
