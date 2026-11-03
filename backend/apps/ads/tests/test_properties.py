"""Random callback sequences keep the ledger and the cap (B07 SC-002, research R4-R6).

Each example signs callbacks for three new players and one unknown id: new transactions, exact
repeats and reused references, with the clock moved across Cairo midnights. After the sequence,
and again after replaying all of it: every wallet equals its ledger, no player has more grants on
a game day than the cap, and the replay changed nothing.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any

import pytest
import time_machine
from django.db.models import Count
from hypothesis import HealthCheck, given
from hypothesis import settings as hypothesis_settings
from hypothesis import strategies as st

from apps.ads.models import AdReward
from apps.ads.services import ssv
from apps.ads.tests.conftest import AdmobKeys, new_player
from apps.ads.tests.signing import signed_query
from apps.economy.models import Currency, LedgerEntry, Wallet
from apps.economy.tests.helpers import ledger_sum
from apps.liveops import settings as live

pytestmark = pytest.mark.django_db

START = datetime.fromisoformat("2026-11-03T20:00:00+00:00")  # 22:00 in Cairo
STEPS = st.lists(
    st.tuples(
        st.integers(0, 3),  # 3: an id that is no player
        st.sampled_from(["new", "new", "repeat", "reuse"]),
        st.sampled_from([0, 1, 90, 240, 600]),  # minutes the clock moves first
    ),
    max_size=14,
)


def snapshot(players: list[Any]) -> dict[str, Any]:
    ids = [p.pk for p in players]
    return {
        "rows": sorted(AdReward.objects.filter(player_id__in=ids).values_list("id", flat=True)),
        "entries": LedgerEntry.objects.filter(player_id__in=ids).count(),
        "wallets": sorted(Wallet.objects.filter(pk__in=ids).values_list("pk", "jenehat", "bonat")),
    }


@hypothesis_settings(suppress_health_check=[HealthCheck.function_scoped_fixture])
@given(steps=STEPS)
def test_any_sequence_keeps_the_ledger_and_the_cap(
    admob_keys: AdmobKeys, steps: list[tuple[int, str, int]]
) -> None:
    players = [new_player() for _ in range(3)]
    ids = [str(p.pk) for p in players] + [str(uuid.uuid4())]
    sent: list[tuple[datetime, str]] = []
    queries: list[str] = []
    at = START
    with time_machine.travel(at, tick=False) as traveller:
        for who, action, minutes in steps:
            at += timedelta(minutes=minutes)
            traveller.move_to(at)
            if action == "repeat" and queries:
                query = queries[-1]
            else:
                nonce = None
                if action == "reuse" and sent:
                    nonce = sent[-1][1]
                query, nonce = signed_query(user_id=ids[who], nonce=nonce)
                sent.append((at, nonce))
                queries.append(query)
            ssv.process(query)
        after = snapshot(players)
        for query in queries:  # AdMob retrying everything, a day later
            traveller.move_to(at + timedelta(days=1))
            ssv.process(query)
        assert snapshot(players) == after

    cap = live.current()["ads_morning_piggy_daily_cap"]
    for player in players:
        wallet = Wallet.objects.filter(pk=player.pk).first()
        if wallet is not None:
            assert wallet.jenehat == ledger_sum(player, Currency.JENEHAT)
            assert wallet.bonat == ledger_sum(player, Currency.BONAT)
        per_day = (
            AdReward.objects.filter(player=player, outcome="granted")
            .values("game_date")
            .annotate(n=Count("id"))
        )
        assert all(day["n"] <= cap for day in per_day)
