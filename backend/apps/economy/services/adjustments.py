"""Staff balance adjustments (contracts/admin.md "Adjusting a balance", research R19).

The only way staff change a balance: one `admin_adjustment` ledger entry and one `WalletAdjustment`
naming who, how much and why, in one transaction. `state_version` moves, so a phone with an older
snapshot is told to refresh. There is no path between currencies or players.
"""

from __future__ import annotations

import uuid

from django.db import transaction
from django.utils import timezone

from apps.accounts.models import Player, User
from apps.common.ids import uuid7
from apps.economy.models import Currency, LedgerEntry, WalletAdjustment
from apps.economy.services import ledger

MAX_REASON_LENGTH = 200


class AdjustmentRefused(ValueError):
    """The adjustment breaks a rule. The message is for the staff user."""


def adjust(
    player: Player,
    currency: str,
    delta: int,
    reason: str,
    actor: User,
    *,
    record_id: uuid.UUID | None = None,
) -> WalletAdjustment:
    """`record_id` is the form's one-time token: an adjustment sent twice with it is applied once,
    and the second call returns the first record."""
    if currency not in (Currency.JENEHAT, Currency.BONAT):
        raise AdjustmentRefused("Only JENEHAT and BONAT can be adjusted.")
    if type(delta) is not int or delta == 0:
        raise AdjustmentRefused("The amount must be a non-zero whole number.")
    reason = reason.strip()
    if not reason or len(reason) > MAX_REASON_LENGTH:
        raise AdjustmentRefused(f"A reason of 1 to {MAX_REASON_LENGTH} characters is required.")
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        # After the lock, so a second submit of the same form waits for the first and sees it.
        if record_id is not None:
            done: WalletAdjustment | None = WalletAdjustment.objects.filter(pk=record_id).first()
            if done is not None:
                if done.player_id != player.pk:
                    raise AdjustmentRefused("This form was already used for another player.")
                return done
        balance = wallet.jenehat if currency == Currency.JENEHAT else wallet.bonat
        if balance + delta < 0:
            raise AdjustmentRefused(f"The balance would go below 0 ({balance} {delta:+d}).")
        record_id = record_id or uuid7()
        entry = ledger.apply_now(
            wallet,
            currency=currency,
            delta=delta,
            reason=LedgerEntry.Reason.ADMIN_ADJUSTMENT,
            source=LedgerEntry.Source.ADMIN,
            ref_type="adjustment",
            ref_id=str(record_id),
        )
        wallet.state_version += 1
        wallet.save(update_fields=["state_version", "updated_at"])
        return WalletAdjustment.objects.create(
            id=record_id,
            actor=actor,
            player=player,
            currency=currency,
            delta=delta,
            reason=reason,
            ledger_entry=entry,
            at=timezone.now(),
        )
