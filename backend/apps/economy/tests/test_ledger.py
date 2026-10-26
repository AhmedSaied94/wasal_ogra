"""The one writer of a balance (research R4, spec FR-005-FR-007, FR-011)."""

from __future__ import annotations

import pytest
from django.db import IntegrityError, connection, transaction

from apps.accounts.models import Player
from apps.economy.models import AppendOnlyError, Currency, LedgerEntry, Wallet
from apps.economy.services import ledger
from apps.economy.tests.helpers import ledger_sum

pytestmark = pytest.mark.django_db

Reason = LedgerEntry.Reason
Source = LedgerEntry.Source


def credit(wallet: Wallet, amount: int, currency: str = Currency.JENEHAT) -> LedgerEntry:
    return ledger.apply_now(
        wallet,
        currency=currency,
        delta=amount,
        reason=Reason.TRIP_EARNINGS,
        source=Source.CLIENT_OP,
    )


def test_lock_wallet_creates_the_starting_wallet_once(player: Player) -> None:
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
    assert (wallet.jenehat, wallet.bonat, wallet.fuel, wallet.state_version) == (0, 0, 5, 0)
    assert wallet.fuel_updated_at == wallet.timeline_at == wallet.last_active_at
    assert wallet.fuel_unlimited_until is None
    with transaction.atomic():
        again = ledger.lock_wallet(player)
    assert again.pk == wallet.pk
    assert Wallet.objects.filter(pk=player.pk).count() == 1


def test_apply_entry_appends_one_entry_and_moves_the_balance(player: Player) -> None:
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        entry = credit(wallet, 46)
        spent = ledger.apply_now(
            wallet,
            currency=Currency.JENEHAT,
            delta=-6,
            reason=Reason.ITEM_PURCHASE,
            source=Source.CLIENT_OP,
            ref_type="sku",
            ref_id="salon.nish",
        )
    stored = Wallet.objects.get(pk=player.pk)
    assert stored.jenehat == 40
    assert (entry.delta, entry.balance_after) == (46, 46)
    assert (spent.delta, spent.balance_after, spent.ref_id) == (-6, 40, "salon.nish")
    assert ledger_sum(player, Currency.JENEHAT) == stored.jenehat
    assert LedgerEntry.objects.filter(player=player).count() == 2


def test_bonat_moves_its_own_balance(player: Player) -> None:
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        credit(wallet, 12, Currency.BONAT)
    stored = Wallet.objects.get(pk=player.pk)
    assert (stored.jenehat, stored.bonat) == (0, 12)


def test_a_delta_below_zero_raises_and_writes_nothing(player: Player) -> None:
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        credit(wallet, 5)
        entries: list[LedgerEntry] = []
        with pytest.raises(ledger.InsufficientFunds):
            ledger.apply_entry(
                wallet,
                entries,
                currency=Currency.JENEHAT,
                delta=-6,
                reason=Reason.ITEM_PURCHASE,
                source=Source.CLIENT_OP,
            )
        assert entries == []
        assert wallet.jenehat == 5
    assert Wallet.objects.get(pk=player.pk).jenehat == 5
    assert LedgerEntry.objects.filter(player=player).count() == 1


@pytest.mark.parametrize("delta", [0, True, 1.0])
def test_a_zero_or_non_integer_delta_is_refused(player: Player, delta: object) -> None:
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        with pytest.raises(ledger.LedgerMisuse):
            ledger.apply_now(
                wallet,
                currency=Currency.JENEHAT,
                delta=delta,  # type: ignore[arg-type]
                reason=Reason.TRIP_EARNINGS,
                source=Source.CLIENT_OP,
            )


def test_an_unknown_currency_is_refused(player: Player) -> None:
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        with pytest.raises(ledger.LedgerMisuse, match="currency"):
            credit(wallet, 1, "FUEL")


def test_the_database_refuses_a_zero_entry(player: Player) -> None:
    with transaction.atomic():
        ledger.lock_wallet(player)
    with pytest.raises(IntegrityError), transaction.atomic():
        LedgerEntry.objects.bulk_create(
            [
                LedgerEntry(
                    player=player,
                    currency=Currency.JENEHAT,
                    delta=0,
                    balance_after=0,
                    reason=Reason.TRIP_EARNINGS,
                    source=Source.CLIENT_OP,
                )
            ]
        )


def test_a_wallet_not_from_lock_wallet_is_refused(player: Player) -> None:
    with transaction.atomic():
        ledger.lock_wallet(player)
        plain = Wallet.objects.get(pk=player.pk)
        with pytest.raises(ledger.LedgerMisuse, match="lock_wallet"):
            credit(plain, 1)
        with pytest.raises(ledger.LedgerMisuse, match="lock_wallet"):
            ledger.flush_entries(plain, [LedgerEntry()])


@pytest.mark.django_db(transaction=True)
def test_the_ledger_needs_an_open_transaction(player: Player) -> None:
    with pytest.raises(ledger.LedgerMisuse, match="transaction"):
        ledger.lock_wallet(player)
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
    assert not connection.in_atomic_block
    with pytest.raises(ledger.LedgerMisuse, match="transaction"):
        credit(wallet, 1)
    with pytest.raises(ledger.LedgerMisuse, match="transaction"):
        ledger.flush_entries(wallet, [LedgerEntry()])


def test_flushing_nothing_writes_nothing(player: Player) -> None:
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        ledger.flush_entries(wallet, [])
    assert LedgerEntry.objects.count() == 0


def test_ledger_entries_are_append_only(player: Player) -> None:
    with transaction.atomic():
        entry = credit(ledger.lock_wallet(player), 3)
    stored = LedgerEntry.objects.get(pk=entry.pk)
    stored.delta = 300
    with pytest.raises(AppendOnlyError):
        stored.save()
    with pytest.raises(AppendOnlyError):
        stored.delete()
    with pytest.raises(AppendOnlyError):
        LedgerEntry.objects.filter(pk=entry.pk).update(delta=300)
    with pytest.raises(AppendOnlyError):
        LedgerEntry.objects.filter(pk=entry.pk).delete()
    assert LedgerEntry.objects.get(pk=entry.pk).delta == 3


@pytest.mark.parametrize(
    "statement",
    [
        "UPDATE economy_wallet SET jenehat = %s WHERE player_id = %s",
        "UPDATE economy_wallet SET bonat = %s WHERE player_id = %s",
        "UPDATE economy_wallet SET fuel = %s WHERE player_id = %s",
    ],
    ids=["jenehat", "bonat", "fuel"],
)
def test_the_database_refuses_a_negative_balance(player: Player, statement: str) -> None:
    with transaction.atomic():
        ledger.lock_wallet(player)
    with pytest.raises(IntegrityError), transaction.atomic(), connection.cursor() as cursor:
        cursor.execute(statement, [-1, player.pk])


def test_a_concurrent_first_use_creates_one_wallet(player: Player) -> None:
    """The insert ignores a conflict: a wallet created meanwhile is the one locked."""
    from django.utils import timezone

    now = timezone.now()
    Wallet.objects.create(
        player=player,
        fuel=2,
        fuel_updated_at=now,
        timeline_at=now,
        last_active_at=now,
        session_started_at=now,
    )
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
    assert wallet.fuel == 2
