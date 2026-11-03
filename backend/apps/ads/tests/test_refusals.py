"""Forged, repeated or extra callbacks grant nothing (B07 US2 AS1-AS7, FR-005-FR-010)."""

from __future__ import annotations

import logging
import time
import uuid
from datetime import timedelta
from typing import Any

import pytest
from django.test import Client

from apps.accounts.models import Player
from apps.ads.models import AdReward
from apps.ads.services import dev_signing
from apps.ads.tests.conftest import AdmobKeys, Callback
from apps.ads.tests.signing import SSV, signed_query
from apps.economy.models import LedgerEntry

pytestmark = pytest.mark.django_db

DAY_MS = 24 * 3600 * 1000


def grants() -> int:
    return LedgerEntry.objects.filter(reason="ssv_grant").count()


def lookup(api: Any, nonce: str) -> Any:
    return api.client.get(f"/v1/ads/rewards/{nonce}", headers=api.headers)


def only_row() -> AdReward:
    return AdReward.objects.get()


@pytest.mark.parametrize(
    "forge",
    [
        lambda q: q.replace("reward_item=piggy", "reward_item=pigge", 1),  # tampered
        lambda q: q[: q.rfind("&signature=")],  # unsigned
        lambda q: q + "&user_id=someone",  # a parameter after key_id
    ],
)
def test_a_forged_callback_is_refused_and_not_recorded(
    player: Player, admob_keys: AdmobKeys, client: Client, forge: Any
) -> None:
    query, _ = signed_query(user_id=str(player.pk))
    response = client.get(f"{SSV}?{forge(query)}")
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "signature_invalid"
    assert not AdReward.objects.exists()
    assert grants() == 0


def test_an_unknown_key_is_refused(player: Player, admob_keys: AdmobKeys, client: Client) -> None:
    query, _ = signed_query(key=dev_signing.new_key(), key_id=4242, user_id=str(player.pk))
    assert client.get(f"{SSV}?{query}").status_code == 403
    assert not AdReward.objects.exists()


def test_the_same_callback_twice_grants_once(player: Player, callback: Callback) -> None:
    first = callback(user_id=str(player.pk))
    again = Client().get(f"{SSV}?{first.query}")
    assert (first.status_code, again.status_code) == (200, 200)
    assert AdReward.objects.count() == 1
    assert grants() == 2  # JENEHAT and BONAT, once


def test_a_second_piggy_the_same_day_is_capped(api: Any, callback: Callback) -> None:
    callback(user_id=api.player_id)
    second = callback(user_id=api.player_id)
    assert second.status_code == 200
    row = AdReward.objects.get(nonce=second.nonce)
    assert (row.outcome, row.jenehat, row.bonat) == ("cap_reached", 0, 0)
    assert lookup(api, second.nonce).json() == {"status": "refused", "reason": "cap_reached"}
    assert grants() == 2


def test_a_reused_reference_is_recorded_without_it(api: Any, callback: Callback) -> None:
    first = callback(user_id=api.player_id)
    reused = callback(user_id=api.player_id, nonce=first.nonce)
    assert reused.status_code == 200
    duplicate = AdReward.objects.get(outcome="duplicate_reference")
    assert duplicate.nonce is None
    assert first.nonce in duplicate.custom_data
    assert lookup(api, first.nonce).json()["status"] == "granted"


@pytest.mark.parametrize("state", ["empty", "unknown", "pending_deletion", "deleted"])
def test_a_callback_for_no_active_player_is_unattributed(
    player: Player, callback: Callback, state: str
) -> None:
    user_id = {"empty": "", "unknown": str(uuid.uuid4())}.get(state, str(player.pk))
    if state in ("pending_deletion", "deleted"):
        Player.objects.filter(pk=player.pk).update(status=state)
    assert callback(user_id=user_id).status_code == 200
    row = only_row()
    assert (row.outcome, row.player_id) == ("unattributed", None)
    assert grants() == 0


def test_a_phone_placement_is_not_the_servers(player: Player, callback: Callback) -> None:
    callback(user_id=str(player.pk), placement="result_double")
    assert (only_row().outcome, only_row().placement) == ("not_server_placement", "result_double")
    assert grants() == 0


@pytest.mark.parametrize(
    "custom", [None, "not json", "[1, 2]", '{"placement": "morning_piggy", "nonce": "x"}', '"s"']
)
def test_unusable_custom_data_is_malformed(
    player: Player, callback: Callback, custom: str | None
) -> None:
    assert callback(user_id=str(player.pk), custom_data=custom).status_code == 200
    row = only_row()
    assert (row.outcome, row.nonce) == ("malformed", None)
    assert grants() == 0


def test_a_callback_older_than_seven_days_is_expired(api: Any, callback: Callback) -> None:
    now_ms = int(time.time() * 1000)
    old = callback(user_id=api.player_id, timestamp=str(now_ms - 7 * DAY_MS - 60_000))
    assert AdReward.objects.get(nonce=old.nonce).outcome == "expired"
    assert lookup(api, old.nonce).json() == {"status": "refused", "reason": "expired"}
    edge = callback(user_id=api.player_id, timestamp=str(now_ms - 7 * DAY_MS + 60_000))
    assert AdReward.objects.get(nonce=edge.nonce).outcome == "granted"


def test_unavailable_keys_answer_503_and_record_nothing(
    player: Player, admob_keys: AdmobKeys, client: Client
) -> None:
    admob_keys.mode = "error"
    query, _ = signed_query(user_id=str(player.pk))
    response = client.get(f"{SSV}?{query}")
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "dependency_unavailable"
    assert not AdReward.objects.exists()


@pytest.mark.parametrize("timestamp", [None, "abc", "-5", "1e3", "99999999999999999999"])
def test_an_unusable_timestamp_is_malformed_not_expired(
    player: Player, callback: Callback, timestamp: str | None
) -> None:
    assert callback(user_id=str(player.pk), timestamp=timestamp).status_code == 200
    assert (only_row().outcome, only_row().callback_at) == ("malformed", None)


@pytest.mark.parametrize("amount", ["1.5", "", "x", "99999999999"])
def test_an_unusable_reward_amount_is_malformed(
    player: Player, callback: Callback, amount: str
) -> None:
    assert callback(user_id=str(player.pk), reward_amount=amount).status_code == 200
    assert (only_row().outcome, only_row().reward_amount) == ("malformed", 0)


def test_over_long_values_are_cut_and_malformed(player: Player, callback: Callback) -> None:
    response = callback(
        user_id=str(player.pk),
        custom_data="c" * 600,
        ad_unit="u" * 100,
        reward_item="i" * 100,
        ad_network="n" * 50,
    )
    assert response.status_code == 200
    row = only_row()
    assert row.outcome == "malformed"
    assert (len(row.custom_data), len(row.ad_unit), len(row.reward_item), len(row.ad_network)) == (
        512,
        64,
        64,
        32,
    )


@pytest.mark.parametrize("transaction_id", [None, "", "t" * 129])
def test_no_usable_transaction_id_is_answered_and_not_recorded(
    player: Player, callback: Callback, caplog: pytest.LogCaptureFixture, transaction_id: Any
) -> None:
    caplog.set_level(logging.INFO, logger="apps.ads")
    assert callback(user_id=str(player.pk), transaction_id=transaction_id).status_code == 200
    assert not AdReward.objects.exists()
    lines = [r for r in caplog.records if r.name == "apps.ads" and r.msg == "ad_ssv_callback"]
    assert [getattr(r, "outcome", None) for r in lines] == ["malformed"]


def test_a_reference_held_by_a_refused_row_is_not_taken_twice(
    player: Player, callback: Callback
) -> None:
    nonce = str(uuid.uuid4())
    callback(user_id=str(uuid.uuid4()), nonce=nonce)  # unattributed, holds the reference
    callback(user_id=str(uuid.uuid4()), nonce=nonce)  # unattributed too, without it
    held = sorted(str(n) for n in AdReward.objects.values_list("nonce", flat=True))
    assert held == sorted([nonce, "None"])
    assert callback(user_id=str(player.pk), nonce=nonce).status_code == 200
    assert AdReward.objects.filter(outcome="duplicate_reference").count() == 1


def test_a_future_timestamp_is_not_expired(player: Player, callback: Callback) -> None:
    ahead = int(time.time() * 1000) + int(timedelta(hours=1).total_seconds() * 1000)
    callback(user_id=str(player.pk), timestamp=str(ahead))
    assert only_row().outcome == "granted"
