"""The shared per-address limit (FR-015, research R4) and the B02 limits (B02 research R9)."""

import json
import uuid
from typing import Any

import pytest
from django.conf import settings as django_settings
from django.test import Client, override_settings
from pytest_django import Settings

from apps.accounts.models import Player
from apps.accounts.services import players
from apps.accounts.tests.factories import (
    CLIENT,
    HEADERS,
    access_for,
    bearer,
    make_player,
    renew,
    sign_in,
)
from apps.common.throttles import address_bucket


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


# -- Per player (B02 research R9, FR-032) ----------------------------------------------------------

WHOAMI = "/test/whoami"


def as_player(token: str, address: str = "127.0.0.1", forwarded: str = "192.0.2.30") -> int:
    headers = {**bearer(token), "x-forwarded-for": forwarded}
    return Client(REMOTE_ADDR=address).get(WHOAMI, headers=headers).status_code


@pytest.mark.django_db
@pytest.mark.urls("apps.accounts.tests.urls")
@pytest.mark.usefixtures("behind_proxy")
def test_requests_with_a_player_token_skip_the_address_limit() -> None:
    token = access_for(make_player())
    assert [as_player(token) for _ in range(6)] == [200] * 6
    # Unauthenticated requests from the same address are still counted.
    assert [get("127.0.0.1", x_forwarded_for="192.0.2.30") for _ in range(4)] == [
        200,
        200,
        200,
        429,
    ]


@pytest.mark.django_db
@pytest.mark.urls("apps.accounts.tests.urls")
@pytest.mark.usefixtures("behind_proxy")
def test_each_player_behind_one_address_has_its_own_budget(settings: Settings) -> None:
    settings.THROTTLE_PLAYER_RATE = "3/min"
    first, second = access_for(make_player()), access_for(make_player())
    assert [as_player(first) for _ in range(4)] == [200, 200, 200, 429]
    assert as_player(second) == 200


@pytest.mark.django_db
@pytest.mark.urls("apps.accounts.tests.urls")
def test_the_default_player_rate_is_120_a_minute() -> None:
    token = access_for(make_player())
    statuses = [as_player(token, address="203.0.113.70") for _ in range(121)]
    assert statuses[:120] == [200] * 120
    assert statuses[120] == 429


@pytest.mark.django_db
@pytest.mark.urls("apps.accounts.tests.urls")
@pytest.mark.usefixtures("behind_proxy")
def test_the_player_limit_fails_open() -> None:
    token = access_for(make_player())
    dead = {**django_settings.CACHES["default"], "LOCATION": "redis://127.0.0.1:1/0"}
    with override_settings(CACHES={**django_settings.CACHES, "default": dead}):
        assert as_player(token) == 200


@pytest.mark.django_db
def test_account_creation_is_limited_to_60_an_hour_per_address() -> None:
    """US1-6: the 61st creation from one address is refused and creates nothing (research R9)."""
    busy = Client(REMOTE_ADDR="203.0.113.80")
    statuses = [sign_in(busy, uuid.uuid4()).status_code for _ in range(60)]
    assert statuses == [201] * 60

    response = sign_in(busy, uuid.uuid4())
    assert response.status_code == 429
    error: dict[str, Any] = json.loads(response.content)["error"]
    assert error["code"] == "rate_limited"
    assert error["details"]["retry_after_s"] > 0
    assert response["Retry-After"] == str(error["details"]["retry_after_s"])
    assert Player.objects.count() == 60

    assert sign_in(Client(REMOTE_ADDR="203.0.113.81"), uuid.uuid4()).status_code == 201


# -- Renewals: per session, never per address (B02 SC-008, research R9) ---------------------------


@pytest.mark.django_db
@pytest.mark.usefixtures("behind_proxy")
def test_a_thousand_players_behind_one_address_all_renew(settings: Settings) -> None:
    """Carrier NAT: 1,000 players share one public address. Created through the service, since
    the API would stop them at 60 creations an hour from that address."""
    settings.THROTTLE_ADDRESS_RATE = "120/min"  # every limit at its default
    issued = [
        players.create_or_return(uuid.uuid4(), "android", "ar-EG", client=CLIENT)[0]
        for _ in range(1000)
    ]
    client = Client(REMOTE_ADDR="127.0.0.1")
    statuses = [
        renew(
            client, pair.refresh, headers={**HEADERS, "x-forwarded-for": "198.51.100.9"}
        ).status_code
        for pair in issued
    ]
    assert statuses == [200] * 1000


@pytest.mark.django_db
@pytest.mark.usefixtures("behind_proxy")
def test_one_session_s_31st_renewal_in_a_minute_is_limited() -> None:
    issued, _ = players.create_or_return(uuid.uuid4(), "android", "ar-EG", client=CLIENT)
    client = Client(REMOTE_ADDR="127.0.0.1")
    headers = {**HEADERS, "x-forwarded-for": "198.51.100.10"}
    # The first renewal rotates; the next 29 are replays of the same token, inside the window.
    statuses = [renew(client, issued.refresh, headers=headers).status_code for _ in range(31)]
    assert statuses == [200] * 30 + [429]


@pytest.mark.django_db
@pytest.mark.usefixtures("behind_proxy")
def test_tokens_that_do_not_verify_are_limited_by_address() -> None:
    """At the address rate (3/min here), apart from the address limit's own budget."""
    client = Client(REMOTE_ADDR="127.0.0.1")
    headers = {**HEADERS, "x-forwarded-for": "198.51.100.11"}
    statuses = [renew(client, "not-a-token", headers=headers).status_code for _ in range(4)]
    assert statuses == [401, 401, 401, 429]
    assert get("127.0.0.1", x_forwarded_for="198.51.100.11") == 200


@pytest.mark.parametrize(
    ("address", "key"),
    [
        ("203.0.113.7", "203.0.113.7"),
        ("2001:db8:1:2:aaaa:bbbb:cccc:dddd", "2001:db8:1:2::/64"),
        ("2001:db8:1:2::1", "2001:db8:1:2::/64"),
        ("::ffff:203.0.113.7", "203.0.113.7"),
        ("not-an-address", "not-an-address"),
    ],
)
def test_an_address_bucket_is_an_ipv4_address_or_an_ipv6_slash_64(address: str, key: str) -> None:
    """A phone or home network gets a whole IPv6 /64 and can pick any address in it, so a limit
    per address would be a limit per request (B02 security review)."""
    assert address_bucket(address) == key


@pytest.mark.django_db
def test_rotating_ipv6_addresses_within_a_slash_64_share_the_anonymous_limit(
    settings: Settings,
) -> None:
    settings.THROTTLE_ANONYMOUS_RATE = "2/hour"
    codes = [
        sign_in(Client(REMOTE_ADDR=f"2001:db8:1:2::{n:x}"), uuid.uuid4()).status_code
        for n in range(1, 4)
    ]
    assert codes == [201, 201, 429]
    assert sign_in(Client(REMOTE_ADDR="2001:db8:1:3::1"), uuid.uuid4()).status_code == 201
