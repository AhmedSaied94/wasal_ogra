"""Input a tampered phone can send never fails the request, and never stores what it chose
(B03 tasks.md T097, the security review's H1 and M1).

Each case is a single bad operation: it is refused on its own, the rest of the batch applies, and
`ProcessedOp.result` holds only server-chosen words.
"""

from __future__ import annotations

import json
from typing import Any

import pytest

from apps.accounts.models import Player
from apps.economy.models import ProcessedOp
from apps.economy.tests.helpers import (
    Api,
    batch,
    op,
    reasons,
    result_of,
    run,
    trip_start,
    txn_of,
)

pytestmark = pytest.mark.django_db

INT32_MAX = 2**31 - 1
SURROGATE = "\ud800"


def stored(player: Player, envelope: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = ProcessedOp.objects.get(
        player=player, client_txn_id=txn_of(envelope)
    ).result
    return result


def test_an_unknown_payload_key_is_not_echoed_or_stored(player: Player) -> None:
    key = "k" * 10_000
    envelope = op("tutorial_gift", {key: 1})
    result = run(player, envelope)
    assert reasons(result) == ["validation_error"]
    assert result.results[0].outcome.details == {"field": "payload"}
    assert len(json.dumps(stored(player, envelope))) < 100


def ended(version: int, **result: Any) -> tuple[dict[str, Any], dict[str, Any]]:
    start = trip_start("line_hay.01", version)
    payload = {"trip_start_txn": txn_of(start), "result": {**result_of("line_hay.01"), **result}}
    return start, op("trip_result", payload)


@pytest.mark.parametrize(
    ("result", "field"),
    [
        ({"rev": INT32_MAX + 1}, "result.rev"),
        ({"fights": INT32_MAX + 1}, "result.fights"),
        ({"command_log_hash": "ab\x00cd"}, "result.command_log_hash"),
        ({"command_log_hash": f"ab{SURROGATE}"}, "result.command_log_hash"),
        ({"boosters_used": ["wake\x00all"]}, "result.boosters_used"),
        ({"boosters_used": ["x" * 33]}, "result.boosters_used"),
        ({"padding": SURROGATE}, None),  # an ignored key: accepted, hashed without failing
    ],
)
def test_a_result_the_columns_cant_hold_is_refused(
    player: Player, published_pack: int, result: dict[str, Any], field: str | None
) -> None:
    start, end = ended(published_pack, **result)
    outcome = run(player, start, end).results[1].outcome
    if field is None:
        assert outcome.status == "accepted"
    else:
        assert (outcome.reason, outcome.details) == ("validation_error", {"field": field})


@pytest.mark.parametrize("text", ["line\x00hay.01", f"line_hay{SURROGATE}"])
def test_a_payload_string_with_nul_or_a_lone_surrogate_is_refused(
    player: Player, published_pack: int, text: str
) -> None:
    payload = {"trip_id": text, "content_version": published_pack, "fuel_mode": "fuel"}
    envelope = op("trip_start", payload)
    result = run(player, envelope, trip_start("line_hay.01", published_pack))
    assert reasons(result) == ["validation_error", "accepted"]
    assert stored(player, envelope) == {"details": {"field": "trip_id"}}


def raw_sync(api: Api, body: str) -> Any:
    return api.client.post(
        "/v1/sync", data=body, content_type="application/json", headers=api.headers
    )


def test_a_lone_surrogate_through_the_api_is_answered(api: Api, published_pack: int) -> None:
    envelope = op("tutorial_gift", {})
    body = json.dumps(batch(envelope)).replace('"payload": {}', '"payload": {"\\ud800": 1}')
    response = raw_sync(api, body)
    assert response.status_code == 200
    assert response.json()["results"][0]["reason"] == "validation_error"


@pytest.mark.parametrize("op_type", ["trip\x00start", "TripStart", "trip-start", f"a{SURROGATE}"])
def test_an_op_type_outside_the_alphabet_is_a_bad_batch(api: Api, op_type: str) -> None:
    body = batch({**op("tutorial_gift", {}), "op_type": op_type})
    response = raw_sync(api, json.dumps(body))
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "validation_error"
    assert not ProcessedOp.objects.exists()


def test_json_nested_too_deep_is_a_bad_request(api: Api) -> None:
    response = raw_sync(api, "[" * 100_000)
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "validation_error"
