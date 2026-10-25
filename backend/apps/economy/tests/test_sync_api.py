"""`POST /v1/sync` (B03 tasks.md T034, contracts/api.md "POST /v1/sync", spec US1 scenarios 1
to 8)."""

from __future__ import annotations

import json
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
import time_machine
from django.test import Client
from pytest_django import Settings

from apps.accounts.models import Player
from apps.accounts.tests.factories import access_for, bearer, make_player
from apps.economy.models import ProcessedOp, Wallet
from apps.economy.tests.helpers import (
    HEADERS,
    SYNC,
    Api,
    batch,
    op,
    trip_result,
    trip_start,
    txn_of,
)

pytestmark = pytest.mark.django_db

WALLET_KEYS = {"jenehat", "bonat", "fuel", "fuel_max", "fuel_updated_at", "fuel_unlimited_until"}


def error_of(response: Any, status: int) -> dict[str, Any]:
    assert response.status_code == status, response.content
    error: dict[str, Any] = json.loads(response.content)["error"]
    return error


def test_the_answer_has_the_contract_shape(api: Api, published_pack: int) -> None:
    start = trip_start("line_hay.01", published_pack)
    refused = trip_start("line_hay.99", published_pack)
    response = api.sync(batch(start, trip_result(start, "line_hay.01"), refused))
    assert response.status_code == 200, response.content
    body = response.json()
    assert set(body) == {"state_version", "state_stale", "results", "wallet"}
    assert (body["state_version"], body["state_stale"]) == (1, False)
    assert body["results"] == [
        {"client_txn_id": txn_of(start), "status": "accepted"},
        {"client_txn_id": body["results"][1]["client_txn_id"], "status": "accepted"},
        {"client_txn_id": txn_of(refused), "status": "rejected", "reason": "unknown_trip"},
    ]
    assert set(body["wallet"]) == WALLET_KEYS
    assert body["wallet"]["jenehat"] == 10
    assert body["wallet"]["fuel"] == 4
    assert body["wallet"]["fuel_max"] == 5
    assert body["wallet"]["fuel_unlimited_until"] is None
    assert body["wallet"]["fuel_updated_at"].endswith("Z")
    assert "X-Request-ID" in response


def test_a_validation_error_names_the_field(api: Api) -> None:
    response = api.sync(batch(op("trip_start", {"trip_id": "x", "content_version": 1.5})))
    [entry] = response.json()["results"]
    assert entry["reason"] == "validation_error"
    assert entry["details"] == {"field": "content_version"}


def test_an_empty_batch_answers_the_current_wallet(api: Api, settings: Settings) -> None:
    response = api.sync(batch())
    assert response.status_code == 200
    body = response.json()
    assert body == {
        "state_version": 0,
        "state_stale": False,
        "results": [],
        "wallet": body["wallet"],
    }
    assert body["wallet"]["fuel"] == settings.ECONOMY_FUEL_MAX
    assert (body["wallet"]["jenehat"], body["wallet"]["bonat"]) == (0, 0)
    assert Wallet.objects.filter(player_id=api.player_id).exists()


def test_a_stale_base_is_reported(api: Api) -> None:
    assert api.sync(batch(base=7)).json()["state_stale"] is True


def test_100_operations_are_one_batch_and_101_are_too_many(api: Api) -> None:
    hundred = [op("no_such_op", {}) for _ in range(100)]
    response = api.sync(batch(*hundred))
    assert response.status_code == 200
    assert len(response.json()["results"]) == 100
    error = error_of(api.sync(batch(*hundred, op("no_such_op", {}))), 400)
    assert error == {
        "code": "batch_too_large",
        "message": "Batch too large",
        "details": {"max": 100},
    }
    assert ProcessedOp.objects.filter(player_id=api.player_id).count() == 100


def test_a_body_over_256_kb_is_too_large(api: Api) -> None:
    big = op("settings_update", {"settings": {"note": "x" * (260 * 1024)}})
    error = error_of(api.sync(batch(big)), 413)
    assert error["code"] == "payload_too_large"
    assert error["details"] == {"limit_bytes": 256 * 1024}
    assert not ProcessedOp.objects.filter(player_id=api.player_id).exists()


def bad(envelope: dict[str, Any], **changes: Any) -> dict[str, Any]:
    changed = {**envelope, **changes}
    return {k: v for k, v in changed.items() if v is not ...}


GOOD = op("no_such_op", {})


@pytest.mark.parametrize(
    ("body", "field"),
    [
        (
            batch(GOOD, GOOD, GOOD, bad(GOOD, client_txn_id=str(uuid.uuid4()))),
            "ops.3.client_txn_id",
        ),
        (batch(bad(GOOD, client_txn_id="not-a-uuid")), "ops.0.client_txn_id"),
        (batch(bad(GOOD, client_txn_id=txn_of(GOOD).upper())), "ops.0.client_txn_id"),
        (batch(bad(GOOD, op_type="")), "ops.0.op_type"),
        (batch(bad(GOOD, op_type=7)), "ops.0.op_type"),
        (batch(bad(GOOD, op_type="x" * 41)), "ops.0.op_type"),
        (batch(bad(GOOD, occurred_at=...)), "ops.0.occurred_at"),
        (batch(bad(GOOD, occurred_at="2026-10-17T09:12:03")), "ops.0.occurred_at"),
        (batch(bad(GOOD, occurred_at="2026-10-17T11:12:03+02:00")), "ops.0.occurred_at"),
        (batch(bad(GOOD, occurred_at="yesterday")), "ops.0.occurred_at"),
        (batch(bad(GOOD, payload=[1])), "ops.0.payload"),
        (batch(bad(GOOD, payload=...)), "ops.0.payload"),
        (batch(bad(GOOD, extra=1)), "ops.0.extra"),
        (batch(bad(GOOD, payload=None)), "ops.0.payload"),
        ({"base_state_version": 1.0, "ops": []}, "base_state_version"),
        ({"base_state_version": True, "ops": []}, "base_state_version"),
        ({"base_state_version": -1, "ops": []}, "base_state_version"),
        ({"base_state_version": "1", "ops": []}, "base_state_version"),
        ({"ops": []}, "base_state_version"),
        ({"base_state_version": 0}, "ops"),
        ({"base_state_version": 0, "ops": {}}, "ops"),
        ({"base_state_version": 0, "ops": [], "extra": 1}, "extra"),
        ({"base_state_version": 0, "ops": [7]}, "ops.0.non_field_errors"),
    ],
)
def test_a_malformed_envelope_refuses_the_whole_batch(
    api: Api, body: dict[str, Any], field: str
) -> None:
    error = error_of(api.sync(body), 400)
    assert error["code"] == "validation_error"
    assert field in error["details"]["fields"], error["details"]
    assert not ProcessedOp.objects.filter(player_id=api.player_id).exists()


def test_a_body_that_is_not_json_is_unsupported(api: Api) -> None:
    response = api.client.post(SYNC, data="a=1", content_type="text/plain", headers=api.headers)
    assert error_of(response, 415)["code"] == "unsupported_media_type"


def test_a_body_that_is_not_an_object_is_a_validation_error(api: Api) -> None:
    assert error_of(api.sync([]), 400)["code"] == "validation_error"  # type: ignore[arg-type]


def post(token: str | None, body: dict[str, Any], **extra: str) -> Any:
    headers = {**HEADERS, **extra}
    if token is not None:
        headers = {**headers, **bearer(token)}
    return Client().post(SYNC, data=body, content_type="application/json", headers=headers)


def test_without_a_token_nothing_is_applied() -> None:
    error = error_of(post(None, batch(GOOD)), 401)
    assert error["code"] == "token_invalid"
    assert not ProcessedOp.objects.exists()


def test_an_expired_token_applies_nothing() -> None:
    now = datetime.now(UTC)
    player = make_player()
    with time_machine.travel(now - timedelta(minutes=16), tick=False):
        token = access_for(player)
    assert error_of(post(token, batch(GOOD)), 401)["code"] == "token_expired"
    assert not ProcessedOp.objects.exists()


@pytest.mark.parametrize("status", ["pending_deletion", "deleted"])
def test_a_deleted_player_applies_nothing(status: str) -> None:
    player = make_player()
    token = access_for(player)
    Player.objects.filter(pk=player.pk).update(status=status)
    assert error_of(post(token, batch(GOOD)), 403)["code"] == "account_deleted"
    assert not ProcessedOp.objects.exists()
    assert not Wallet.objects.exists()


@pytest.mark.parametrize("missing", ["x-client-version", "x-platform"])
def test_a_missing_client_header_is_a_validation_error(missing: str) -> None:
    token = access_for(make_player())
    headers = {k: v for k, v in {**HEADERS, **bearer(token)}.items() if k != missing}
    response = Client().post(
        SYNC, data=batch(GOOD), content_type="application/json", headers=headers
    )
    assert error_of(response, 400)["code"] == "validation_error"
    assert not ProcessedOp.objects.exists()


def test_too_many_batches_a_minute_are_limited(api: Api, settings: Settings) -> None:
    settings.THROTTLE_SYNC_RATE = "2/min"
    assert [api.sync(batch()).status_code for _ in range(2)] == [200, 200]
    response = api.sync(batch(GOOD))
    error = error_of(response, 429)
    assert error["code"] == "rate_limited"
    assert int(response["Retry-After"]) == error["details"]["retry_after_s"] > 0
    assert not ProcessedOp.objects.filter(player_id=api.player_id).exists()


def test_only_post_is_allowed(api: Api) -> None:
    assert error_of(api.client.get(SYNC, headers=api.headers), 405)["code"] == "method_not_allowed"
