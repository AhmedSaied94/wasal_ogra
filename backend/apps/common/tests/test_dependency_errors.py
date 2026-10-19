"""A database or cache outage during a request is a 503 (spec edge case "Database or cache
unreachable")."""

import json

import pytest
from django.test import Client

pytestmark = pytest.mark.urls("apps.common.tests.urls")


@pytest.mark.parametrize(
    "path", ["/test/db-down", "/test/db-closed", "/test/cache-down", "/test/cache-timeout"]
)
def test_dependency_failure_is_503_without_internals(client: Client, path: str) -> None:
    response = client.get(path)
    assert response.status_code == 503
    assert response["Content-Type"] == "application/json"
    error = json.loads(response.content)["error"]
    assert error["code"] == "dependency_unavailable"
    assert error["details"] == {}
    text = response.content.decode()
    for leak in ("internal", "5432", "6379", "connect", "Timeout", "Error"):
        assert leak not in text
