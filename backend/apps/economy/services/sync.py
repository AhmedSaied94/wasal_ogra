"""`POST /v1/sync`: one batch of operations, applied in order in one transaction (research R5,
contracts/operations.md "Order of checks common to every operation").

The wallet row is locked first, so a player's batches never interleave. Each operation's outcome
is stored by its `client_txn_id`, so sending the same batch again returns the same answers and
applies nothing. A rejected operation changes nothing and doesn't stop the batch.

Operation handlers register here with `register`. A handler is a function of the batch state and
the operation's context: it validates first and changes last, through the state's methods only,
and raises `Rejected(reason)` before any change.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any

from django.db import transaction
from django.utils import timezone

from apps.accounts.models import Player
from apps.content.services import lookups
from apps.economy.models import PlayerFlag, ProcessedOp
from apps.economy.services import flags, ledger, settings
from apps.economy.services.batch import BatchState, Outcome, PackView
from apps.economy.services.payloads import Field, PayloadError, PayloadSpec, maybe_uuid, validate
from apps.economy.services.timeline import effective, from_ms, to_ms

ACCEPTED = ProcessedOp.Status.ACCEPTED
REJECTED = ProcessedOp.Status.REJECTED
MAX_OPS = 100
# The keys whose value names an earlier operation (the dependency rule, research R5).
REFERENCE_KEYS = ("trip_start_txn", "ref")
DAY_MS = 86_400_000


# contracts/operations.md "Reasons". Additive only: a phone treats an unknown one as a generic
# rejection (contracts/api.md "Versioning").
REASONS = (
    "validation_error",
    "unknown_op_type",
    "op_expired",
    "unknown_content_version",
    "content_version_unsupported",
    "dependency_rejected",
    "unknown_trip",
    "unknown_sku",
    "unknown_variant",
    "not_for_sale",
    "price_mismatch",
    "not_unlocked",
    "already_owned",
    "already_revived",
    "already_doubled",
    "already_granted",
    "result_exists",
    "insufficient_funds",
    "tank_full",
    "none_left",
    "no_trip",
    "no_trip_start",
    "no_result",
    "not_doublable",
    "trip_mismatch",
    "stars_out_of_bounds",
    "earnings_out_of_bounds",
    "duration_out_of_bounds",
    "cap_reached",
    "not_eligible",
    "server_only",
)


class Rejected(Exception):
    """The operation is refused with `reason` (contracts/operations.md "Reasons")."""

    def __init__(self, reason: str, details: Mapping[str, Any] | None = None) -> None:
        if reason not in REASONS:
            raise ValueError(f"{reason!r} is not a reason of contracts/operations.md")
        super().__init__(reason)
        self.reason = reason
        self.details = details


@dataclass(frozen=True)
class Op:
    """One operation's envelope, as the serializer validated it."""

    client_txn_id: uuid.UUID
    op_type: str
    occurred_at: datetime
    payload: Mapping[str, Any]


@dataclass(frozen=True)
class Ctx:
    """What a handler gets besides the state: the operation, its clean payload, its effective
    time, and the pack of its declared `content_version` (when it declares one)."""

    client_txn_id: uuid.UUID
    op_type: str
    occurred_at: datetime
    t: datetime
    payload: Mapping[str, Any]
    pack: PackView | None = None

    @property
    def t_ms(self) -> int:
        return to_ms(self.t)

    def pack_view(self) -> PackView:
        """The declared version's pack, for a handler registered with `content_version=True`."""
        if self.pack is None:
            raise RuntimeError(f"{self.op_type} reads the pack but declares no content_version")
        return self.pack


Granted = Sequence[Mapping[str, Any]]
Handler = Callable[[BatchState, Ctx], Granted | None]


@dataclass(frozen=True)
class Registration:
    handler: Handler
    payload: PayloadSpec
    content_version: bool


@dataclass(frozen=True)
class OpResult:
    client_txn_id: uuid.UUID
    outcome: Outcome


@dataclass(frozen=True)
class BatchResult:
    state_version: int
    state_stale: bool
    results: list[OpResult]
    wallet: dict[str, Any] = field(default_factory=dict)


_registry: dict[str, Registration] = {}


def register(
    op_type: str, *, payload: PayloadSpec, content_version: bool = False
) -> Callable[[Handler], Handler]:
    """Decorator: `@register("trip_start", payload={...}, content_version=True)`."""
    if content_version and "content_version" not in payload:
        raise ValueError(f"{op_type} declares a content_version its payload lacks")

    def decorator(handler: Handler) -> Handler:
        if op_type in _registry:
            raise ValueError(f"operation {op_type!r} is registered twice")
        _registry[op_type] = Registration(handler, payload, content_version)
        return handler

    return decorator


def registered() -> dict[str, Registration]:
    return dict(_registry)


def unregister(op_type: str) -> None:
    """For tests only."""
    _registry.pop(op_type, None)


CONTENT_VERSION = Field("int", minimum=1)


def process_batch(
    player: Player,
    base_state_version: int,
    ops: Sequence[Op],
    *,
    client_version: str = "",
) -> BatchResult:
    """Apply `ops` in order for `player`, in one transaction under the wallet's lock."""
    if len(ops) > MAX_OPS:
        raise ValueError("a batch holds at most 100 operations")
    # Whole milliseconds, like every time the economy keeps (contracts/fuel.md).
    now = from_ms(to_ms(timezone.now()))
    with transaction.atomic():
        wallet = ledger.lock_wallet(player, now=now)
        before = wallet.state_version
        referenced = {
            ref
            for op in ops
            for key in REFERENCE_KEYS
            if (ref := maybe_uuid(op.payload.get(key))) is not None
        }
        ids = {op.client_txn_id for op in ops} | referenced
        state = BatchState(
            player,
            wallet,
            now=now,
            settings=settings.current(),
            processed=ProcessedOp.objects.filter(player=player, client_txn_id__in=ids),
            referenced=referenced,
            client_version=client_version,
        )
        results = [OpResult(op.client_txn_id, _apply(state, op)) for op in ops]
        state.flush()
        answer = state.wallet_answer()
    return BatchResult(
        state_version=state.state_version,
        state_stale=base_state_version != before,
        results=results,
        wallet=answer,
    )


def payload_hash(payload: Mapping[str, Any]) -> str:
    """sha256 of the canonical payload: spots a repeat with another payload (research R5)."""
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))  # ASCII: always encodes
    return hashlib.sha256(canonical.encode()).hexdigest()


def _apply(state: BatchState, op: Op) -> Outcome:
    digest = payload_hash(op.payload)
    known = state.recorded(op.client_txn_id)
    if known is not None:
        if known.op_type != op.op_type or known.payload_hash != digest:
            flags.raise_flag(
                state,
                PlayerFlag.Kind.TXN_PAYLOAD_MISMATCH,
                {"client_txn_id": str(op.client_txn_id)},
            )
        return known.outcome
    outcome = _outcome(state, op)
    state.record(op.client_txn_id, op.op_type, digest, outcome)
    return outcome


def _outcome(state: BatchState, op: Op) -> Outcome:
    if _expired(op.client_txn_id, state):
        return Outcome(REJECTED, "op_expired")
    registration = _registry.get(op.op_type)
    if registration is None:
        return Outcome(REJECTED, "unknown_op_type")
    try:
        payload = validate(registration.payload, op.payload)
    except PayloadError as error:
        return Outcome(REJECTED, "validation_error", details={"field": error.field})
    pack = None
    if registration.content_version:
        version = payload["content_version"]
        status = state.version_status(version)
        if status == lookups.UNKNOWN:
            return Outcome(REJECTED, "unknown_content_version")
        if status == lookups.UNSUPPORTED:
            return Outcome(REJECTED, "content_version_unsupported")
        pack = state.pack(version)
    t = from_ms(to_ms(effective(op.occurred_at, state.timeline_at, state.now)))
    ctx = Ctx(op.client_txn_id, op.op_type, op.occurred_at, t, payload, pack)
    state.begin(op.client_txn_id)
    before = state.mutations
    try:
        granted = registration.handler(state, ctx) or ()
    except Rejected as rejected:
        if state.mutations != before:
            raise RuntimeError(f"{op.op_type} changed the state and then rejected") from rejected
        return Outcome(REJECTED, rejected.reason, details=rejected.details)
    state.advance_timeline(t)
    moved = abs(t - op.occurred_at)
    if moved > timedelta(minutes=state.settings.clock_clamp_flag_minutes):
        flags.raise_flag(
            state,
            PlayerFlag.Kind.CLOCK_CLAMPED,
            {"moved_ms": moved // timedelta(milliseconds=1)},
            at=t,
        )
    return Outcome(ACCEPTED, granted=tuple(dict(g) for g in granted))


def _expired(client_txn_id: uuid.UUID, state: BatchState) -> bool:
    """A UUIDv7 carries its creation time in its first 48 bits (research R11)."""
    created_ms = client_txn_id.int >> 80
    oldest = state.now_ms - state.settings.op_retention_days * DAY_MS
    return created_ms < oldest or created_ms > state.now_ms + DAY_MS
