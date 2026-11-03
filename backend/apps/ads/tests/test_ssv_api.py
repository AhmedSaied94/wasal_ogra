"""`GET /v1/ads/ssv` is Google's, not the app's (B07 contracts/api.md, research R3)."""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from django.test import Client

from apps.accounts.models import Player
from apps.ads.models import AdReward
from apps.ads.tests.conftest import AdmobKeys, Callback
from apps.ads.tests.signing import SSV, signed_query

pytestmark = pytest.mark.django_db


def test_no_token_and_no_client_headers_are_needed(player: Player, callback: Callback) -> None:
    response = callback(user_id=str(player.pk))
    assert response.status_code == 200
    assert AdReward.objects.get().outcome == "granted"


def test_an_outdated_version_header_changes_nothing(
    player: Player, admob_keys: AdmobKeys, client: Client, live_settings: Any
) -> None:
    live_settings(min_client_version_android="9.0.0", latest_client_version_android="9.0.0")
    query, _ = signed_query(user_id=str(player.pk))
    response = client.get(
        f"{SSV}?{query}", headers={"x-client-version": "1.0.0", "x-platform": "android"}
    )
    assert response.status_code == 200


def test_it_answers_and_grants_during_maintenance(
    player: Player, callback: Callback, live_settings: Any
) -> None:
    live_settings(maintenance_enabled=True)
    assert callback(user_id=str(player.pk)).status_code == 200
    assert AdReward.objects.get().outcome == "granted"


def test_the_body_never_says_what_happened(player: Player, callback: Callback) -> None:
    answers = [
        callback(user_id=str(player.pk)),  # granted
        callback(user_id=str(player.pk)),  # cap_reached
        callback(user_id=str(uuid.uuid4())),  # unattributed
        callback(user_id=str(player.pk), placement="result_double"),
        callback(user_id=str(player.pk), custom_data="not json"),
    ]
    assert {(a.status_code, a.content) for a in answers} == {(200, b"{}")}
    assert sorted(AdReward.objects.values_list("outcome", flat=True)) == sorted(
        ["granted", "cap_reached", "unattributed", "not_server_placement", "malformed"]
    )


def test_only_get(admob_keys: AdmobKeys, client: Client) -> None:
    query, _ = signed_query()
    assert client.post(f"{SSV}?{query}").status_code == 405


def test_the_callback_is_limited_per_address(
    admob_keys: AdmobKeys, client: Client, settings: Any
) -> None:
    settings.THROTTLE_SSV_RATE = "2/min"
    codes = [client.get(f"{SSV}?{signed_query()[0]}").status_code for _ in range(3)]
    assert codes == [200, 200, 429]
    assert client.get(SSV).json()["error"]["code"] == "rate_limited"
