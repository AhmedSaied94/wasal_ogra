"""Offer rules: one validator and one evaluator each (B10 contracts/offers.md, research R12).

A player sees an offer only when every rule holds. Times, the product's platform and non-consumable
ownership are applied whatever the rules.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Mapping
from datetime import UTC, date, datetime
from typing import Any
from zoneinfo import ZoneInfo

from django.db import transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.liveops import settings as live
from apps.liveops.models import LiveopsChange, Offer, StoreProduct
from apps.liveops.services import catalog, facts

CAIRO = ZoneInfo("Africa/Cairo")
CHAPTER = re.compile(r"^[a-z0-9_]{3,32}$")
COUNTRY = re.compile(r"^[A-Z]{2}$")
STATUS_RANK = {"open": 1, "completed": 2}
FIELDS = ("kind", "product_id", "starts_at", "ends_at", "priority", "rules", "status")


class OfferRefused(ValueError):
    """A rule or a field of an offer is invalid; the message names the rule's position."""


def validate_rules(rules: Any) -> list[dict[str, Any]]:
    """The rules with only their documented fields, or `OfferRefused` naming position and rule."""
    if not isinstance(rules, list):
        raise OfferRefused("Rules must be a list.")
    validated: list[dict[str, Any]] = []
    for position, rule in enumerate(rules, start=1):
        if not isinstance(rule, dict):
            raise OfferRefused(f"Rule {position} must be an object.")
        name = rule.get("rule")
        validator = VALIDATORS.get(name) if isinstance(name, str) else None
        if validator is None:
            raise OfferRefused(f"Rule {position}: {name!r} is not a known rule.")
        _fields(position, name, rule, validator.fields)
        validator.check(position, rule)
        validated.append({key: rule[key] for key in validator.fields})
    return validated


class _Rule:
    def __init__(
        self,
        fields: tuple[str, ...],
        check: Callable[[int, Mapping[str, Any]], None],
    ) -> None:
        self.fields = fields
        self.check = check


def _fields(position: int, name: Any, rule: Mapping[str, Any], expected: tuple[str, ...]) -> None:
    missing = [field for field in expected if field not in rule]
    extra = [field for field in rule if field not in expected]
    if missing:
        raise OfferRefused(f"Rule {position} ({name}): {missing[0]} is required.")
    if extra:
        raise OfferRefused(f"Rule {position} ({name}): {extra[0]} is not a field of this rule.")


def _integer(position: int, name: str, value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise OfferRefused(f"Rule {position} ({name}): {value!r} must be a whole number.")
    return int(value)


def _check_country(position: int, rule: Mapping[str, Any]) -> None:
    countries = rule["countries"]
    if not isinstance(countries, list) or not countries:
        raise OfferRefused(f"Rule {position} (country_in): countries must be a non-empty list.")
    for country in countries:
        if not isinstance(country, str) or not COUNTRY.match(country):
            raise OfferRefused(
                f"Rule {position} (country_in): {country!r} must be an ISO 3166-1 alpha-2 code."
            )


def _check_days(position: int, rule: Mapping[str, Any]) -> None:
    minimum = _integer(position, "days_since_install", rule["min"])
    maximum = _integer(position, "days_since_install", rule["max"])
    if not 0 <= minimum <= maximum <= 3650:
        raise OfferRefused(f"Rule {position} (days_since_install): use 0 <= min <= max <= 3650.")


def _check_payer(position: int, rule: Mapping[str, Any]) -> None:
    if not isinstance(rule["is"], bool):
        raise OfferRefused(f"Rule {position} (payer): is must be true or false.")


def _check_product(position: int, name: str, rule: Mapping[str, Any]) -> None:
    product_id = rule["product_id"]
    if not isinstance(product_id, str) or not catalog.is_known(product_id):
        raise OfferRefused(f"Rule {position} ({name}): {product_id!r} is not a known product.")


def _check_chapter(position: int, rule: Mapping[str, Any]) -> None:
    chapter = rule["chapter_id"]
    if not isinstance(chapter, str) or not CHAPTER.match(chapter):
        raise OfferRefused(f"Rule {position} (chapter_reached): {chapter!r} is not a chapter id.")
    if rule["status"] not in STATUS_RANK:
        raise OfferRefused(f"Rule {position} (chapter_reached): status must be open or completed.")


VALIDATORS = {
    "country_in": _Rule(("rule", "countries"), _check_country),
    "days_since_install": _Rule(("rule", "min", "max"), _check_days),
    "payer": _Rule(("rule", "is"), _check_payer),
    "owns_product": _Rule(
        ("rule", "product_id"), lambda p, r: _check_product(p, "owns_product", r)
    ),
    "lacks_product": _Rule(
        ("rule", "product_id"), lambda p, r: _check_product(p, "lacks_product", r)
    ),
    "chapter_reached": _Rule(("rule", "chapter_id", "status"), _check_chapter),
}


# -- evaluation ------------------------------------------------------------------------------------


def _product(product_id: str) -> Any:
    return next((row for row in live.products() if row.product_id == product_id), None)


def _owns(found: facts.PlayerFacts, product_id: str) -> bool:
    product = _product(product_id)
    if product is None or not product.entitlement:
        return False
    return product.entitlement in found.entitlements


def _holds(rule: Mapping[str, Any], found: facts.PlayerFacts, now: datetime) -> bool:
    name = rule.get("rule")
    if name == "country_in":
        return bool(found.country) and bool(found.country.upper() in rule["countries"])
    if name == "days_since_install":
        days = (_cairo_day(now) - _cairo_day(found.installed_at)).days
        return bool(rule["min"] <= days <= rule["max"])
    if name == "payer":
        return bool(found.has_purchase == rule["is"])
    if name == "owns_product":
        return _owns(found, rule["product_id"])
    if name == "lacks_product":
        return not _owns(found, rule["product_id"])
    if name == "chapter_reached":
        reached = STATUS_RANK.get(found.chapters.get(rule["chapter_id"], ""), 0)
        return reached >= STATUS_RANK[rule["status"]]
    return False


def _cairo_day(instant: datetime) -> date:
    return instant.astimezone(CAIRO).date()


def eligible_offers(player: Any, platform: str, *, now: datetime | None = None) -> list[Offer]:
    """The offers this player may see now, priority first, over the per-process snapshot."""
    at = now or timezone.now()
    found = facts.for_player(player)
    listed: list[Offer] = []
    for offer in live.offers():
        if offer.starts_at > at or (offer.ends_at is not None and at >= offer.ends_at):
            continue
        product = _product(offer.product.product_id)
        if product is None or not product.active or platform not in product.platforms:
            continue
        if product.kind == StoreProduct.Kind.NON_CONSUMABLE and _owns(found, product.product_id):
            continue
        if all(_holds(rule, found, at) for rule in offer.rules):
            listed.append(offer)
    return listed


# -- writes ----------------------------------------------------------------------------------------


def save_offer(
    offer_id: str,
    *,
    actor: User | None,
    note: str = "",
    **values: Any,
) -> Offer:
    """Validate one offer and write it with an `offer` change, in one transaction."""
    rules = validate_rules(values["rules"])
    if values["kind"] not in Offer.Kind.values:
        raise OfferRefused(f"{values['kind']!r} is not an offer kind.")
    if values.get("status", Offer.Status.SCHEDULED) not in Offer.Status.values:
        raise OfferRefused(f"{values['status']!r} is not an offer status.")
    if not CHAPTER.match(offer_id):
        raise OfferRefused("Use lowercase letters, digits and underscores for the id.")
    product = StoreProduct.objects.filter(product_id=values["product_id"]).first()
    if product is None:
        raise OfferRefused(f"{values['product_id']} is not a product.")
    if values["ends_at"] is not None and values["ends_at"] <= values["starts_at"]:
        raise OfferRefused("The end must be after the start.")
    with transaction.atomic():
        offer = Offer.objects.select_for_update().filter(offer_id=offer_id).first()
        old = row_of(offer) if offer is not None else None
        if offer is None:
            offer = Offer(offer_id=offer_id)
        offer.kind = values["kind"]
        offer.product = product
        offer.starts_at = values["starts_at"]
        offer.ends_at = values["ends_at"]
        offer.priority = values["priority"]
        offer.rules = rules
        offer.status = values.get("status", Offer.Status.SCHEDULED)
        offer.save()
        LiveopsChange.objects.create(
            target=LiveopsChange.Target.OFFER,
            key=offer_id,
            old=old,
            new=row_of(offer),
            source=LiveopsChange.Source.ADMIN,
            actor=actor,
            note=note,
        )
        transaction.on_commit(live.refresh_offers)
    return offer


def row_of(offer: Offer) -> dict[str, Any]:
    """The whole row as the history stores it (JSON only)."""
    return {
        "offer_id": offer.offer_id,
        "kind": offer.kind,
        "product_id": offer.product.product_id,
        "starts_at": offer.starts_at.astimezone(UTC).isoformat(),
        "ends_at": offer.ends_at.astimezone(UTC).isoformat() if offer.ends_at else None,
        "priority": offer.priority,
        "rules": list(offer.rules),
        "status": offer.status,
    }


def expire(now: datetime | None = None) -> dict[str, int]:
    """The hourly job: scheduled → active when the start passes, → expired when the end does."""
    at = now or timezone.now()
    started = Offer.objects.filter(status=Offer.Status.SCHEDULED, starts_at__lte=at).update(
        status=Offer.Status.ACTIVE
    )
    ended = Offer.objects.filter(status=Offer.Status.ACTIVE, ends_at__lte=at).update(
        status=Offer.Status.EXPIRED
    )
    if started or ended:
        live.refresh_offers()
    return {"started": started, "expired": ended}
