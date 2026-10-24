"""The client headers every player endpoint requires (B02 research R10, FR-034)."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

import pytest
from django.test import Client

from apps.common.client import parse_client_version, parse_platform

if TYPE_CHECKING:
    from django.test.client import _MonkeyPatchedWSGIResponse as TestResponse

pytestmark = pytest.mark.urls("apps.common.tests.urls")

HEADERS = {"x-client-version": "1.4.0+57", "x-platform": "android"}


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("1.0.0", (1, 0, 0)), ("1.0.0+2", (1, 0, 0)), ("10.20.30+57", (10, 20, 30))],
)
def test_client_version_accepted(raw: str, expected: tuple[int, int, int]) -> None:
    assert parse_client_version(raw) == expected


@pytest.mark.parametrize("raw", [None, "", "1.0", "1.0.0-beta", "v1.0.0", "1.0.0+", "1" * 65])
def test_client_version_refused(raw: str | None) -> None:
    assert parse_client_version(raw) is None


@pytest.mark.parametrize("raw", ["android", "ios"])
def test_platform_accepted(raw: str) -> None:
    assert parse_platform(raw) == raw


@pytest.mark.parametrize("raw", [None, "", "Android", "web", "ios "])
def test_platform_refused(raw: str | None) -> None:
    assert parse_platform(raw) is None


def fields_of(response: TestResponse) -> dict[str, list[str]]:
    assert response.status_code == 400
    error = json.loads(response.content)["error"]
    assert error["code"] == "validation_error"
    fields: dict[str, list[str]] = error["details"]["fields"]
    return fields


def test_both_headers_let_the_request_through(client: Client) -> None:
    assert client.get("/test/client-headers", headers=HEADERS).status_code == 200


@pytest.mark.parametrize(
    ("headers", "field"),
    [
        ({"x-platform": "android"}, "X-Client-Version"),
        ({**HEADERS, "x-client-version": "1.0"}, "X-Client-Version"),
        # Longer than the player's `client_version` column (B02 data-model.md).
        ({**HEADERS, "x-client-version": "1.0.0+" + "a" * 27}, "X-Client-Version"),
        ({"x-client-version": "1.0.0"}, "X-Platform"),
        ({**HEADERS, "x-platform": "web"}, "X-Platform"),
    ],
)
def test_missing_or_malformed_header_is_named(
    client: Client, headers: dict[str, str], field: str
) -> None:
    fields = fields_of(client.get("/test/client-headers", headers=headers))
    assert list(fields) == [field]


def test_both_missing_are_both_named_without_echoing(client: Client) -> None:
    response = client.get("/test/client-headers", headers={"x-platform": "<script>"})
    assert set(fields_of(response)) == {"X-Client-Version", "X-Platform"}
    assert "<script>" not in response.content.decode()


@pytest.mark.django_db
def test_manifest_needs_neither_header(client: Client) -> None:
    """B04's contract is unchanged: the manifest stays public (FR-035)."""
    assert client.get("/v1/content/manifest").status_code == 200
