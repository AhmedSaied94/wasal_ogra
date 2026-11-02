"""`GET /v1/offers` (B10 contracts/api.md "GET /v1/offers", FR-019 to FR-024)."""

from __future__ import annotations

import json
from collections.abc import Callable

import pytest
from django.test import Client
from pytest_django import DjangoAssertNumQueries

from apps.economy.tests.helpers import Api, signed_in_api
from apps.liveops import settings as live
from apps.liveops.models import Offer, StoreProduct

pytestmark = pytest.mark.django_db

URL = "/v1/offers"
ANDROID = {"x-client-version": "1.0.0", "x-platform": "android"}
IOS = {"x-client-version": "1.0.0", "x-platform": "ios"}


@pytest.fixture
def api() -> Api:
    return signed_in_api()


def test_the_response_shape(api: Api, no_throttle: None) -> None:
    response = api.client.get(URL, headers=api.headers)
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"server_time", "products", "offers"}
    assert body["server_time"].endswith("Z")
    assert body["products"] == [
        {
            "product_id": "bonat_pack_s",
            "kind": "consumable",
            "bonat": 60,
            "bonus_bonat": 0,
            "entitlement": None,
            "best_value": False,
        },
        {
            "product_id": "bonat_pack_m",
            "kind": "consumable",
            "bonat": 300,
            "bonus_bonat": 30,
            "entitlement": None,
            "best_value": False,
        },
        {
            "product_id": "bonat_pack_l",
            "kind": "consumable",
            "bonat": 800,
            "bonus_bonat": 120,
            "entitlement": None,
            "best_value": True,
        },
        {
            "product_id": "remove_ads",
            "kind": "non_consumable",
            "bonat": 0,
            "bonus_bonat": 0,
            "entitlement": "remove_ads",
            "best_value": False,
        },
    ]
    assert body["offers"] == []


def test_no_price_or_currency_anywhere(api: Api) -> None:
    body = api.client.get(URL, headers=api.headers).json()
    text = json.dumps(body)
    assert "price" not in text
    assert "currency" not in text


def test_only_the_request_platforms_products(api: Api) -> None:
    StoreProduct.objects.filter(product_id="bonat_pack_m").update(platforms=["ios"])
    live.refresh_products()
    android = api.client.get(URL, headers=api.headers).json()["products"]
    assert "bonat_pack_m" not in [product["product_id"] for product in android]
    ios = api.client.get(URL, headers={**api.headers, **IOS}).json()["products"]
    assert "bonat_pack_m" in [product["product_id"] for product in ios]


def test_the_cache_control_header(api: Api) -> None:
    response = api.client.get(URL, headers=api.headers)
    assert response["Cache-Control"] == "private, no-store"


def test_a_token_is_required() -> None:
    assert Client().get(URL, headers=ANDROID).status_code == 401


def test_an_old_app_gets_426(api: Api, live_settings: Callable[..., None]) -> None:
    live_settings(min_client_version_android="1.3.0", latest_client_version_android="1.4.0")
    response = api.client.get(URL, headers={**api.headers, **ANDROID})
    assert response.status_code == 426


def test_offers_answer_during_maintenance(api: Api, live_settings: Callable[..., None]) -> None:
    live_settings(maintenance_enabled=True)
    assert api.client.get(URL, headers=api.headers).status_code == 200


def test_an_offer_is_listed(api: Api) -> None:
    Offer.objects.create(
        offer_id="eg_launch_week",
        kind="sale",
        product=StoreProduct.objects.get(product_id="remove_ads"),
        starts_at="2020-01-01T00:00:00Z",
        ends_at="2030-01-01T00:00:00Z",
        priority=1,
        rules=[],
        status="active",
    )
    live.refresh_offers()
    body = api.client.get(URL, headers=api.headers).json()
    assert body["offers"] == [
        {
            "offer_id": "eg_launch_week",
            "kind": "sale",
            "product_id": "remove_ads",
            "ends_at": "2030-01-01T00:00:00Z",
        }
    ]


def test_the_query_count_does_not_grow_with_the_offers(
    api: Api, django_assert_num_queries: DjangoAssertNumQueries
) -> None:
    live.refresh_products()
    live.refresh_offers()
    api.client.get(URL, headers=api.headers)  # warm the snapshots and the session
    with django_assert_num_queries(2):  # the player and one StoryState query
        api.client.get(URL, headers=api.headers)
    product = StoreProduct.objects.get(product_id="remove_ads")
    for index in range(20):
        Offer.objects.create(
            offer_id=f"many_{index}",
            kind="sale",
            product=product,
            starts_at="2020-01-01T00:00:00Z",
            ends_at="2030-01-01T00:00:00Z",
            priority=index,
            rules=[],
            status="active",
        )
    live.refresh_offers()
    with django_assert_num_queries(2):
        response = api.client.get(URL, headers=api.headers)
    assert len(response.json()["offers"]) == 20
