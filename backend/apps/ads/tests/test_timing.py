"""How fast the callback and the lookup answer (B07 SC-005, plan "Performance Goals").

On the real PostgreSQL and Valkey, with the keys held: 100 signed callbacks for distinct players
and 100 lookups. Prints both p95s, so the gate run records them. Staging repeats it with real
callbacks after the deploy (T055).
"""

from __future__ import annotations

import statistics
import time

import pytest
from django.test import Client

from apps.ads.tests.conftest import AdmobKeys, new_player
from apps.ads.tests.signing import SSV, signed_query
from apps.economy.tests.helpers import signed_in_api

pytestmark = pytest.mark.django_db

RUNS = 100


def p95(seconds: list[float]) -> float:
    return statistics.quantiles(seconds, n=20)[-1]


def test_callback_and_lookup_p95(admob_keys: AdmobKeys, no_throttle: None) -> None:
    client = Client()
    client.get(f"{SSV}?{signed_query()[0]}")  # load the keys
    callbacks: list[float] = []
    for _ in range(RUNS):
        query, _ = signed_query(user_id=str(new_player().pk))
        started = time.perf_counter()
        assert client.get(f"{SSV}?{query}").status_code == 200
        callbacks.append(time.perf_counter() - started)

    api = signed_in_api()
    query, nonce = signed_query(user_id=api.player_id)
    client.get(f"{SSV}?{query}")
    lookups: list[float] = []
    for _ in range(RUNS):
        started = time.perf_counter()
        assert api.client.get(f"/v1/ads/rewards/{nonce}", headers=api.headers).status_code == 200
        lookups.append(time.perf_counter() - started)

    print(
        f"\nads timing: callback p95 {p95(callbacks) * 1000:.1f} ms, "
        f"lookup p95 {p95(lookups) * 1000:.1f} ms"
    )
    assert p95(callbacks) < 1.0
    assert p95(lookups) <= 0.1
