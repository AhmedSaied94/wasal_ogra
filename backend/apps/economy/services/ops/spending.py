"""`spend_jenehat`, `spend_bonat` and `use_booster` (contracts/operations.md).

Prices come from the catalog of the declared pack and the balance is the server's own (FR-018,
FR-019). Each operation checks everything that could stop it from applying before the balance,
so a purchase that couldn't apply is never reported as unaffordable.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from typing import Any

from apps.content.services.lookups import Price
from apps.economy.models import Currency, Inventory, LedgerEntry
from apps.economy.services import fuel
from apps.economy.services.batch import BatchState, SessionRow
from apps.economy.services.ops.story import pay_completions
from apps.economy.services.payloads import INT, STR, UUID, Field
from apps.economy.services.sync import CONTENT_VERSION, REJECTED, Ctx, Rejected, register
from apps.progress.models import Ownership
from apps.progress.services import unlocks

Reason = LedgerEntry.Reason
BOOSTERS = frozenset(Inventory.Booster.values)

# What JENEHAT buys, its ledger reason, and where the rules document lists it (upgrades are in the
# catalog only).
JENEHAT_KINDS: dict[str, tuple[str, str]] = {
    "item": (Reason.ITEM_PURCHASE, "items"),
    "vehicle": (Reason.VEHICLE_PURCHASE, "vehicles"),
    "chapter": (Reason.CHAPTER_PURCHASE, "chapters"),
    "upgrade": (Reason.UPGRADE_PURCHASE, ""),
}

# What BONAT buys: the sku ids each kind sells (None: any id the catalog lists) and its reason.
BONAT_KINDS: dict[str, tuple[frozenset[str] | None, str]] = {
    "booster": (BOOSTERS, Reason.BOOSTER_PURCHASE),
    "fuel": (frozenset({"refuel_full"}), Reason.FUEL_PURCHASE),
    "fuel_unlimited": (frozenset({"fuel_unlimited_1h"}), Reason.FUEL_UNLIMITED_PURCHASE),
    "revive": (frozenset({"revive"}), Reason.REVIVE_PURCHASE),
    "cosmetic": (None, Reason.COSMETIC_PURCHASE),
}

_SKU = {
    "sku_kind": Field(STR, max_length=16),
    "sku_id": Field(STR, max_length=64),
    "price": Field(INT, minimum=0),
    "content_version": CONTENT_VERSION,
}


def _for_sale(price: Price | None, currency: str, asked: int) -> None:
    if price is None or price.currency != currency:
        raise Rejected("not_for_sale")
    if asked != price.amount:
        raise Rejected("price_mismatch")


@register(
    "spend_jenehat",
    payload={**_SKU, "variant": Field(STR, required=False, max_length=32)},
    content_version=True,
)
def spend_jenehat(state: BatchState, ctx: Ctx) -> list[dict[str, Any]]:
    pack = ctx.pack_view()
    kind, sku, price = ctx.payload["sku_kind"], ctx.payload["sku_id"], ctx.payload["price"]
    variant: str | None = ctx.payload.get("variant")
    if (kind == "item") != (variant is not None):
        raise Rejected("validation_error", {"field": "variant"})  # required for items only
    rules = pack.rules
    if kind not in JENEHAT_KINDS:
        raise Rejected("unknown_sku")
    reason, listed_in = JENEHAT_KINDS[kind]
    if sku not in rules.get(listed_in, {}) and (kind, sku) not in pack.prices:
        raise Rejected("unknown_sku")
    _for_sale(pack.prices.get((kind, sku)), Currency.JENEHAT, price)
    if kind == "item" and variant not in rules.get("items", {}).get(sku, {}).get("variants", []):
        raise Rejected("unknown_variant")
    view = state.player_view()
    owned = unlocks.vehicle_owned(rules, view, sku) if kind == "vehicle" else state.owns(kind, sku)
    if owned:
        raise Rejected("already_owned")
    if kind == "item" and not unlocks.item_purchasable(rules, view, sku):
        raise Rejected("not_unlocked")
    if kind == "chapter" and not unlocks.chapter_unlocked(rules, view, sku):
        raise Rejected("not_unlocked")
    if state.jenehat < price:
        raise Rejected("insufficient_funds")

    state.debit(Currency.JENEHAT, price, reason, ref_type="sku", ref_id=f"{kind}:{sku}")
    state.add_ownership(kind, sku, variant or "", ctx.t)
    return pay_completions(state, rules, ctx.t)


@register(
    "spend_bonat",
    payload={**_SKU, "ref": Field(UUID, required=False)},
    content_version=True,
)
def spend_bonat(state: BatchState, ctx: Ctx) -> None:
    pack = ctx.pack_view()
    kind, sku, price = ctx.payload["sku_kind"], ctx.payload["sku_id"], ctx.payload["price"]
    listed = pack.prices.get((kind, sku))
    if kind not in BONAT_KINDS:
        raise Rejected("unknown_sku")
    skus, reason = BONAT_KINDS[kind]
    if sku not in (skus if skus is not None else {s for k, s in pack.prices if k == kind}):
        raise Rejected("unknown_sku")
    _for_sale(listed, Currency.BONAT, price)

    apply = _bonat_effect(state, ctx, kind, sku)  # the row's own checks
    if state.bonat < price:
        raise Rejected("insufficient_funds")
    ref = ctx.payload.get("ref")
    state.debit(
        Currency.BONAT,
        price,
        reason,
        ref_type="trip" if kind == "revive" else "sku",
        ref_id=str(ref) if kind == "revive" else f"{kind}:{sku}",
    )
    apply()


def _bonat_effect(state: BatchState, ctx: Ctx, kind: str, sku: str) -> Callable[[], None]:
    """Check what the purchase changes and return the change, applied after the debit."""
    if kind == "booster":
        return lambda: state.add_inventory(sku, 1)
    if kind in ("fuel", "fuel_unlimited"):
        size, regen = state.tank_size(ctx.t), state.regen_ms
        tank = fuel.regenerate(state.fuel_state(), ctx.t_ms, max_liters=size, regen_ms=regen)
        if kind == "fuel_unlimited":
            extended = fuel.extend_unlimited(tank, ctx.t_ms)
            return lambda: state.set_fuel(extended)
        filled = fuel.fill_to_max(tank, ctx.t_ms, max_liters=size)
        if filled is None:
            raise Rejected("tank_full")
        return lambda: state.set_fuel(filled)
    if kind == "revive":
        session = open_trip(state, ctx.payload.get("ref"))
        if session.open_revived:
            raise Rejected("already_revived")
        session.open_revived = True
        return lambda: state.set_session(session)
    if state.owns(Ownership.Kind.COSMETIC, sku):
        raise Rejected("already_owned")
    return lambda: state.add_ownership(Ownership.Kind.COSMETIC, sku, "", ctx.t)


def open_trip(state: BatchState, ref: uuid.UUID | None) -> SessionRow:
    """A copy of the session, when `ref` names the open start (the dependency rule, research
    R5). Shared by the revive purchase, the booster use and the in-trip ads."""
    if ref is not None and state.status_of(ref) == REJECTED:
        raise Rejected("dependency_rejected")
    session = state.session()
    if ref is None or session.open_start != ref:
        raise Rejected("no_trip")
    return session


@register("use_booster", payload={"booster_id": Field(STR, max_length=16), "ref": Field(UUID)})
def use_booster(state: BatchState, ctx: Ctx) -> None:
    booster = ctx.payload["booster_id"]
    open_trip(state, ctx.payload["ref"])
    if booster not in BOOSTERS:
        raise Rejected("unknown_sku")
    if state.inventory(booster) < 1:
        raise Rejected("none_left")
    state.add_inventory(booster, -1)
