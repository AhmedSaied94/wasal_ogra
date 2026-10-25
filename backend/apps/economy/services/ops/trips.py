"""`trip_start` and `trip_result` (contracts/operations.md, research R5 to R7).

A start opens the trip with the bounds of the declared pack's trip, so its result is checked
against what the phone was shown. The economy checks bounds only: the engine decided the result
(constitution I).
"""

from __future__ import annotations

import json
import uuid
from typing import Any

from apps.economy.models import Currency, DayCounter, LedgerEntry, PlayerFlag
from apps.economy.services import flags, fuel
from apps.economy.services.batch import BatchState, ProgressRow, Run, SessionRow
from apps.economy.services.ops.story import pay_completions
from apps.economy.services.payloads import (
    BOOL,
    INT,
    INT32_MAX,
    OBJECT,
    STR,
    UUID,
    Field,
    PayloadError,
    is_text,
    validate,
)
from apps.economy.services.sync import CONTENT_VERSION, REJECTED, Ctx, Rejected, register
from apps.progress.models import TripRun
from apps.progress.services import unlocks

FINISHED = TripRun.Outcome.FINISHED
ABANDONED = TripRun.Outcome.ABANDONED
MAX_STARS = 3
RESULT_MAX_BYTES = 8 * 1024
HASH_LENGTH = 64
BOOSTER_ID_LENGTH = 32

# The keys of M01's `TripResult` the server reads; the others are ignored.
_RESULT = {
    "trip_id": Field(STR, max_length=40),
    "rev": Field(INT, minimum=0, maximum=INT32_MAX),
    "outcome": Field(STR, choices=tuple(TripRun.Outcome.values)),
    "stars": Field(INT),
    "earnings_jenehat": Field(INT),
    "fights": Field(INT, minimum=0, maximum=INT32_MAX),
    "duration_ms": Field(INT, minimum=0),
    "revived": Field(BOOL),
    "command_log_hash": Field(STR, max_length=HASH_LENGTH),
}


def _result(value: dict[str, Any]) -> dict[str, Any]:
    """The read keys of a result, checked; the result itself is at most 8 KB."""
    encoded = json.dumps(value, separators=(",", ":")).encode()  # ASCII: any string encodes
    if len(encoded) > RESULT_MAX_BYTES:
        raise PayloadError("result")
    try:
        cleaned = validate(_RESULT, {key: value[key] for key in _RESULT if key in value})
    except PayloadError as error:
        raise PayloadError(f"result.{error.field}") from None
    mistakes = value.get("mistakes")
    if not isinstance(mistakes, list):
        raise PayloadError("result.mistakes")
    boosters = value.get("boosters_used")
    if not isinstance(boosters, list) or not all(is_text(b, BOOSTER_ID_LENGTH) for b in boosters):
        raise PayloadError("result.boosters_used")
    return {**cleaned, "mistakes_count": len(mistakes), "boosters_used": tuple(boosters)}


@register(
    "trip_start",
    payload={
        "trip_id": Field(STR, max_length=40),
        "content_version": CONTENT_VERSION,
        "fuel_mode": Field(STR, max_length=16),
    },
    content_version=True,
)
def trip_start(state: BatchState, ctx: Ctx) -> None:
    pack = ctx.pack_view()
    trip_id, mode = ctx.payload["trip_id"], ctx.payload["fuel_mode"]
    bounds = pack.trips.get(trip_id)
    if bounds is None:
        raise Rejected("unknown_trip")
    if mode == fuel.UNLIMITED:
        if not fuel.is_unlimited(state.fuel_state(), ctx.t_ms):
            raise Rejected("not_eligible")
    elif mode != fuel.FUEL:
        raise Rejected("not_eligible")  # challenge: B08
    if not unlocks.trip_unlocked(pack.rules, state.player_view(), trip_id):
        raise Rejected("not_unlocked")
    started = fuel.start(
        state.fuel_state(),
        ctx.t_ms,
        mode=mode,
        max_liters=state.tank_size(ctx.t),
        regen_ms=state.regen_ms,
        overdrafts_today=state.counter(DayCounter.Kind.OVERDRAFT, ctx.t),
        overdraft_cap=state.settings.fuel_overdraft_per_day,
    )
    if started.reason:
        raise Rejected(started.reason)

    _abandon_open(state)
    state.set_fuel(started.state)
    if started.overdraft:
        state.bump_counter(DayCounter.Kind.OVERDRAFT, ctx.t)
        flags.raise_flag(
            state, PlayerFlag.Kind.FUEL_OVERDRAFT, {"start": str(ctx.client_txn_id)}, at=ctx.t
        )
    started_today = state.bump_counter(DayCounter.Kind.TRIPS_STARTED, ctx.t)
    if started_today > state.settings.trips_per_day_flag:
        flags.raise_flag(
            state, PlayerFlag.Kind.TRIP_RATE, {"started_today": started_today}, at=ctx.t
        )
    session = state.session()
    state.set_session(
        SessionRow(
            open_start=ctx.client_txn_id,
            open_trip_id=trip_id,
            open_rev=bounds.rev,
            open_content_version=pack.version,
            open_max_earnings=bounds.max_earnings_jenehat,
            open_last_station_ms=bounds.last_station_at_s * 1000,
            open_started_at=ctx.t,
            last_start=session.last_start,
            last_outcome=session.last_outcome,
            last_earnings=session.last_earnings,
            last_doubled=session.last_doubled,
        )
    )


def _abandon_open(state: BatchState) -> None:
    """A start with no result is closed by the next start: it counts as a play, of nothing."""
    session = state.session()
    if session.open_start is None:
        return
    state.add_run(
        Run(
            trip_id=session.open_trip_id,
            rev=session.open_rev,
            start_op=session.open_start,
            outcome=ABANDONED,
            content_version=session.open_content_version,
        )
    )
    progress = state.progress(session.open_trip_id)
    progress.plays += 1
    state.set_progress(session.open_trip_id, progress)


@register(
    "trip_result",
    payload={"trip_start_txn": Field(UUID), "result": Field(OBJECT, check=_result)},
)
def trip_result(state: BatchState, ctx: Ctx) -> list[dict[str, Any]]:
    start: uuid.UUID = ctx.payload["trip_start_txn"]
    result: dict[str, Any] = ctx.payload["result"]
    if state.status_of(start) == REJECTED:
        raise Rejected("dependency_rejected")
    if state.run_exists(start):
        raise Rejected("result_exists")
    session = state.session()
    if session.open_start != start:
        raise Rejected("no_trip_start")
    if result["trip_id"] != session.open_trip_id:
        raise Rejected("trip_mismatch")
    finished = result["outcome"] == FINISHED
    stars, earnings = result["stars"], result["earnings_jenehat"]
    if not 0 <= stars <= MAX_STARS or (not finished and stars != 0):
        raise Rejected("stars_out_of_bounds")
    if not 0 <= earnings <= session.open_max_earnings or (not finished and earnings != 0):
        raise Rejected("earnings_out_of_bounds")
    minimum_percent = state.settings.min_duration_percent
    if finished and result["duration_ms"] * 100 < minimum_percent * session.open_last_station_ms:
        raise Rejected("duration_out_of_bounds")

    last_station_ms = session.open_last_station_ms
    if (
        finished
        and stars == MAX_STARS
        and result["duration_ms"] * 100 < state.settings.fast_run_percent * last_station_ms
    ):
        flags.raise_flag(
            state,
            PlayerFlag.Kind.FAST_THREE_STAR,
            {
                "start": str(start),
                "duration_ms": result["duration_ms"],
                "last_station_ms": last_station_ms,
            },
            at=ctx.t,
        )
    state.credit(
        Currency.JENEHAT,
        earnings,
        LedgerEntry.Reason.TRIP_EARNINGS,
        ref_type="trip",
        ref_id=str(start),
    )
    state.set_progress(session.open_trip_id, _progressed(state, session, result, ctx))
    state.add_run(
        Run(
            trip_id=session.open_trip_id,
            rev=result["rev"],
            start_op=start,
            outcome=result["outcome"],
            content_version=session.open_content_version,
            stars=stars,
            fights=result["fights"],
            mistakes_count=result["mistakes_count"],
            earnings_jenehat=earnings,
            duration_ms=result["duration_ms"],
            revived=result["revived"],
            boosters_used=result["boosters_used"],
            command_log_hash=result["command_log_hash"],
        )
    )
    state.set_session(
        SessionRow(
            last_start=start,
            last_outcome=result["outcome"],
            last_earnings=earnings,
            last_doubled=False,
        )
    )
    # The rules of the pack the trip was started on: what the phone was shown. A version retired
    # since has none, and what this result completes is paid by the next trip or purchase.
    rules = state.pack(session.open_content_version).rules
    return pay_completions(state, rules, ctx.t) if rules else []


def _progressed(
    state: BatchState, session: SessionRow, result: dict[str, Any], ctx: Ctx
) -> ProgressRow:
    """`plays` + 1; for a finished trip, the best stars, the best time of runs with a star, and
    the first completion."""
    row = state.progress(session.open_trip_id)
    row.plays += 1
    if result["outcome"] != FINISHED:
        return row
    row.best_stars = max(row.best_stars, result["stars"])
    duration = result["duration_ms"]
    if result["stars"] >= 1 and (row.best_time_ms is None or duration < row.best_time_ms):
        row.best_time_ms = duration
    if row.first_completed_at is None:
        row.first_completed_at = ctx.t
    return row
