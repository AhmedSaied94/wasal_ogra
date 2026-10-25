"""Every documented operation, called on a live server, conforms to the committed contract
(constitution XIII, contracts/api.md "Contract tests").

Player endpoints get a real token: the test signs a fresh install id in through
`POST /v1/auth/anonymous` on the live server (B02 research R15), so their checks run past the 401.
"""

import uuid
from pathlib import Path
from typing import Any

import pytest
import requests
import schemathesis
from pytest_django.live_server_helper import LiveServer
from schemathesis.specs.openapi.checks import positive_data_acceptance

# Google's key set, served locally, so a link never reaches the network (B02 conftest).
from apps.accounts.tests.conftest import google_jwks, google_key

__all__ = ["google_jwks", "google_key"]

CONTRACT = Path(__file__).resolve().parents[2] / "contracts" / "openapi.yaml"
PLAYER_PATHS = ("/v1/auth/link",)
# No schema can describe a valid Google ID token, so a schema-valid random one is a 422, as it
# should be: that one check doesn't apply to the link (every other check does).
OPAQUE_CREDENTIALS = ("/v1/auth/link",)

schema = schemathesis.openapi.from_path(CONTRACT)


def player_token(base_url: str) -> str:
    """A new player per case, signed in on the live server: the database is emptied between
    cases, so no token outlives its test. (Not a schemathesis auth provider: those run when the
    coverage cases are collected, before there is a server to sign in on.)"""
    response = requests.post(
        f"{base_url}/v1/auth/anonymous",
        json={"install_id": str(uuid.uuid4()), "platform": "android", "locale": "ar-EG"},
        headers={"X-Client-Version": "1.0.0", "X-Platform": "android"},
        timeout=10,
    )
    response.raise_for_status()
    access: str = response.json()["access"]
    return access


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
