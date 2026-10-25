"""A second phone, or a stale one, catches up (B03 tasks.md T058, FR-015, spec US4).

Phone A and phone B are two sessions of one player. Each sends what it recorded on the base it
last saw; the server validates everything against its own current state.
"""

from __future__ import annotations

from datetime import timedelta

import pytest
from django.test import Client
from django.utils import timezone

from apps.accounts.services import sessions
from apps.accounts.tests.factories import CLIENT, make_device
from apps.economy.models import Currency
from apps.economy.tests.helpers import (
    HEADERS,
    STATE,
    Api,
    batch,
    grant,
    ready_for_the_salon,
    spend,
    trip_result,
    trip_start,
)

pytestmark = pytest.mark.django_db


def phone_b(api: Api) -> Api:
    other = sessions.open_session(api.player, make_device(api.player), client=CLIENT)
    headers = {**HEADERS, "authorization": f"Bearer {other.access}"}
    return Api(Client(), api.player_id, other.access, headers)


def test_a_stale_phone_is_validated_against_the_servers_state(
    api: Api, published_pack: int
) -> None:
    grant(api.player, Currency.JENEHAT, 1_000)
    ready_for_the_salon(api.player)
    b = phone_b(api)
    nish = spend("item", "salon.nish", 400, published_pack, variant="classic")
    a_answer = api.sync(batch(nish)).json()
    assert a_answer["results"][0]["status"] == "accepted"
    assert a_answer["state_version"] == 1
    # B bought the same item offline, earlier, and saw version 0.
    earlier = timezone.now() - timedelta(minutes=30)
    b_nish = spend("item", "salon.nish", 400, published_pack, variant="modern", at=earlier)
    b_start = trip_start("line_hay.01", published_pack, at=earlier)
    b_answer = b.sync(batch(b_nish, b_start, base=0)).json()
    assert b_answer["state_stale"] is True
    assert [r.get("reason", r["status"]) for r in b_answer["results"]] == [
        "already_owned",
        "accepted",  # an older occurred_at doesn't make an operation invalid
    ]
    assert b_answer["state_version"] == 2
    snapshot = b.state().json()
    assert snapshot["state_version"] == 2
    assert snapshot["ownership"] == [
        {"kind": "chapter", "sku_id": "ch3_shabka", "variant": ""},
        {"kind": "item", "sku_id": "salon.nish", "variant": "classic"},
        {"kind": "vehicle", "sku_id": "micro_old", "variant": ""},
    ]
    assert snapshot["open_trip"]["trip_id"] == "line_hay.01"
    assert snapshot["wallet"]["jenehat"] == 600


def test_replaying_on_top_of_a_snapshot_gives_the_servers_state(
    api: Api, published_pack: int
) -> None:
    """M05's `replaceBase`: the phone takes the snapshot, then re-sends what it still holds as
    pending. The pending operations the server already has change nothing."""
    start = trip_start("line_hay.01", published_pack)
    pending = batch(start, trip_result(start, "line_hay.01"))
    api.sync(pending)  # the answer was lost
    snapshot = api.state().json()
    replay = api.sync({**pending, "base_state_version": snapshot["state_version"]}).json()
    assert replay["state_stale"] is False
    assert replay["state_version"] == snapshot["state_version"]
    again = api.state().json()
    snapshot.pop("server_time")
    again.pop("server_time")
    assert again == snapshot


def test_the_state_needs_the_client_headers(api: Api) -> None:
    response = api.client.get(STATE, headers={"authorization": f"Bearer {api.access}"})
    assert response.status_code == 400
    assert api.client.post(STATE, headers=api.headers).status_code == 405
