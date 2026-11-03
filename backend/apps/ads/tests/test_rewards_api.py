"""`GET /v1/ads/rewards/{nonce}`: the app asks for its reward (B07 US1 AS2-AS3, FR-014-FR-016)."""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone

from apps.ads.models import AdReward
from apps.ads.tests.conftest import Callback
from apps.ads.tests.helpers import reward_row
from apps.economy.services import settings as economy_settings
from apps.economy.services import wallets
from apps.economy.tests.helpers import Api, signed_in_api, wallet_of

pytestmark = pytest.mark.django_db


def lookup(api: Api, nonce: str) -> Any:
    return api.client.get(f"/v1/ads/rewards/{nonce}", headers=api.headers)


def test_a_granted_reward_and_the_wallet(api: Api, callback: Callback) -> None:
    sent = callback(user_id=api.player_id)
    response = lookup(api, sent.nonce)
    assert response.status_code == 200
    body = response.json()
    row = AdReward.objects.get()
    assert body == {
        "status": "granted",
        "jenehat": 30,
        "bonat": 2,
        "granted_at": wallets.iso(row.created_at),
        "wallet": wallets.answer(
            wallet_of(api.player_id), api.player, timezone.now(), economy_settings.current()
        ),
    }


@pytest.mark.parametrize("outcome", ["cap_reached", "not_server_placement", "expired"])
def test_a_refused_reward_says_why(api: Api, outcome: str) -> None:
    row = reward_row(api.player, outcome)
    response = lookup(api, str(row.nonce))
    assert (response.status_code, response.json()) == (
        200,
        {"status": "refused", "reason": outcome},
    )


def test_every_not_yours_is_the_same_404(api: Api) -> None:
    other = signed_in_api()
    theirs = reward_row(other.player)
    nobody = reward_row(None, "unattributed")
    answers = [
        lookup(api, str(uuid.uuid4())),
        lookup(api, str(theirs.nonce)),
        lookup(api, str(nobody.nonce)),
        lookup(api, "not-a-uuid"),
    ]
    assert {(a.status_code, a.content) for a in answers} == {(404, answers[0].content)}
    assert answers[0].json()["error"]["code"] == "not_found"


def test_it_needs_the_player_defaults(api: Api) -> None:
    row = reward_row(api.player)
    response = api.client.get(
        f"/v1/ads/rewards/{row.nonce}", headers=api.headers | {"authorization": ""}
    )
    assert response.status_code == 401


def test_it_writes_nothing(api: Api) -> None:
    api.bootstrap()  # the wallet, as a grant creates it
    row = reward_row(api.player)
    lookup(api, str(row.nonce))  # warm the throttle and the snapshot
    with CaptureQueriesContext(connection) as queries:
        assert lookup(api, str(row.nonce)).status_code == 200
    statements = [q["sql"].lstrip().split()[0].upper() for q in queries.captured_queries]
    assert set(statements) <= {"SELECT"}, statements
