"""`ad_reward_seen` (B07 FR-017a, research R7, contracts/api.md "POST /v1/sync")."""

from __future__ import annotations

import uuid

import pytest

from apps.accounts.models import Player
from apps.ads.models import AdReward
from apps.ads.tests.helpers import reward_row
from apps.economy.tests.helpers import Api, batch, op, reasons, run, signed_in_api

pytestmark = pytest.mark.django_db


def seen(nonce: object) -> dict[str, object]:
    return op("ad_reward_seen", {"nonce": str(nonce)})


def shown_at(row: AdReward) -> object:
    return AdReward.objects.get(pk=row.pk).shown_at


def test_the_players_unseen_reward_is_marked(api: Api) -> None:
    row = reward_row(api.player)
    assert api.bootstrap().json()["ads"]["morning_piggy"]["unseen"] != []
    version = api.bootstrap().json()["state_version"]
    response = api.sync(batch(seen(row.nonce), base=version))
    body = response.json()
    assert [r["status"] for r in body["results"]] == ["accepted"]
    assert "granted" not in body["results"][0]
    assert body["state_version"] == version
    assert shown_at(row) is not None
    assert api.bootstrap().json()["ads"]["morning_piggy"]["unseen"] == []


def test_marking_again_changes_nothing(player: Player) -> None:
    row = reward_row(player)
    run(player, seen(row.nonce))
    first = shown_at(row)
    result = run(player, seen(row.nonce))
    assert reasons(result) == ["accepted"]
    assert shown_at(row) == first


def test_a_replay_returns_the_stored_result(player: Player) -> None:
    row = reward_row(player)
    envelope = seen(row.nonce)
    assert reasons(run(player, envelope)) == ["accepted"]
    assert reasons(run(player, envelope)) == ["accepted"]


def test_any_other_reference_is_accepted_and_changes_nothing(player: Player) -> None:
    other = signed_in_api().player
    theirs = reward_row(other)
    refused = reward_row(player, "cap_reached")
    result = run(player, seen(theirs.nonce), seen(refused.nonce), seen(uuid.uuid4()))
    assert reasons(result) == ["accepted"] * 3
    assert shown_at(theirs) is None
    assert shown_at(refused) is None


@pytest.mark.parametrize("payload", [{}, {"nonce": "nope"}, {"nonce": 7}, {"nonce": None}])
def test_a_bad_nonce_is_a_validation_error(player: Player, payload: dict[str, object]) -> None:
    assert reasons(run(player, op("ad_reward_seen", payload))) == ["validation_error"]
