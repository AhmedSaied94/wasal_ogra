"""The security review's findings on B07, each held by a test (H1, M1, L1, L3, L4, L5)."""

from __future__ import annotations

import json
import logging
import time
from typing import Any
from urllib.parse import quote

import pytest
from django.test import Client
from pytest_django import Settings

from apps.accounts.models import Player
from apps.ads.models import AdReward
from apps.ads.services import alerts, dev_signing, keys
from apps.ads.tests.conftest import AdmobKeys, Callback
from apps.ads.tests.signing import SSV, signed_query
from apps.economy.models import LedgerEntry

pytestmark = pytest.mark.django_db

DAY_MS = 24 * 3600 * 1000


# -- H1: only our ad units grant -------------------------------------------------------------------


def test_another_publishers_ad_unit_is_answered_and_not_recorded(
    player: Player, callback: Callback, settings: Settings, caplog: pytest.LogCaptureFixture
) -> None:
    settings.ADS_ALLOWED_AD_UNITS = ("1111111111",)
    caplog.set_level(logging.INFO, logger="apps.ads")
    response = callback(user_id=str(player.pk), ad_unit="9999999999")
    assert (response.status_code, response.json()) == (200, {})
    assert not AdReward.objects.exists()
    assert not LedgerEntry.objects.exists()
    assert [getattr(r, "outcome", None) for r in caplog.records if r.msg == "ad_ssv_callback"] == [
        "foreign_ad_unit"
    ]
    assert callback(user_id=str(player.pk), ad_unit="1111111111").status_code == 200
    assert AdReward.objects.get().outcome == "granted"


def test_an_empty_allow_list_grants_nothing_outside_dev_and_test(
    player: Player, callback: Callback, settings: Settings
) -> None:
    settings.ADS_ALLOWED_AD_UNITS = ()
    settings.WASSAL_ENV = "staging"
    assert callback(user_id=str(player.pk)).status_code == 200
    assert not AdReward.objects.exists()


def test_a_repeated_parameter_is_refused(
    player: Player, admob_keys: AdmobKeys, client: Client, settings: Settings
) -> None:
    settings.ADS_ALLOWED_AD_UNITS = ("1234567890",)
    query, _ = signed_query(user_id=str(player.pk), raw={"ad_unit": "1234567890&ad_unit=999"})
    response = client.get(f"{SSV}?{query}")
    assert response.status_code == 403
    assert not AdReward.objects.exists()


# -- M1: nothing signed makes the database fail ----------------------------------------------------


@pytest.mark.parametrize("field", ["ad_unit", "reward_item", "ad_network"])
def test_a_nul_is_malformed_not_a_500(player: Player, callback: Callback, field: str) -> None:
    response = callback(user_id=str(player.pk), raw={field: "a%00b"})
    assert response.status_code == 200
    row = AdReward.objects.get()
    assert row.outcome == "malformed"
    assert getattr(row, field) == "ab"


def test_a_lone_surrogates_bytes_arrive_as_a_replacement_character(
    player: Player, callback: Callback
) -> None:
    response = callback(user_id=str(player.pk), raw={"reward_item": "a%ED%A0%80b"})
    assert response.status_code == 200
    assert "�" in AdReward.objects.get().reward_item


@pytest.mark.parametrize("placement", ["\u0000", "\ud800"])
def test_an_unstorable_placement_is_malformed(
    player: Player, callback: Callback, placement: str
) -> None:
    data = json.dumps({"placement": placement, "nonce": "0b5e2f8e-6b7e-4d0b-a3c4-3c1c3f9b6a11"})
    response = callback(user_id=str(player.pk), raw={"custom_data": quote(data, safe="")})
    assert response.status_code == 200
    assert AdReward.objects.get().outcome == "malformed"


def test_an_unstorable_transaction_id_is_not_recorded(player: Player, callback: Callback) -> None:
    assert callback(user_id=str(player.pk), raw={"transaction_id": "t%00x"}).status_code == 200
    assert not AdReward.objects.exists()


# -- L5: a callback dated far ahead isn't Google's -------------------------------------------------


def test_a_timestamp_over_a_day_ahead_is_malformed(player: Player, callback: Callback) -> None:
    callback(user_id=str(player.pk), timestamp=str(int(time.time() * 1000) + 2 * DAY_MS))
    assert AdReward.objects.get().outcome == "malformed"


# -- L1: one bad key doesn't take the list down ----------------------------------------------------


def test_a_bad_entry_beside_a_good_key_is_skipped(admob_keys: AdmobKeys) -> None:
    good = dev_signing.key_entry(admob_keys.key, admob_keys.key_id)
    admob_keys.body = json.dumps(
        {"keys": [{"keyId": 1, "pem": "not a key"}, {"keyId": "x", "pem": ""}, {"nope": 1}, good]}
    ).encode()
    assert keys.public_key(admob_keys.key_id) is not None


# -- L3, L4: refusals are logged with their reason; only forged ones count for the alert -----------


def test_refusals_are_logged_and_only_forgeries_counted(
    admob_keys: AdmobKeys,
    client: Client,
    caplog: pytest.LogCaptureFixture,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    counted: list[int] = []
    monkeypatch.setattr(alerts, "signature_refused", lambda: counted.append(1))
    caplog.set_level(logging.INFO, logger="apps.ads")
    forged = signed_query()[0].replace("reward_item=piggy", "reward_item=pigge", 1)
    client.get(SSV)  # a scanner's bare GET
    client.get(f"{SSV}?{forged}")
    reasons: list[Any] = [
        getattr(r, "reason", None) for r in caplog.records if r.msg == "ad_ssv_refused"
    ]
    assert reasons == ["unsigned", "signature"]
    assert counted == [1]


# -- the branches the other tests reach only by chance -------------------------------------------


def test_an_oversized_key_list_is_unavailable(admob_keys: AdmobKeys) -> None:
    admob_keys.body = b'{"keys": [], "pad": "' + b"x" * (keys.MAX_KEY_LIST_BYTES + 1) + b'"}'
    with pytest.raises(keys.KeysUnavailable):
        keys.public_key(admob_keys.key_id)


def test_a_signature_that_is_not_base64_is_refused(admob_keys: AdmobKeys) -> None:
    from apps.ads.services import ssv

    query, _ = signed_query()
    message = query[: query.rfind("&signature=")]
    with pytest.raises(ssv.SignatureInvalid, match="encoding"):
        ssv.verify(f"{message}&signature=A&key_id=1")


def test_a_timestamp_past_the_calendar_is_malformed(player: Player, callback: Callback) -> None:
    callback(user_id=str(player.pk), timestamp="9" * 19)
    assert (AdReward.objects.get().outcome, AdReward.objects.get().callback_at) == (
        "malformed",
        None,
    )


def test_losing_a_race_on_the_transaction_answers_a_duplicate(
    player: Player, admob_keys: AdmobKeys, monkeypatch: pytest.MonkeyPatch
) -> None:
    from django.db import IntegrityError

    from apps.ads.services import ssv

    query, _ = signed_query(user_id=str(player.pk), transaction_id="raced")
    ssv.process(query)  # the other delivery, which won

    def lost(*args: object) -> str:
        raise IntegrityError("ad_reward_transaction_once")

    monkeypatch.setattr(ssv, "_record", lost)
    assert ssv.process(query) == ssv.DUPLICATE


def test_losing_a_race_on_the_reference_decides_again(
    player: Player, admob_keys: AdmobKeys, monkeypatch: pytest.MonkeyPatch
) -> None:
    from django.db import IntegrityError

    from apps.ads.services import ssv

    record = ssv._record
    calls: list[int] = []

    def once(*args: Any) -> str:
        calls.append(1)
        if len(calls) == 1:
            raise IntegrityError("ad_reward_nonce_once")
        return record(*args)

    monkeypatch.setattr(ssv, "_record", once)
    assert ssv.process(signed_query(user_id=str(player.pk))[0]) == "granted"
    assert len(calls) == 2
