"""Operation envelopes, batches and wallet reads for the economy tests (B03 tasks.md T005)."""

from __future__ import annotations

import secrets
import uuid
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

from django.db import transaction
from django.db.models import Sum
from django.test import Client
from django.utils import timezone

from apps.accounts.models import Player
from apps.accounts.tests.factories import sign_in
from apps.economy.models import GrantRecord, LedgerEntry, Wallet
from apps.economy.services import ledger
from apps.economy.services.sync import BatchResult, Op, process_batch
from apps.economy.services.timeline import to_ms
from apps.progress.models import Ownership, TripProgress

HEADERS = {"x-client-version": "1.0.0+1", "x-platform": "android"}
SYNC = "/v1/sync"
BOOTSTRAP = "/v1/bootstrap"
STATE = "/v1/state"


def uuid7_at(instant: datetime) -> uuid.UUID:
    """A UUIDv7 whose embedded time is `instant`. The app makes its ids at the moment of the
    intent; `apps.common.ids.uuid7` reads the real clock, which time-machine doesn't move."""
    ms = to_ms(instant)
    rand = int.from_bytes(secrets.token_bytes(10), "big")
    value = (ms & ((1 << 48) - 1)) << 80
    value |= 0x7 << 76  # version 7
    value |= ((rand >> 62) & 0xFFF) << 64  # rand_a
    value |= 0b10 << 62  # RFC 4122 variant
    value |= rand & ((1 << 62) - 1)  # rand_b
    return uuid.UUID(int=value)


def iso(instant: datetime) -> str:
    return instant.astimezone(UTC).isoformat().replace("+00:00", "Z")


def op(
    op_type: str,
    payload: dict[str, Any],
    *,
    at: datetime | None = None,
    txn: uuid.UUID | str | None = None,
) -> dict[str, Any]:
    """One envelope, as M06 sends it: a fresh UUIDv7 made at `at`, and `occurred_at` = `at`."""
    when = at or timezone.now()
    return {
        "client_txn_id": str(txn or uuid7_at(when)),
        "op_type": op_type,
        "occurred_at": iso(when),
        "payload": payload,
    }


def batch(*ops: dict[str, Any], base: int = 0) -> dict[str, Any]:
    return {"base_state_version": base, "ops": list(ops)}


def as_ops(envelopes: Iterable[dict[str, Any]]) -> list[Op]:
    """Envelopes as `process_batch` takes them, without the API."""
    return [
        Op(
            client_txn_id=uuid.UUID(e["client_txn_id"]),
            op_type=e["op_type"],
            occurred_at=datetime.fromisoformat(e["occurred_at"]),
            payload=e["payload"],
        )
        for e in envelopes
    ]


def run(player: Player, *envelopes: dict[str, Any], base: int = 0) -> BatchResult:
    """`process_batch` on envelopes, as the API would call it."""
    return process_batch(player, base, as_ops(envelopes), client_version="1.0.0+1")


def reasons(result: BatchResult) -> list[str]:
    """Each operation's reason, or `accepted`."""
    return [r.outcome.reason or r.outcome.status for r in result.results]


def txn_of(envelope: dict[str, Any]) -> str:
    return str(envelope["client_txn_id"])


def wallet_of(player: Player | str | uuid.UUID) -> Wallet:
    return Wallet.objects.get(player_id=player.pk if isinstance(player, Player) else player)


def ledger_sum(player: Player | str | uuid.UUID, currency: str) -> int:
    pk = player.pk if isinstance(player, Player) else player
    total = LedgerEntry.objects.filter(player_id=pk, currency=currency).aggregate(s=Sum("delta"))
    return int(total["s"] or 0)


# -- a player's starting point ---------------------------------------------------------------------

# The sample pack: every regular trip of line_hay at a star completes chapter 1.
HAY_DONE = {"line_hay.01": 1, "line_hay.02": 3}
# What makes the salon's items purchasable: chapters 1 to 3 complete.
SALON_READY = (("vehicle", "micro_old"), ("chapter", "ch3_shabka"))


def grant(player: Player, currency: str, amount: int) -> None:
    """A balance to spend, through the ledger like any other (an admin adjustment)."""
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        ledger.apply_now(
            wallet,
            currency=currency,
            delta=amount,
            reason=LedgerEntry.Reason.ADMIN_ADJUSTMENT,
            source=LedgerEntry.Source.ADMIN,
        )


def give_stars(player: Player, stars: dict[str, int]) -> None:
    for trip_id, best in stars.items():
        TripProgress.objects.update_or_create(
            player=player, trip_id=trip_id, defaults={"best_stars": best, "plays": 1}
        )


def give(player: Player, *owned: tuple[str, str], variant: str = "") -> None:
    for kind, sku_id in owned:
        Ownership.objects.create(
            player=player, kind=kind, sku_id=sku_id, variant=variant, acquired_at=timezone.now()
        )


def ready_for_the_salon(player: Player) -> None:
    """Chapters 1 to 3 complete, and already rewarded, so a purchase pays nothing else."""
    give_stars(player, HAY_DONE)
    give(player, *SALON_READY)
    for chapter in ("ch1_first_job", "ch2_her_father", "ch3_shabka"):
        GrantRecord.objects.create(
            player=player, kind=GrantRecord.Kind.CHAPTER, key=chapter, granted_at=timezone.now()
        )


def granted_of(result: BatchResult, index: int = 0) -> list[dict[str, Any]]:
    return list(result.results[index].outcome.granted)


# -- operations ------------------------------------------------------------------------------------


def spend(kind: str, sku_id: str, price: int, version: int, **extra: Any) -> dict[str, Any]:
    currency_op = (
        "spend_jenehat" if kind in ("item", "vehicle", "chapter", "upgrade") else "spend_bonat"
    )
    payload = {"sku_kind": kind, "sku_id": sku_id, "price": price, "content_version": version}
    at = extra.pop("at", None)
    return op(extra.pop("op_type", currency_op), {**payload, **extra}, at=at)


def trip_start(
    trip_id: str, version: int, *, mode: str = "fuel", at: datetime | None = None
) -> dict[str, Any]:
    return op(
        "trip_start",
        {"trip_id": trip_id, "content_version": version, "fuel_mode": mode},
        at=at,
    )


def result_of(trip_id: str, **overrides: Any) -> dict[str, Any]:
    """M01's `TripResult.toJson()` for a finished 3-star trip, with `overrides`."""
    values: dict[str, Any] = {
        "trip_id": trip_id,
        "rev": 1,
        "outcome": "finished",
        "stars": 3,
        "star_flags": {"reached": True, "no_fights": True, "no_mistakes": True},
        "fares_collected_piasters": 2100,
        "overpaid_piasters": 0,
        "tips_piasters": 0,
        "earnings_jenehat": 10,
        "fights": 0,
        "lost_fares": 0,
        "missed_stops": 0,
        "impatient": 0,
        "caught_liars": 0,
        "mistakes": [],
        "reputation": 100,
        "reputation_lost": {},
        "duration_ms": 60_000,
        "boosters_used": [],
        "revived": False,
        "command_log_hash": "a" * 64,
    }
    values.update(overrides)
    return values


def trip_result(
    start: dict[str, Any] | str, trip_id: str, *, at: datetime | None = None, **overrides: Any
) -> dict[str, Any]:
    start_txn = start if isinstance(start, str) else txn_of(start)
    return op(
        "trip_result",
        {"trip_start_txn": start_txn, "result": result_of(trip_id, **overrides)},
        at=at,
    )


# -- the API ---------------------------------------------------------------------------------------


@dataclass
class Api:
    """A player signed in through `POST /v1/auth/anonymous`, calling B03's three endpoints."""

    client: Client
    player_id: str
    access: str
    headers: dict[str, str] = field(default_factory=dict)

    @property
    def player(self) -> Player:
        return Player.objects.get(pk=self.player_id)

    def sync(self, body: dict[str, Any], **headers: str) -> Any:
        return self.client.post(
            SYNC, data=body, content_type="application/json", headers={**self.headers, **headers}
        )

    def bootstrap(self, **headers: str) -> Any:
        return self.client.get(BOOTSTRAP, headers={**self.headers, **headers})

    def state(self, **headers: str) -> Any:
        return self.client.get(STATE, headers={**self.headers, **headers})


def signed_in_api() -> Api:
    client = Client()
    body = sign_in(client, uuid.uuid4(), headers=HEADERS).json()
    headers = {**HEADERS, "authorization": f"Bearer {body['access']}"}
    return Api(client, body["player_id"], body["access"], headers)
