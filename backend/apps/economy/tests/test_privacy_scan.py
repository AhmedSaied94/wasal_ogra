"""FR-044: no payload, balance or display name is logged, and only `Player` stores a name
(B03 tasks.md T086, the scan of B02's `test_privacy_scan.py` extended).

Every operation type goes through the API, accepted or not, carrying values found nowhere else;
the balances are numbers no log line has by chance. Then every log record captured at DEBUG is
searched for each of them, and every text column of every table for the name.
"""

from __future__ import annotations

import logging
from typing import Any

import pytest

from apps.accounts.tests.test_privacy_scan import logged, stored
from apps.economy.models import Currency
from apps.economy.services import sync
from apps.economy.tests.helpers import (
    Api,
    batch,
    give,
    grant,
    op,
    spend,
    trip_result,
    trip_start,
    txn_of,
    wallet_of,
)

pytestmark = pytest.mark.django_db

NAME = "Privacy Driver Qx"
LOG_HASH = "feedfacecafebeef" * 4
UNKNOWN_TRIP = "line_privacy.77"
UNKNOWN_REQUEST = "req_privacy_marker"
JENEHAT = 987_651
BONAT = 4_321


def every_operation(version: int) -> list[dict[str, Any]]:
    start = trip_start("line_hay.01", version)
    return [
        start,
        op("ad_reward", {"ad_placement": "trip_revive", "ref": txn_of(start)}),
        op("use_booster", {"booster_id": "wake_all", "ref": txn_of(start)}),
        trip_result(start, "line_hay.01", command_log_hash=LOG_HASH),
        trip_start(UNKNOWN_TRIP, version),
        spend("item", "salon.nish", 400, version, variant="classic"),
        spend("booster", "wake_all", 8, version),
        op(
            "story_progress",
            {"chapter_id": "ch1_first_job", "scene_id": "the_stand", "content_version": version},
        ),
        op("settings_update", {"display_name": NAME, "settings": {"digits": "western"}}),
        op("tutorial_gift", {}),
        op("comeback_gift", {}),
        op("claim_request", {"request_id": "req_nish_crystal", "content_version": version}),
        op("claim_request", {"request_id": UNKNOWN_REQUEST, "content_version": version}),
    ]


def test_nothing_of_the_economy_is_logged(
    api: Api, published_pack: int, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    assert api.bootstrap().status_code == 200
    grant(api.player, Currency.JENEHAT, JENEHAT)
    grant(api.player, Currency.BONAT, BONAT)
    give(api.player, ("item", "salon.nish"), variant="crystal")
    ops = every_operation(published_pack)
    assert {e["op_type"] for e in ops} == set(sync.registered())
    response = api.sync(batch(*ops))
    assert response.status_code == 200
    assert "accepted" in {r["status"] for r in response.json()["results"]}
    assert api.state().status_code == 200
    wallet = wallet_of(api.player)

    secrets = [NAME, LOG_HASH, UNKNOWN_TRIP, UNKNOWN_REQUEST]
    secrets += [str(n) for n in (JENEHAT, BONAT, wallet.jenehat, wallet.bonat)]
    assert logged(caplog.records, secrets) == []
    assert caplog.records, "nothing was captured, so the log check proves nothing"
    assert stored([NAME]) == [f"accounts_player.display_name: {NAME}"]
