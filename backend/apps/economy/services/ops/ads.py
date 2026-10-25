"""`ad_reward` (contracts/operations.md `ad_reward`, contracts/fuel.md).

The phone reports an ad it showed; the server checks what the placement may give. The in-trip
placements name the open start in `ref`, and `morning_piggy` is the server's alone.
"""

from __future__ import annotations

from apps.economy.models import Currency, DayCounter, LedgerEntry
from apps.economy.services import fuel
from apps.economy.services.batch import BatchState
from apps.economy.services.ops.spending import open_trip
from apps.economy.services.payloads import STR, UUID, Field
from apps.economy.services.sync import Ctx, Rejected, register
from apps.progress.models import TripRun


@register(
    "ad_reward",
    payload={"ad_placement": Field(STR, max_length=32), "ref": Field(UUID, required=False)},
)
def ad_reward(state: BatchState, ctx: Ctx) -> None:
    placement = ctx.payload["ad_placement"]
    if placement == "result_double":
        _result_double(state, ctx)
    elif placement == "fuel_refill":
        _fuel_refill(state, ctx)
    elif placement == "trip_revive":
        session = open_trip(state, ctx.payload.get("ref"))
        if session.open_revived:
            raise Rejected("already_revived")
        session.open_revived = True
        state.set_session(session)
    elif placement == "traffic_jam":
        session = open_trip(state, ctx.payload.get("ref"))
        if session.open_traffic_jam_ads >= state.settings.traffic_jam_ads_per_trip:
            raise Rejected("cap_reached")
        session.open_traffic_jam_ads += 1
        state.set_session(session)
    elif placement == "morning_piggy":
        raise Rejected("server_only")
    else:
        raise Rejected("unknown_sku")


def _result_double(state: BatchState, ctx: Ctx) -> None:
    session = state.session()
    ref = ctx.payload.get("ref")
    if ref is None or session.last_start != ref:
        raise Rejected("no_result")
    if session.last_outcome != TripRun.Outcome.FINISHED or session.last_earnings == 0:
        raise Rejected("not_doublable")
    if session.last_doubled:
        raise Rejected("already_doubled")
    state.credit(
        Currency.JENEHAT,
        session.last_earnings,
        LedgerEntry.Reason.AD_RESULT_DOUBLE,
        ref_type="trip",
        ref_id=str(ref),
    )
    session.last_doubled = True
    state.set_session(session)


def _fuel_refill(state: BatchState, ctx: Ctx) -> None:
    size = state.tank_size(ctx.t)
    tank = fuel.regenerate(state.fuel_state(), ctx.t_ms, max_liters=size, regen_ms=state.regen_ms)
    filled = fuel.fill_to_max(tank, ctx.t_ms, max_liters=size)
    if filled is None:
        raise Rejected("tank_full")
    if state.counter(DayCounter.Kind.FUEL_REFILL_AD, ctx.t) >= state.settings.fuel_refill_daily_cap:
        raise Rejected("cap_reached")
    state.set_fuel(filled)
    state.bump_counter(DayCounter.Kind.FUEL_REFILL_AD, ctx.t)
