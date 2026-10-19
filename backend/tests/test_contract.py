"""Every documented operation, called on a live server, conforms to the committed contract
(constitution XIII, contracts/api.md "Contract tests")."""

from pathlib import Path
from typing import Any

import pytest
import schemathesis
from pytest_django.live_server_helper import LiveServer

CONTRACT = Path(__file__).resolve().parents[2] / "contracts" / "openapi.yaml"

schema = schemathesis.openapi.from_path(CONTRACT)


@pytest.mark.usefixtures("no_throttle")
@schema.parametrize()
def test_operation_conforms(case: schemathesis.Case[Any], live_server: LiveServer) -> None:
    response = case.call_and_validate(base_url=live_server.url)
    # schemathesis keeps headers with lowercase keys and list values.
    assert response.headers["content-type"] == ["application/json"]
