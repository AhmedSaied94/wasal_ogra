"""The one writer of a balance (FR-005, FR-009, research R4).

Every change of `Wallet.jenehat` or `Wallet.bonat` goes through `apply_entry`, which appends a
`LedgerEntry` for it, and every write of those two columns and of ledger rows goes through
`flush_entries`. Nothing else in the backend may do either: `test_balance_writers.py` scans for it,
the database refuses a negative balance, and the restore drill checks `wallet == sum(ledger)`.

Later features grant the same way: B06 purchases, B07 ad callbacks, B08 challenge rewards. Lock the
wallet with `lock_wallet` inside an atomic block, then `apply_now` (or, during a sync batch,
`apply_entry` and one `flush_entries` at the end).
"""

from __future__ import annotations

import uuid
from datetime import datetime

from django.db import connection
from django.utils import timezone

from apps.accounts.models import Player
from apps.economy.models import Currency, LedgerEntry, Wallet
from apps.economy.services import entitlements, settings

# Set on a wallet by `lock_wallet`: the instance holds the row lock of the current transaction.
_LOCKED = "_ledger_locked"


class InsufficientFunds(Exception):
    """The entry would take the balance below 0. Nothing was changed."""


class LedgerMisuse(RuntimeError):
    """A programming error: the wallet isn't locked, or no transaction is open."""


def create_wallet(player: Player, *, now: datetime | None = None) -> None:
    """Create the player's wallet if it doesn't exist: a full tank, 0 JENEHAT, 0 BONAT and
    `state_version` 0, every time at `now` (FR-011). Takes no lock."""
    at = now or timezone.now()
    fuel_max = entitlements.tank_size(player, at, settings.current())
    Wallet.objects.bulk_create(
        [
            Wallet(
                player=player,
                fuel=fuel_max,
                fuel_updated_at=at,
                timeline_at=at,
                last_active_at=at,
                session_started_at=at,
            )
        ],
        ignore_conflicts=True,  # another request created it first
    )


def lock_wallet(player: Player, *, now: datetime | None = None) -> Wallet:
    """The player's wallet, locked `FOR UPDATE` until the transaction ends, created on first use."""
    _require_transaction()
    wallet = Wallet.objects.select_for_update().filter(pk=player.pk).first()
    if wallet is None:
        create_wallet(player, now=now)
        wallet = Wallet.objects.select_for_update().get(pk=player.pk)
    setattr(wallet, _LOCKED, True)
    return wallet


def apply_entry(
    wallet: Wallet,
    entries: list[LedgerEntry],
    *,
    currency: str,
    delta: int,
    reason: str,
    source: str,
    ref_type: str = "",
    ref_id: str = "",
    op_id: uuid.UUID | None = None,
) -> LedgerEntry:
    """Move the in-memory balance by `delta` and queue its entry on `entries`. `flush_entries`
    writes both. Raises `InsufficientFunds`, changing nothing, if the balance would go below 0."""
    _require_transaction()
    if not getattr(wallet, _LOCKED, False):
        raise LedgerMisuse("apply_entry needs the wallet from lock_wallet")
    if type(delta) is not int or delta == 0:
        raise LedgerMisuse("a ledger entry moves a balance by a non-zero integer")
    if currency == Currency.JENEHAT:
        balance = wallet.jenehat + delta
    elif currency == Currency.BONAT:
        balance = wallet.bonat + delta
    else:
        raise LedgerMisuse(f"unknown currency {currency!r}")
    if balance < 0:
        raise InsufficientFunds(currency)
    if currency == Currency.JENEHAT:
        wallet.jenehat = balance
    else:
        wallet.bonat = balance
    entry = LedgerEntry(
        player_id=wallet.player_id,
        currency=currency,
        delta=delta,
        balance_after=balance,
        reason=reason,
        ref_type=ref_type,
        ref_id=ref_id,
        op_id=op_id,
        source=source,
    )
    entries.append(entry)
    return entry


def flush_entries(wallet: Wallet, entries: list[LedgerEntry]) -> None:
    """Insert the queued entries and save the two balances, in the caller's transaction."""
    if not entries:
        return
    _require_transaction()
    if not getattr(wallet, _LOCKED, False):
        raise LedgerMisuse("flush_entries needs the wallet from lock_wallet")
    LedgerEntry.objects.bulk_create(entries)
    wallet.save(update_fields=["jenehat", "bonat", "updated_at"])
    entries.clear()


def apply_now(
    wallet: Wallet,
    *,
    currency: str,
    delta: int,
    reason: str,
    source: str,
    ref_type: str = "",
    ref_id: str = "",
    op_id: uuid.UUID | None = None,
) -> LedgerEntry:
    """`apply_entry` and `flush_entries` at once: one change outside a sync batch."""
    entries: list[LedgerEntry] = []
    entry = apply_entry(
        wallet,
        entries,
        currency=currency,
        delta=delta,
        reason=reason,
        source=source,
        ref_type=ref_type,
        ref_id=ref_id,
        op_id=op_id,
    )
    flush_entries(wallet, entries)
    return entry


def _require_transaction() -> None:
    if not connection.in_atomic_block:
        raise LedgerMisuse("the ledger is written only inside a transaction")
