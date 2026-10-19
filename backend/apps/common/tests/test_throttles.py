"""The shared per-address limit (FR-015, research R4)."""

import json
from typing import Any

import pytest
from django.conf import settings as django_settings
from django.test import Client, override_settings
from pytest_django import Settings


@pytest.fixture(autouse=True)
def _low_rate(settings: Settings) -> None:
    settings.THROTTLE_ADDRESS_RATE = "3/min"


@pytest.fixture
def behind_proxy(settings: Settings) -> None:
    settings.REST_FRAMEWORK = {**settings.REST_FRAMEWORK, "NUM_PROXIES": 1}


def get(address: str = "203.0.113.7", path: str = "/healthz", **headers: str) -> int:
    return Client(REMOTE_ADDR=address).get(path, headers=headers).status_code


def test_separate_clients_share_one_limit() -> None:
    assert [get(), get(), get(), get()] == [200, 200, 200, 429]


def test_other_address_is_not_limited() -> None:
    for _ in range(4):
        get("203.0.113.7")
    assert get("203.0.113.8") == 200


def test_limited_response_has_retry_after() -> None:
    client = Client(REMOTE_ADDR="203.0.113.9")
    for _ in range(3):
        client.get("/healthz")
    response = client.get("/healthz")
    assert response.status_code == 429
    error: dict[str, Any] = json.loads(response.content)["error"]
    assert error["code"] == "rate_limited"
    retry_after = error["details"]["retry_after_s"]
    assert isinstance(retry_after, int)
    assert retry_after > 0
    assert response["Retry-After"] == str(retry_after)


@pytest.mark.usefixtures("behind_proxy")
def test_address_is_the_last_forwarded_entry() -> None:
    statuses = [
        get("127.0.0.1", x_forwarded_for="198.51.100.1, 192.0.2.10"),
        get("127.0.0.1", x_forwarded_for="198.51.100.2, 192.0.2.10"),
        get("127.0.0.1", x_forwarded_for="192.0.2.10"),
        get("127.0.0.1", x_forwarded_for="198.51.100.3, 192.0.2.10"),
    ]
    assert statuses == [200, 200, 200, 429]
    assert get("127.0.0.1", x_forwarded_for="192.0.2.10, 192.0.2.11") == 200


@pytest.mark.usefixtures("behind_proxy")
def test_requests_without_forwarded_for_are_not_counted_behind_proxy() -> None:
    assert [get("127.0.0.1") for _ in range(10)] == [200] * 10
    # They used none of 127.0.0.1's budget either.
    statuses = [get("127.0.0.1", x_forwarded_for="127.0.0.1") for _ in range(4)]
    assert statuses == [200, 200, 200, 429]


def test_every_request_counted_without_proxy() -> None:
    assert [get("127.0.0.1") for _ in range(4)] == [200, 200, 200, 429]


@pytest.mark.urls("apps.common.tests.urls")
@pytest.mark.usefixtures("behind_proxy")
def test_only_health_paths_are_exempt_behind_proxy() -> None:
    """Without the header only the host's health checks are let through uncounted."""
    assert [get("127.0.0.1", path="/test/open") for _ in range(4)] == [200, 200, 200, 429]


@pytest.mark.urls("apps.common.tests.urls")
@pytest.mark.usefixtures("behind_proxy")
def test_cache_outage_does_not_block_requests() -> None:
    """The limit fails open: with the cache down, /healthz must still answer (contracts/api.md)."""
    dead = {**django_settings.CACHES["default"], "LOCATION": "redis://127.0.0.1:1/0"}
    with override_settings(CACHES={**django_settings.CACHES, "default": dead}):
        assert get("127.0.0.1", x_forwarded_for="192.0.2.20") == 200
        assert get("127.0.0.1", path="/test/open", x_forwarded_for="192.0.2.20") == 200
