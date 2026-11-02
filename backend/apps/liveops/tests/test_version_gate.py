"""The version gate: an app too old to play safely is asked to update (B10 US2, api.md)."""

from __future__ import annotations

import uuid
from collections.abc import Callable

import pytest
from django.test import Client

from apps.economy.models import ProcessedOp
from apps.economy.tests.helpers import Api, batch, signed_in_api

pytestmark = pytest.mark.django_db

ANDROID_OLD = {"x-client-version": "1.2.4", "x-platform": "android"}
IOS_OLD = {"x-client-version": "1.2.4", "x-platform": "ios"}


@pytest.fixture
def api() -> Api:
    return signed_in_api()


@pytest.fixture
def minimum(live_settings: Callable[..., None]) -> None:
    live_settings(min_client_version_android="1.3.0", latest_client_version_android="1.4.0")


def error_of(response: object) -> dict[str, object]:
    body = response.json()  # type: ignore[attr-defined]
    return body["error"]  # type: ignore[no-any-return]


def test_sync_below_the_minimum_answers_426_and_applies_nothing(api: Api, minimum: None) -> None:
    response = api.sync(batch(), **ANDROID_OLD)
    assert response.status_code == 426
    assert error_of(response) == {
        "code": "client_outdated",
        "message": "Client outdated",
        "details": {"min_version": "1.3.0"},
    }
    assert not ProcessedOp.objects.exists()


def test_state_below_the_minimum_answers_426(api: Api, minimum: None) -> None:
    assert api.state(**ANDROID_OLD).status_code == 426


def test_link_below_the_minimum_answers_426(api: Api, minimum: None) -> None:
    response = api.client.post(
        "/v1/auth/link",
        data={"provider": "google", "id_token": "x"},
        content_type="application/json",
        headers={**api.headers, **ANDROID_OLD},
    )
    assert response.status_code == 426


def test_bootstrap_stays_200_with_the_live_client_block(api: Api, minimum: None) -> None:
    response = api.bootstrap(**ANDROID_OLD)
    assert response.status_code == 200
    assert response.json()["client"] == {
        "min_version": "1.3.0",
        "latest_version": "1.4.0",
        "force_update": True,
    }


def test_a_build_suffix_counts_as_its_version(api: Api, minimum: None) -> None:
    assert api.sync(batch(), **{**ANDROID_OLD, "x-client-version": "1.3.0+57"}).status_code == 200


def test_the_ios_minimum_is_independent(api: Api, live_settings: Callable[..., None]) -> None:
    live_settings(
        min_client_version_android="1.3.0",
        latest_client_version_android="1.4.0",
        min_client_version_ios="1.0.0",
    )
    assert api.sync(batch(), **IOS_OLD).status_code == 200
    assert api.sync(batch(), **ANDROID_OLD).status_code == 426


def test_anonymous_refresh_and_the_manifest_are_not_gated(api: Api, minimum: None) -> None:
    anonymous = Client().post(
        "/v1/auth/anonymous",
        data={"install_id": str(uuid.uuid4()), "platform": "android", "locale": "ar-EG"},
        content_type="application/json",
        headers=ANDROID_OLD,
    )
    assert anonymous.status_code == 201
    refresh = api.client.post(
        "/v1/auth/refresh",
        data={"refresh": "not-a-token"},
        content_type="application/json",
        headers={**api.headers, **ANDROID_OLD},
    )
    assert refresh.status_code == 401
    assert api.client.get("/v1/content/manifest", headers=ANDROID_OLD).status_code == 200
    assert api.client.get("/healthz", headers=ANDROID_OLD).status_code == 200


def test_authentication_comes_before_the_version(api: Api, minimum: None) -> None:
    anonymous = Client()
    response = anonymous.post(
        "/v1/sync",
        data=batch(),
        content_type="application/json",
        headers=ANDROID_OLD,
    )
    assert response.status_code == 401


def test_a_missing_header_comes_before_the_version(api: Api, minimum: None) -> None:
    response = api.client.get(
        "/v1/state",
        headers={"authorization": api.headers["authorization"], "x-client-version": "1.2.4"},
    )
    assert response.status_code == 400


def test_the_version_comes_before_maintenance(
    api: Api, minimum: None, live_settings: Callable[..., None]
) -> None:
    live_settings(maintenance_enabled=True)
    assert api.sync(batch(), **ANDROID_OLD).status_code == 426
    current = {"x-client-version": "1.4.0", "x-platform": "android"}
    assert api.sync(batch(), **current).status_code == 503
