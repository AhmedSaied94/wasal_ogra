"""The store product and offer admin pages: add, edit and their validation (B10 US3, US5)."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest
from django.test import Client

from apps.liveops import settings as live
from apps.liveops.models import LiveopsChange, Offer, StoreProduct
from apps.liveops.services import offers as offers_service
from apps.liveops.tests.conftest import staff

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

PRODUCTS = "/admin/liveops/storeproduct/"
OFFERS = "/admin/liveops/offer/"
PRODUCT: dict[str, Any] = {
    "kind": "consumable",
    "platforms": ["android", "ios"],
    "bonat": 90,
    "bonus_bonat": 0,
    "entitlement": "",
    "display_order": 7,
    "active": "on",
}
OFFER: dict[str, Any] = {
    "offer_id": "starter_week",
    "kind": "starter",
    "product_id": "bonat_pack_s",
    "starts_at_0": "2026-11-01",
    "starts_at_1": "12:00:00",
    "ends_at_0": "",
    "ends_at_1": "",
    "priority": 1,
    "rules": "[]",
    "status": "scheduled",
}


def test_a_live_ops_member_adds_a_product_that_has_no_row(live_ops: Client) -> None:
    assert live_ops.get(f"{PRODUCTS}add/").status_code == 200
    response = live_ops.post(f"{PRODUCTS}add/", {"product_id": "starter_pack", **PRODUCT})
    assert response.status_code == 302
    product = StoreProduct.objects.get(product_id="starter_pack")
    assert (product.kind, product.bonat, product.platforms) == (
        "consumable",
        90,
        ["android", "ios"],
    )
    assert LiveopsChange.objects.get(target=LiveopsChange.Target.PRODUCT).key == "starter_pack"


def test_a_live_ops_member_edits_a_product(live_ops: Client) -> None:
    row = StoreProduct.objects.get(product_id="bonat_pack_s")
    assert live_ops.get(f"{PRODUCTS}{row.pk}/change/").status_code == 200
    response = live_ops.post(f"{PRODUCTS}{row.pk}/change/", {**PRODUCT, "bonat": 70})
    assert response.status_code == 302
    row.refresh_from_db()
    assert row.bonat == 70
    assert LiveopsChange.objects.get(target=LiveopsChange.Target.PRODUCT).new is not None


def test_a_live_ops_member_adds_an_offer(live_ops: Client) -> None:
    assert live_ops.get(f"{OFFERS}add/").status_code == 200
    response = live_ops.post(f"{OFFERS}add/", OFFER)
    assert response.status_code == 302
    offer = Offer.objects.get(offer_id="starter_week")
    assert (offer.kind, offer.product.product_id, offer.priority) == (
        "starter",
        "bonat_pack_s",
        1,
    )
    live.refresh_offers()
    assert [row.offer_id for row in live.offers()] == ["starter_week"]


def test_a_live_ops_member_edits_an_offer(live_ops: Client) -> None:
    offers_service.save_offer(
        "starter_week",
        actor=None,
        kind="starter",
        product_id="bonat_pack_s",
        starts_at=datetime(2026, 11, 1, 12, tzinfo=UTC),
        ends_at=None,
        priority=1,
        rules=[],
        status="scheduled",
    )
    offer = Offer.objects.get(offer_id="starter_week")
    page = live_ops.get(f"{OFFERS}{offer.pk}/change/")
    assert page.status_code == 200
    assert page.context["adminform"].form.fields["product_id"].initial == "bonat_pack_s"
    response = live_ops.post(f"{OFFERS}{offer.pk}/change/", {**OFFER, "priority": 5})
    assert response.status_code == 302
    offer.refresh_from_db()
    assert offer.priority == 5


def test_an_unknown_rule_is_refused_naming_it(live_ops: Client) -> None:
    response = live_ops.post(f"{OFFERS}add/", {**OFFER, "rules": '[{"rule": "vip"}]'})
    assert response.status_code == 200
    assert b"vip" in response.content
    assert "rules" in response.context["adminform"].form.errors
    assert not Offer.objects.exists()


@pytest.mark.parametrize(
    ("bonat", "field", "text"),
    [("-5", "bonat", "greater than or equal to 0"), ("abc", "bonat", "whole number")],
)
def test_an_invalid_amount_shows_the_form_error_not_a_crash(
    live_ops: Client, bonat: str, field: str, text: str
) -> None:
    response = live_ops.post(
        f"{PRODUCTS}add/", {**PRODUCT, "product_id": "starter_pack", "bonat": bonat}
    )
    assert response.status_code == 200
    errors = response.context["adminform"].form.errors
    assert field in errors
    assert text in errors[field][0]
    assert not StoreProduct.objects.filter(product_id="starter_pack").exists()
    assert not LiveopsChange.objects.exists()


def test_the_products_page_needs_the_live_ops_permissions() -> None:
    viewer = staff("viewer1", None, "view_livesetting")
    assert viewer.get(PRODUCTS).status_code == 403
    assert viewer.get(f"{PRODUCTS}add/").status_code == 403
    assert viewer.get(OFFERS).status_code == 403
