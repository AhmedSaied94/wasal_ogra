"""Every documented operation, called on a live server, conforms to the committed contract
(constitution XIII, contracts/api.md "Contract tests").

Player endpoints get a real token: the test signs a fresh install id in through
`POST /v1/auth/anonymous` on the live server (B02 research R15), so their checks run past the 401.
B03 adds its three endpoints, each documented error answer, and one case per operation reason of
`POST /v1/sync` (contracts/operations.md "Reasons"), each validated against the contract.
"""

import uuid
from collections.abc import Callable
from datetime import timedelta
from pathlib import Path
from typing import Any

import pytest
import requests
import schemathesis
from django.utils import timezone
from pytest_django import Settings
from pytest_django.live_server_helper import LiveServer
from schemathesis.specs.openapi.checks import positive_data_acceptance

from apps.accounts.models import Player

# Google's key set, served locally, so a link never reaches the network (B02 conftest).
from apps.accounts.tests.conftest import google_jwks, google_key
from apps.content.models import PackRulesIndex

# The sample pack, published through B04's real path (B03 conftest).
from apps.economy.tests.conftest import (
    author,
    channel,
    packs_dir,
    published_packs,
    publisher,
    sample_imported,
    sample_reviewed,
)
from apps.economy.tests.helpers import (
    batch,
    give,
    grant,
    op,
    result_of,
    spend,
    trip_result,
    trip_start,
    txn_of,
    uuid7_at,
)

__all__ = [
    "author",
    "channel",
    "google_jwks",
    "google_key",
    "packs_dir",
    "published_packs",
    "publisher",
    "sample_imported",
    "sample_reviewed",
]

CONTRACT = Path(__file__).resolve().parents[2] / "contracts" / "openapi.yaml"
PLAYER_PATHS = ("/v1/auth/link", "/v1/bootstrap", "/v1/state", "/v1/sync")
CLIENT_HEADERS = {"X-Client-Version": "1.0.0", "X-Platform": "android"}
# No schema can describe a valid Google ID token, so a schema-valid random one is a 422, as it
# should be: that one check doesn't apply to the link (every other check does).
OPAQUE_CREDENTIALS = ("/v1/auth/link",)

schema = schemathesis.openapi.from_path(CONTRACT)


def player_token(base_url: str) -> str:
    """A new player per case, signed in on the live server: the database is emptied between
    cases, so no token outlives its test. (Not a schemathesis auth provider: those run when the
    coverage cases are collected, before there is a server to sign in on.)"""
    return signed_in(base_url)[1]


def signed_in(base_url: str) -> tuple[Player, str]:
    """A new player on the live server, and its access token."""
    response = requests.post(
        f"{base_url}/v1/auth/anonymous",
        json={"install_id": str(uuid.uuid4()), "platform": "android", "locale": "ar-EG"},
        headers=CLIENT_HEADERS,
        timeout=10,
    )
    response.raise_for_status()
    body = response.json()
    return Player.objects.get(pk=body["player_id"]), body["access"]


def align_platform(case: schemathesis.Case[Any]) -> None:
    """`POST /v1/auth/anonymous` needs the body's `platform` to equal `X-Platform`, which the
    schema can't say (B02 contracts/api.md). Generated cases get the two in step."""
    body, headers = case.body, case.headers
    if (
        case.path == "/v1/auth/anonymous"
        and isinstance(body, dict)
        and headers
        and "X-Platform" in headers
        and body.get("platform") in ("android", "ios")
    ):
        headers["X-Platform"] = body["platform"]


@pytest.mark.usefixtures("no_throttle", "google_jwks")
@schema.parametrize()
def test_operation_conforms(case: schemathesis.Case[Any], live_server: LiveServer) -> None:
    if case.path in PLAYER_PATHS:
        case.headers["Authorization"] = f"Bearer {player_token(live_server.url)}"
    align_platform(case)
    excluded = [positive_data_acceptance] if case.path in OPAQUE_CREDENTIALS else []
    response = case.call_and_validate(base_url=live_server.url, excluded_checks=excluded)
    # The coverage phase also sends cases with the token removed on purpose; those must be 401.
    if case.path in PLAYER_PATHS and "Authorization" in response.request.headers:
        assert response.status_code != 401, "the player token wasn't accepted"
    # schemathesis keeps headers with lowercase keys and list values.
    assert response.headers["content-type"] == ["application/json"]


# -- B03: the documented error answers -------------------------------------------------------------


def call(live_server: LiveServer, method: str, path: str, token: str | None, **kwargs: Any) -> Any:
    headers = {**CLIENT_HEADERS, **kwargs.pop("headers", {})}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    response = requests.request(
        method, f"{live_server.url}{path}", headers=headers, timeout=10, **kwargs
    )
    schema[path][method].validate_response(response)
    return response


def code_of(response: Any) -> str:
    code: str = response.json()["error"]["code"]
    return code


@pytest.mark.usefixtures("no_throttle")
def test_the_sync_errors_conform(live_server: LiveServer) -> None:
    player, token = signed_in(live_server.url)
    sync = "/v1/sync"
    assert code_of(call(live_server, "POST", sync, token, json={"ops": []})) == "validation_error"
    many = batch(*(op("tutorial_gift", {}) for _ in range(101)))
    too_many = call(live_server, "POST", sync, token, json=many)
    assert (too_many.status_code, code_of(too_many)) == (400, "batch_too_large")
    big = call(
        live_server,
        "POST",
        sync,
        token,
        data=b"{" + b" " * 262_200 + b"}",
        headers={"Content-Type": "application/json"},
    )
    assert big.status_code == 413
    text = call(
        live_server, "POST", sync, token, data="ops", headers={"Content-Type": "text/plain"}
    )
    assert text.status_code == 415
    assert call(live_server, "POST", sync, None, json=batch()).status_code == 401
    Player.objects.filter(pk=player.pk).update(status="deleted")
    assert code_of(call(live_server, "POST", sync, token, json=batch())) == "account_deleted"


@pytest.mark.parametrize("path", ["/v1/bootstrap", "/v1/state"])
@pytest.mark.usefixtures("no_throttle")
def test_the_read_errors_conform(live_server: LiveServer, path: str) -> None:
    player, token = signed_in(live_server.url)
    assert call(live_server, "GET", path, token).status_code == 200
    assert call(live_server, "GET", path, None).status_code == 401
    Player.objects.filter(pk=player.pk).update(status="deleted")
    assert code_of(call(live_server, "GET", path, token)) == "account_deleted"


@pytest.mark.parametrize(
    ("method", "path", "body"), [("GET", "/v1/bootstrap", None), ("POST", "/v1/sync", batch())]
)
def test_too_many_requests_conform(
    live_server: LiveServer, settings: Settings, method: str, path: str, body: Any
) -> None:
    settings.THROTTLE_PLAYER_RATE = "2/min"
    settings.THROTTLE_SYNC_RATE = "2/min"
    _, token = signed_in(live_server.url)
    answers = [call(live_server, method, path, token, json=body).status_code for _ in range(3)]
    assert answers == [200, 200, 429]


# -- B03: one case per operation reason ------------------------------------------------------------

Scenario = Callable[[Player, int, Callable[[int], list[int]]], list[dict[str, Any]]]


def _started(*results: dict[str, Any]) -> Scenario:
    """A start of line_hay.01, then results of it with `results`' overrides, in order."""

    def scenario(
        player: Player, v: int, publish: Callable[[int], list[int]]
    ) -> list[dict[str, Any]]:
        start = trip_start("line_hay.01", v)
        return [start, *(trip_result(start, "line_hay.01", **r) for r in results)]

    return scenario


def _unsupported(
    player: Player, v: int, publish: Callable[[int], list[int]]
) -> list[dict[str, Any]]:
    publish(1)
    PackRulesIndex.objects.filter(version=v).delete()
    return [trip_start("line_hay.01", v)]


def _ad_after_start(*placements: str) -> Scenario:
    def scenario(
        player: Player, v: int, publish: Callable[[int], list[int]]
    ) -> list[dict[str, Any]]:
        start = trip_start("line_hay.01", v)
        ads = [op("ad_reward", {"ad_placement": p, "ref": txn_of(start)}) for p in placements]
        return [start, *ads]

    return scenario


def _doubled_twice(
    player: Player, v: int, publish: Callable[[int], list[int]]
) -> list[dict[str, Any]]:
    start = trip_start("line_hay.01", v)
    double = {"ad_placement": "result_double", "ref": txn_of(start)}
    return [
        start,
        trip_result(start, "line_hay.01"),
        op("ad_reward", double),
        op("ad_reward", double),
    ]


def _mismatched(
    player: Player, v: int, publish: Callable[[int], list[int]]
) -> list[dict[str, Any]]:
    start = trip_start("line_hay.01", v)
    result = {**result_of("line_hay.01"), "trip_id": "line_hay.02"}
    return [start, op("trip_result", {"trip_start_txn": txn_of(start), "result": result})]


def _not_doublable(
    player: Player, v: int, publish: Callable[[int], list[int]]
) -> list[dict[str, Any]]:
    start = trip_start("line_hay.01", v)
    failed = trip_result(start, "line_hay.01", outcome="failed", stars=0, earnings_jenehat=0)
    return [start, failed, op("ad_reward", {"ad_placement": "result_double", "ref": txn_of(start)})]


def _funded(currency: str, amount: int, envelope: Callable[[int], dict[str, Any]]) -> Scenario:
    def scenario(
        player: Player, v: int, publish: Callable[[int], list[int]]
    ) -> list[dict[str, Any]]:
        grant(player, currency, amount)
        return [envelope(v)]

    return scenario


def _owned_vehicle(
    player: Player, v: int, publish: Callable[[int], list[int]]
) -> list[dict[str, Any]]:
    grant(player, "JENEHAT", 2_000)
    give(player, ("vehicle", "micro_old"))
    return [spend("vehicle", "micro_old", 1500, v)]


def _result_twice(
    player: Player, v: int, publish: Callable[[int], list[int]]
) -> list[dict[str, Any]]:
    start = trip_start("line_hay.01", v)
    return [start, trip_result(start, "line_hay.01"), trip_result(start, "line_hay.01")]


def _rejected_then_dependent(
    player: Player, v: int, publish: Callable[[int], list[int]]
) -> list[dict[str, Any]]:
    start = trip_start("line_none.01", v)
    return [start, trip_result(start, "line_none.01")]


def _random_ref(envelope: Callable[[str], dict[str, Any]]) -> Scenario:
    def scenario(
        player: Player, v: int, publish: Callable[[int], list[int]]
    ) -> list[dict[str, Any]]:
        return [envelope(str(uuid7_at(timezone.now())))]

    return scenario


def _single(envelope: Callable[[int], dict[str, Any]]) -> Scenario:
    def scenario(
        player: Player, v: int, publish: Callable[[int], list[int]]
    ) -> list[dict[str, Any]]:
        return [envelope(v)]

    return scenario


START = {"trip_id": "line_hay.01", "fuel_mode": "fuel"}
SCENARIOS: dict[str, Scenario] = {
    "validation_error": _single(
        lambda v: op("trip_start", {**START, "trip_id": 7, "content_version": v})
    ),
    "unknown_op_type": _single(lambda v: op("fly", {})),
    "op_expired": _single(
        lambda v: op(
            "trip_start",
            {**START, "content_version": v},
            txn=uuid7_at(timezone.now() - timedelta(days=181)),
        )
    ),
    "unknown_content_version": _single(lambda v: trip_start("line_hay.01", v + 99)),
    "content_version_unsupported": _unsupported,
    "dependency_rejected": _rejected_then_dependent,
    "unknown_trip": _single(lambda v: trip_start("line_none.01", v)),
    "unknown_sku": _single(lambda v: spend("booster", "rocket", 10, v)),
    "unknown_variant": _funded(
        "JENEHAT", 1_000, lambda v: spend("item", "salon.nish", 400, v, variant="gold")
    ),
    "not_for_sale": _single(lambda v: spend("vehicle", "tuktuk", 0, v)),  # the starter
    "price_mismatch": _funded("BONAT", 100, lambda v: spend("booster", "change_bag", 11, v)),
    "not_unlocked": _single(lambda v: trip_start("line_hay.02", v)),  # .01 has no star
    "already_owned": _owned_vehicle,
    "already_revived": _ad_after_start("trip_revive", "trip_revive"),
    "already_doubled": _doubled_twice,
    "already_granted": lambda p, v, publish: [op("tutorial_gift", {}), op("tutorial_gift", {})],
    "result_exists": _result_twice,
    "insufficient_funds": _single(lambda v: spend("booster", "change_bag", 10, v)),
    "tank_full": _single(lambda v: op("ad_reward", {"ad_placement": "fuel_refill"})),
    "none_left": lambda p, v, publish: [
        start := trip_start("line_hay.01", v),
        op("use_booster", {"booster_id": "wake_all", "ref": txn_of(start)}),
    ],
    "no_trip": _random_ref(lambda ref: op("use_booster", {"booster_id": "wake_all", "ref": ref})),
    "no_trip_start": _random_ref(
        lambda ref: op("trip_result", {"trip_start_txn": ref, "result": result_of("line_hay.01")})
    ),
    "no_result": _random_ref(
        lambda ref: op("ad_reward", {"ad_placement": "result_double", "ref": ref})
    ),
    "not_doublable": _not_doublable,
    "trip_mismatch": _mismatched,
    "stars_out_of_bounds": _started({"stars": 4}),
    "earnings_out_of_bounds": _started({"earnings_jenehat": 100_000}),
    "duration_out_of_bounds": _started({"duration_ms": 1}),
    "cap_reached": lambda p, v, publish: [trip_start("line_hay.01", v) for _ in range(8)],
    "not_eligible": _single(lambda v: op("comeback_gift", {})),
    "server_only": _single(lambda v: op("ad_reward", {"ad_placement": "morning_piggy"})),
}


def test_every_reason_has_a_case() -> None:
    from apps.economy.services.sync import REASONS

    assert sorted(SCENARIOS) == sorted(REASONS)


@pytest.mark.parametrize("reason", sorted(SCENARIOS))
@pytest.mark.usefixtures("no_throttle")
def test_each_reason_conforms(
    live_server: LiveServer, published_packs: Callable[[int], list[int]], reason: str
) -> None:
    [version] = published_packs(1)
    player, token = signed_in(live_server.url)
    envelopes = SCENARIOS[reason](player, version, published_packs)
    response = call(live_server, "POST", "/v1/sync", token, json=batch(*envelopes))
    assert response.status_code == 200
    last = response.json()["results"][-1]
    assert (last["status"], last.get("reason")) == ("rejected", reason)
