"""`GET /v1/state` (B03 tasks.md T057, contracts/api.md "GET /v1/state", spec US4)."""

from __future__ import annotations

import json
import threading
from typing import Any

import pytest
from django.db import connection
from django.test import Client
from django.utils import timezone

from apps.accounts.models import Player
from apps.accounts.services import sessions
from apps.accounts.tests.factories import CLIENT, make_device, make_player
from apps.economy.models import Currency, GrantRecord, Wallet
from apps.economy.services import state
from apps.economy.tests.helpers import (
    HEADERS,
    STATE,
    Api,
    batch,
    give,
    grant,
    op,
    run,
    spend,
    trip_result,
    trip_start,
    txn_of,
)
from apps.progress.models import StoryState

KEYS = {
    "state_version",
    "server_time",
    "player",
    "wallet",
    "inventory",
    "ownership",
    "trips",
    "open_trip",
    "last_result",
    "story",
    "grants",
    "stats",
    "comeback",
}


@pytest.mark.django_db
def test_a_new_player_gets_an_empty_snapshot(api: Api) -> None:
    response = api.state()
    assert response.status_code == 200, response.content
    body = response.json()
    assert set(body) == KEYS
    assert body["state_version"] == 0
    assert body["player"] == {"display_name": "", "driver_level": 1, "settings": {}}
    assert body["inventory"] == {"change_bag": 0, "wake_all": 0, "ledger_peek": 0, "traffic_jam": 0}
    assert (body["ownership"], body["trips"]) == ([], [])
    assert (body["open_trip"], body["last_result"]) == (None, None)
    assert body["story"] == {"chapters": [], "requests_claimed": []}
    assert body["grants"] == {"tutorial": False}
    assert body["stats"] == {"trips_played": 0, "stars_total": 0, "longest_streak": 0}
    assert body["comeback"] == {"claimable": False}
    assert body["wallet"]["fuel"] == 5
    assert Wallet.objects.filter(player_id=api.player_id).exists()


@pytest.mark.django_db
def test_the_snapshot_holds_everything_the_server_has(api: Api, published_pack: int) -> None:
    player = api.player
    Player.objects.filter(pk=player.pk).update(
        display_name="Hamada", driver_level=2, settings={"digits": "arabic"}
    )
    grant(player, Currency.BONAT, 100)
    give(player, ("item", "salon.nish"), variant="crystal")
    StoryState.objects.create(player=player, chapter_id="ch1_first_job", scenes_seen=["intro"])
    now = timezone.now()
    GrantRecord.objects.create(player=player, kind="tutorial", key="tutorial", granted_at=now)
    GrantRecord.objects.create(
        player=player, kind="request", key="req_nish_crystal", granted_at=now
    )
    first, abandoned, last = (trip_start("line_hay.01", published_pack) for _ in range(3))
    run(
        player,
        spend("booster", "wake_all", 8, published_pack),
        first,
        trip_result(first, "line_hay.01", stars=2, earnings_jenehat=7, duration_ms=95_000),
        abandoned,
        last,  # abandons the one before
    )
    body = api.state().json()
    assert body["state_version"] == 1
    assert body["player"] == {
        "display_name": "Hamada",
        "driver_level": 2,
        "settings": {"digits": "arabic"},
    }
    assert body["wallet"]["jenehat"] == 7
    assert body["wallet"]["bonat"] == 92
    assert body["inventory"]["wake_all"] == 1
    assert body["ownership"] == [{"kind": "item", "sku_id": "salon.nish", "variant": "crystal"}]
    assert body["trips"] == [
        {"trip_id": "line_hay.01", "best_stars": 2, "best_time_ms": 95_000, "plays": 2}
    ]
    assert body["open_trip"] == {
        "start_txn": txn_of(last),
        "trip_id": "line_hay.01",
        "content_version": published_pack,
        "revived": False,
        "traffic_jam_ads": 0,
    }
    assert body["last_result"] == {
        "start_txn": txn_of(first),
        "outcome": "finished",
        "earnings_jenehat": 7,
        "doubled": False,
    }
    assert body["story"] == {
        "chapters": [{"chapter_id": "ch1_first_job", "status": "open", "scenes_seen": ["intro"]}],
        "requests_claimed": ["req_nish_crystal"],
    }
    assert body["grants"] == {"tutorial": True}
    # Every accepted result counts, abandoned ones too.
    assert body["stats"] == {"trips_played": 2, "stars_total": 2, "longest_streak": 0}


@pytest.mark.django_db
def test_a_trip_started_on_one_phone_is_open_on_the_other(api: Api, published_pack: int) -> None:
    start = trip_start("line_hay.01", published_pack)
    api.sync(batch(start))
    other = sessions.open_session(api.player, make_device(api.player), client=CLIENT)
    response = Client().get(STATE, headers={**HEADERS, "authorization": f"Bearer {other.access}"})
    assert response.json()["open_trip"]["start_txn"] == txn_of(start)


@pytest.mark.django_db
def test_nothing_of_anyone_else_and_no_secret_is_in_it(api: Api, published_pack: int) -> None:
    stranger = make_player(display_name="Someone")
    run(stranger, trip_start("line_hay.03", published_pack))
    text = json.dumps(api.state().json())
    for secret in (api.access, "install", "subject", "provider", "token", "refresh"):
        assert secret not in text
    assert str(stranger.pk) not in text
    assert "Someone" not in text
    assert "line_hay.03" not in text


@pytest.mark.django_db
def test_a_read_marks_activity(api: Api) -> None:
    api.state()
    before = Wallet.objects.get(player_id=api.player_id).last_active_at
    api.state()
    assert Wallet.objects.get(player_id=api.player_id).last_active_at >= before


@pytest.mark.django_db(transaction=True)
def test_a_snapshot_never_shows_a_batch_half_applied(player: Player, published_pack: int) -> None:
    """Each batch plays one trip that earns 10. A snapshot read while batches apply must agree
    with itself: the version, the wallet and the plays move together."""
    run(player)
    done = threading.Event()

    def play() -> None:
        try:
            for _ in range(5):
                start = trip_start("line_hay.01", published_pack)
                run(player, start, trip_result(start, "line_hay.01"))
        finally:
            done.set()
            connection.close()

    thread = threading.Thread(target=play)
    thread.start()
    seen: list[tuple[int, int, int]] = []
    while not done.is_set() or not seen:
        snapshot: dict[str, Any] = state.snapshot(player)
        plays = snapshot["stats"]["trips_played"]
        seen.append((snapshot["state_version"], snapshot["wallet"]["jenehat"], plays))
    thread.join()
    for version, jenehat, plays in seen:
        assert jenehat == 10 * plays == 10 * version
    assert state.snapshot(player)["state_version"] == 5


@pytest.mark.django_db
def test_ownership_and_trips_may_name_ids_the_pack_lacks(player: Player) -> None:
    give(player, ("vehicle", "retired_bus"))
    run(player, op("no_such_op", {}))
    assert state.snapshot(player)["ownership"] == [
        {"kind": "vehicle", "sku_id": "retired_bus", "variant": ""}
    ]
