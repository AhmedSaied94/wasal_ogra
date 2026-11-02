"""The store catalog: typed grants, the product save and the list `GET /v1/offers` returns.

B06 calls `grants_for` inside its grant transaction; B10 only defines grants, never applies them
(constitution IV, B10 research R11).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from django.db import transaction

from apps.accounts.models import User
from apps.liveops import settings as live
from apps.liveops.models import LiveopsChange, StoreProduct

# Glossary §3.5: the ids the store sells. A form may only name one of them.
KNOWN_PRODUCT_IDS = frozenset(
    {
        "bonat_pack_s",
        "bonat_pack_m",
        "bonat_pack_l",
        "starter_pack",
        "remove_ads",
        "sub_ostaz_weekly",
        "sub_ostaz_monthly",
    }
)
KNOWN_PREFIXES = ("season_pass_",)
PLATFORMS = ("android", "ios")
FIELDS = (
    "kind",
    "platforms",
    "bonat",
    "bonus_bonat",
    "entitlement",
    "best_value",
    "display_order",
    "active",
)


class ProductUnavailable(Exception):
    """The product is unknown, inactive or not sold on that platform (FR-022)."""


@dataclass(frozen=True)
class ProductGrants:
    """What a purchase grants. B06 stores it on `Purchase` (research R11)."""

    bonat_total: int
    entitlement: str | None


def is_known(product_id: str) -> bool:
    return product_id in KNOWN_PRODUCT_IDS or product_id.startswith(KNOWN_PREFIXES)


def grants_for(product_id: str, platform: str) -> ProductGrants:
    """The grants of an active product sold on `platform`, or `ProductUnavailable`."""
    product = next((row for row in live.products() if row.product_id == product_id), None)
    if product is None or not product.active or platform not in product.platforms:
        raise ProductUnavailable(product_id)
    return ProductGrants(
        bonat_total=product.bonat + product.bonus_bonat,
        entitlement=product.entitlement or None,
    )


def active_products(platform: str) -> list[Any]:
    """Active products offered on `platform`, in display order (research R12)."""
    return [
        product for product in live.products() if product.active and platform in product.platforms
    ]


def save_product(
    product_id: str,
    *,
    actor: User | None,
    note: str = "",
    **values: Any,
) -> StoreProduct:
    """Validate one product and write it with a `product` change, in one transaction."""
    if not is_known(product_id):
        raise ValueError(f"{product_id} is not a known product.")
    check_product(values)
    with transaction.atomic():
        product = StoreProduct.objects.select_for_update().filter(product_id=product_id).first()
        old = row_of(product) if product is not None else None
        if product is None:
            product = StoreProduct(product_id=product_id)
        for field in FIELDS:
            setattr(product, field, values[field])
        _check_best_value(product)
        product.save()
        LiveopsChange.objects.create(
            target=LiveopsChange.Target.PRODUCT,
            key=product_id,
            old=old,
            new=row_of(product),
            source=LiveopsChange.Source.ADMIN,
            actor=actor,
            note=note,
        )
        transaction.on_commit(lambda: live.refresh_products())
    return product


def row_of(product: StoreProduct) -> dict[str, Any]:
    return {field: getattr(product, field) for field in ("product_id", *FIELDS)}


def check_product(values: dict[str, Any]) -> None:
    """The kind/grants coherence the database enforces, with a readable message."""
    kind = values.get("kind")
    if kind not in StoreProduct.Kind.values:
        raise ValueError(f"{kind!r} is not a product kind.")
    platforms = values.get("platforms") or []
    if not platforms or any(platform not in PLATFORMS for platform in platforms):
        raise ValueError("Pick at least one of android and ios.")
    bonat = _amount("bonat", values.get("bonat"))
    bonus = _amount("bonus_bonat", values.get("bonus_bonat"))
    entitlement = values.get("entitlement") or ""
    if kind == StoreProduct.Kind.CONSUMABLE and not (bonat > 0 and entitlement == ""):
        raise ValueError("A consumable needs BONAT and no entitlement.")
    if kind == StoreProduct.Kind.NON_CONSUMABLE and not (entitlement and bonat == 0 and bonus == 0):
        raise ValueError("A non-consumable needs an entitlement and no BONAT.")


def _amount(field: str, value: Any) -> int:
    """One BONAT column as a count. A field that failed its own validation arrives as None."""
    if isinstance(value, bool) or value is None:
        raise ValueError(f"{field} must be a whole number of BONAT.")
    try:
        amount = int(value)
    except (TypeError, ValueError):
        raise ValueError(f"{field} must be a whole number of BONAT.") from None
    if amount < 0:
        raise ValueError("A BONAT amount can't be negative.")
    return amount


def _check_best_value(product: StoreProduct) -> None:
    if not (product.active and product.best_value):
        return
    rival = (
        StoreProduct.objects.filter(active=True, best_value=True)
        .exclude(product_id=product.product_id)
        .exists()
    )
    if rival:
        raise ValueError("Only one active product can be the best value.")
