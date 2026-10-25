"""Sending again never applies twice (B03 tasks.md T035, SC-001, constitution VI)."""

from __future__ import annotations

from datetime import datetime, timedelta
from itertools import pairwise
from typing import Any

import pytest
import time_machine
from django.utils import timezone

from apps.accounts.models import Player
from apps.economy.models import Currency, LedgerEntry, ProcessedOp
from apps.economy.tests.helpers import (
    Api,
    batch,
    ledger_sum,
    run,
    signed_in_api,
    trip_result,
    trip_start,
    wallet_of,
)
from apps.progress.models import TripProgress, TripRun

pytestmark = pytest.mark.django_db

TRIPS = 20
GAP = timedelta(minutes=25)  # more than a liter's regeneration, so no start overdrafts


def rows(player_id: str) -> dict[str, int]:
    return {
        "ledger": LedgerEntry.objects.filter(player_id=player_id).count(),
        "processed": ProcessedOp.objects.filter(player_id=player_id).count(),
        "runs": TripRun.objects.filter(player_id=player_id).count(),
    }


def test_the_same_batch_sent_three_times_gives_the_same_answer(
    api: Api, published_pack: int
) -> None:
    start = trip_start("line_hay.01", published_pack)
    body = batch(start, trip_result(start, "line_hay.01"), trip_start("nope", published_pack))
    answers = [api.sync(body).json() for _ in range(3)]
    # The repeats were sent on the old base, so only state_stale differs.
    assert [a.pop("state_stale") for a in answers] == [False, True, True]
    assert answers[1] == answers[0]
    assert answers[2] == answers[0]
    assert answers[0]["wallet"]["jenehat"] == 10
    assert rows(api.player_id) == {"ledger": 1, "processed": 3, "runs": 1}


def offline_trips(version: int, t0: datetime) -> list[dict[str, Any]]:
    """Twenty plays of line_hay.01, recorded at their own times."""
    ops: list[dict[str, Any]] = []
    for n in range(TRIPS):
        at = t0 + GAP * (n + 1)
        start = trip_start("line_hay.01", version, at=at)
        stars = 3 - n % 3
        ops += [start, trip_result(start, "line_hay.01", at=at + timedelta(minutes=2), stars=stars)]
    return ops


def snapshot(player: Player) -> dict[str, Any]:
    wallet = wallet_of(player)
    return {
        "wallet": (wallet.jenehat, wallet.bonat, wallet.fuel, wallet.fuel_updated_at),
        "state_version": wallet.state_version,
        "ledger": (ledger_sum(player, Currency.JENEHAT), ledger_sum(player, Currency.BONAT)),
        "progress": list(
            TripProgress.objects.filter(player=player).values_list(
                "trip_id", "best_stars", "best_time_ms", "plays"
            )
        ),
        "rows": rows(str(player.pk)),
    }


def test_lost_answers_end_in_the_state_of_a_clean_run(published_pack: int) -> None:
    t0 = timezone.now() - timedelta(hours=10)
    clean, lossy = signed_in_api(), signed_in_api()
    with time_machine.travel(t0, tick=False):
        for api in (clean, lossy):
            run(api.player)  # the wallets start at t0 (the tokens are minted now)

    clean_ops, lossy_ops = offline_trips(published_pack, t0), offline_trips(published_pack, t0)
    cuts = [0, 14, 27, len(clean_ops)]

    clean_answers = []
    for first, last in pairwise(cuts):
        response = clean.sync(batch(*clean_ops[first:last]))
        clean_answers += response.json()["results"]

    # The lossy phone: every fifth operation's answer is lost and the operation goes out again in
    # the next batch, and the second batch's whole answer is lost, so it is sent twice.
    lossy_answers: dict[str, dict[str, Any]] = {}
    unanswered: list[dict[str, Any]] = []
    for index, (first, last) in enumerate(pairwise(cuts)):
        body = batch(*unanswered, *lossy_ops[first:last])
        response = lossy.sync(body)
        if index == 1:
            response = lossy.sync(body)
        unanswered = []
        for position, entry in enumerate(response.json()["results"], start=1):
            if position % 5 == 0:
                unanswered.append(
                    next(o for o in body["ops"] if o["client_txn_id"] == entry["client_txn_id"])
                )
            else:
                lossy_answers[entry["client_txn_id"]] = entry
    for entry in lossy.sync(batch(*unanswered)).json()["results"]:
        lossy_answers[entry["client_txn_id"]] = entry

    assert all(a["status"] == "accepted" for a in clean_answers)
    assert [lossy_answers[o["client_txn_id"]]["status"] for o in lossy_ops] == ["accepted"] * (
        2 * TRIPS
    )
    clean_state, lossy_state = snapshot(clean.player), snapshot(lossy.player)
    assert lossy_state == clean_state
    assert clean_state["rows"] == {"ledger": TRIPS, "processed": 2 * TRIPS, "runs": TRIPS}
    assert clean_state["state_version"] == 3


def test_a_batch_replayed_through_the_engine_changes_nothing(
    player: Player, published_pack: int
) -> None:
    start = trip_start("line_hay.01", published_pack)
    envelopes = (start, trip_result(start, "line_hay.01"))
    first = run(player, *envelopes)
    before = snapshot(player)
    again = run(player, *envelopes, base=first.state_version)
    assert [r.outcome for r in again.results] == [r.outcome for r in first.results]
    assert snapshot(player) == before
