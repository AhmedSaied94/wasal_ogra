"""`tutorial_gift`, `comeback_gift` and `claim_request` (contracts/operations.md, research R9).

The gifts fill the tank without a ledger entry, since fuel is not a currency. A request's reward is
BONAT the pack sets, so its entry's source is the server's, not the phone's (the direction rule).
"""

from __future__ import annotations

from typing import Any

from apps.economy.models import Currency, GrantRecord, LedgerEntry
from apps.economy.services import comeback, fuel
from apps.economy.services.batch import BatchState
from apps.economy.services.payloads import STR, Field
from apps.economy.services.sync import CONTENT_VERSION, Ctx, Rejected, register

COMEBACK_BOOSTER = "change_bag"


def _fill(state: BatchState, ctx: Ctx) -> None:
    """Fuel to the maximum (`fuel.gift`: a full tank stays as it is)."""
    size = state.tank_size(ctx.t)
    state.set_fuel(
        fuel.gift(state.fuel_state(), ctx.t_ms, max_liters=size, regen_ms=state.regen_ms)
    )


@register("tutorial_gift", payload={})
def tutorial_gift(state: BatchState, ctx: Ctx) -> list[dict[str, Any]]:
    if state.granted(GrantRecord.Kind.TUTORIAL, ""):
        raise Rejected("already_granted")
    _fill(state, ctx)
    state.add_grant(GrantRecord.Kind.TUTORIAL, "", ctx.t)
    return [{"kind": "gift", "id": "tutorial", "fuel": "max"}]


@register("comeback_gift", payload={})
def comeback_gift(state: BatchState, ctx: Ctx) -> list[dict[str, Any]]:
    return_at = state.comeback_return_at
    if return_at is None:
        raise Rejected("not_eligible")
    key = comeback.return_key(return_at)
    if state.granted(GrantRecord.Kind.COMEBACK, key):
        raise Rejected("already_granted")
    last = state.last_grant(GrantRecord.Kind.COMEBACK)
    if not comeback.cooldown_passed(last, ctx.t, state.settings):
        raise Rejected("not_eligible")
    _fill(state, ctx)
    state.add_inventory(COMEBACK_BOOSTER, 1)
    state.add_grant(GrantRecord.Kind.COMEBACK, key, ctx.t)
    return [{"kind": "gift", "id": "comeback", "fuel": "max", "booster": COMEBACK_BOOSTER}]


@register(
    "claim_request",
    payload={"request_id": Field(STR, max_length=40), "content_version": CONTENT_VERSION},
    content_version=True,
)
def claim_request(state: BatchState, ctx: Ctx) -> list[dict[str, Any]]:
    request_id: str = ctx.payload["request_id"]
    request = ctx.pack_view().rules["requests"].get(request_id)
    if request is None:
        raise Rejected("unknown_sku")
    if state.granted(GrantRecord.Kind.REQUEST, request_id):
        raise Rejected("already_granted")
    owned = state.owned_variant("item", request["item_id"])
    if owned is None or request["variant_id"] not in ("", owned):
        raise Rejected("not_eligible")
    reward: int = request["reward_bonat"]
    state.credit(
        Currency.BONAT,
        reward,
        LedgerEntry.Reason.REQUEST_REWARD,
        ref_type="request",
        ref_id=request_id,
        source=LedgerEntry.Source.SYSTEM,
    )
    state.add_grant(GrantRecord.Kind.REQUEST, request_id, ctx.t)
    return [{"kind": "request", "id": request_id, "currency": "BONAT", "amount": reward}]
