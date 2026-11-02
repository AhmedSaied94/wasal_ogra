"""The store catalog: the seed, the constraints, `grants_for` and the product history (B10 US3)."""

from __future__ import annotations

from typing import Any

import pytest
from django.db import IntegrityError, transaction

from apps.accounts.models import User
from apps.liveops import settings as live
from apps.liveops.admin import StoreProductForm
from apps.liveops.models import LiveopsChange, StoreProduct
from apps.liveops.services import catalog

pytestmark = pytest.mark.django_db

SEED = [
    ("bonat_pack_s", "consumable", 60, 0, "", False, 1),
    ("bonat_pack_m", "consumable", 300, 30, "", False, 2),
    ("bonat_pack_l", "consumable", 800, 120, "", True, 3),
    ("remove_ads", "non_consumable", 0, 0, "remove_ads", False, 4),
]


def test_the_seed_has_the_four_products_on_both_platforms() -> None:
    rows = {
        product.product_id: product for product in StoreProduct.objects.order_by("display_order")
    }
    assert [
        (
            row.product_id,
            row.kind,
            row.bonat,
            row.bonus_bonat,
            row.entitlement,
            row.best_value,
            row.display_order,
        )
        for row in rows.values()
    ] == SEED
    assert all(row.platforms == ["android", "ios"] for row in rows.values())
    assert all(row.active for row in rows.values())
    assert not hasattr(StoreProduct, "price")


def make(**overrides: Any) -> StoreProduct:
    values = {
        "product_id": "season_pass_season_1",
        "kind": "non_consumable",
        "platforms": ["android"],
        "bonat": 0,
        "bonus_bonat": 0,
        "entitlement": "season_pass_1",
        "display_order": 9,
        "active": True,
    }
    values.update(overrides)
    return StoreProduct(**values)


@pytest.mark.parametrize(
    "row",
    [
        make(product_id="bonat_pack_x", kind="consumable", bonat=0, entitlement=""),
        make(product_id="bonat_pack_y", kind="consumable", bonat=10, entitlement="remove_ads"),
        make(product_id="remove_ads_2", kind="non_consumable", entitlement=""),
        make(product_id="remove_ads_3", kind="non_consumable", bonat=5, entitlement="remove_ads"),
    ],
)
def test_the_grant_constraints_refuse_incoherent_rows(row: StoreProduct) -> None:
    with pytest.raises(IntegrityError), transaction.atomic():
        row.save()


def test_a_second_active_best_value_is_refused() -> None:
    with pytest.raises(IntegrityError), transaction.atomic():
        make(product_id="remove_ads_4", entitlement="remove_ads", best_value=True).save()


def test_an_empty_platform_list_is_refused() -> None:
    with pytest.raises(IntegrityError), transaction.atomic():
        make(platforms=[]).save()


def test_the_form_refuses_an_unknown_product_id() -> None:
    form = StoreProductForm(
        data={
            "product_id": "bogus_pack",
            "kind": "consumable",
            "platforms": ["android"],
            "bonat": 10,
            "bonus_bonat": 0,
            "entitlement": "",
            "best_value": "",
            "display_order": 5,
            "active": "on",
        }
    )
    assert form.is_valid() is False
    assert "product_id" in form.errors


def test_grants_for_sums_the_bonus() -> None:
    live.refresh_products()
    assert catalog.grants_for("bonat_pack_l", "android") == catalog.ProductGrants(920, None)
    assert catalog.grants_for("remove_ads", "android") == catalog.ProductGrants(0, "remove_ads")


@pytest.mark.parametrize(
    ("product_id", "platform"),
    [("pack_unknown", "android"), ("bonat_pack_s", "web")],
)
def test_grants_for_refuses_an_unknown_or_other_platform_product(
    product_id: str, platform: str
) -> None:
    live.refresh_products()
    with pytest.raises(catalog.ProductUnavailable):
        catalog.grants_for(product_id, platform)


def test_grants_for_refuses_an_inactive_product() -> None:
    StoreProduct.objects.filter(product_id="bonat_pack_s").update(active=False)
    live.refresh_products()
    with pytest.raises(catalog.ProductUnavailable):
        catalog.grants_for("bonat_pack_s", "android")


def test_active_products_keeps_the_display_order() -> None:
    live.refresh_products()
    assert [product.product_id for product in catalog.active_products("android")] == [
        "bonat_pack_s",
        "bonat_pack_m",
        "bonat_pack_l",
        "remove_ads",
    ]


def test_a_save_writes_a_product_change() -> None:
    actor = User.objects.create_user("ops", is_staff=True)
    values: dict[str, Any] = {
        "kind": "consumable",
        "platforms": ["android", "ios"],
        "bonat": 70,
        "bonus_bonat": 0,
        "entitlement": "",
        "best_value": False,
        "display_order": 1,
        "active": True,
    }
    catalog.save_product("bonat_pack_s", actor=actor, note="raise it", **values)
    assert StoreProduct.objects.get(product_id="bonat_pack_s").bonat == 70
    change = LiveopsChange.objects.get(target=LiveopsChange.Target.PRODUCT)
    assert change.key == "bonat_pack_s"
    assert change.new is not None
    assert change.new["bonat"] == 70
    assert change.old is not None
    assert change.old["bonat"] == 60
    assert change.note == "raise it"


def test_a_save_of_an_incoherent_row_writes_nothing() -> None:
    actor = User.objects.create_user("ops", is_staff=True)
    values: dict[str, Any] = {
        "kind": "consumable",
        "platforms": ["android"],
        "bonat": 0,
        "bonus_bonat": 0,
        "entitlement": "",
        "best_value": False,
        "display_order": 1,
        "active": True,
    }
    with pytest.raises(ValueError, match="A consumable needs BONAT"):
        catalog.save_product("bonat_pack_s", actor=actor, **values)
    assert not LiveopsChange.objects.exists()


def test_a_second_best_value_is_refused_readably() -> None:
    actor = User.objects.create_user("ops", is_staff=True)
    values: dict[str, Any] = {
        "kind": "consumable",
        "platforms": ["android", "ios"],
        "bonat": 300,
        "bonus_bonat": 30,
        "entitlement": "",
        "best_value": True,
        "display_order": 2,
        "active": True,
    }
    with pytest.raises(ValueError, match="best value"):
        catalog.save_product("bonat_pack_m", actor=actor, **values)
    assert not LiveopsChange.objects.exists()


def test_a_save_refuses_an_unknown_product_id() -> None:
    actor = User.objects.create_user("ops", is_staff=True)
    with pytest.raises(ValueError, match="not a known product"):
        catalog.save_product("bogus_pack", actor=actor, **{})


def test_a_save_creates_a_known_product_that_has_no_row() -> None:
    actor = User.objects.create_user("ops", is_staff=True)
    values: dict[str, Any] = {
        "kind": "non_consumable",
        "platforms": ["android"],
        "bonat": 0,
        "bonus_bonat": 0,
        "entitlement": "season_pass_s1",
        "best_value": False,
        "display_order": 9,
        "active": True,
    }
    catalog.save_product("season_pass_s1", actor=actor, **values)
    assert StoreProduct.objects.filter(product_id="season_pass_s1").exists()
    change = LiveopsChange.objects.get(target=LiveopsChange.Target.PRODUCT)
    assert change.old is None


@pytest.mark.parametrize(
    ("overrides", "text"),
    [
        ({"kind": "bundle"}, "is not a product kind"),
        ({"platforms": []}, "Pick at least one of android and ios."),
        ({"platforms": ["web"]}, "Pick at least one of android and ios."),
        ({"kind": "consumable", "bonat": -1, "entitlement": ""}, "can't be negative"),
        ({"kind": "consumable", "bonat": None, "entitlement": ""}, "whole number"),
        ({"kind": "consumable", "bonat": "abc", "entitlement": ""}, "whole number"),
        ({"kind": "non_consumable", "entitlement": ""}, "needs an entitlement"),
    ],
)
def test_the_save_validates_the_platforms_and_the_amounts(
    overrides: dict[str, Any], text: str
) -> None:
    values: dict[str, Any] = {
        "kind": "consumable",
        "platforms": ["android"],
        "bonat": 10,
        "bonus_bonat": 0,
        "entitlement": "",
        "best_value": False,
        "display_order": 9,
        "active": True,
        **overrides,
    }
    with pytest.raises(ValueError, match=text):
        catalog.check_product(values)
