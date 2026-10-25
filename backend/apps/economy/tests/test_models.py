"""The economy tables' constraints (B03 data-model.md "economy")."""

from __future__ import annotations

import uuid

import pytest
from django.db import IntegrityError, models, transaction
from django.utils import timezone

from apps.accounts.models import Player, User
from apps.common.checks import check_uuid7_primary_keys
from apps.common.ids import uuid7
from apps.economy.models import (
    AppendOnlyError,
    Currency,
    DayCounter,
    GrantRecord,
    Inventory,
    LedgerEntry,
    PlayerFlag,
    ProcessedOp,
    Wallet,
    WalletAdjustment,
)
from apps.economy.services import ledger

pytestmark = pytest.mark.django_db


def refused(make: object) -> None:
    with pytest.raises(IntegrityError), transaction.atomic():
        make()  # type: ignore[operator]


def test_a_processed_op_is_stored_once_per_player_and_id(player: Player) -> None:
    txn = uuid7()

    def make() -> ProcessedOp:
        return ProcessedOp.objects.create(
            player=player,
            client_txn_id=txn,
            op_type="trip_start",
            payload_hash="0" * 64,
            status="accepted",
            processed_at=timezone.now(),
        )

    make()
    refused(make)


def test_inventory_is_unique_per_booster(player: Player) -> None:
    Inventory.objects.create(player=player, booster_id="change_bag", count=1)
    refused(lambda: Inventory.objects.create(player=player, booster_id="change_bag", count=2))


def test_a_flag_is_one_row_per_kind_and_game_day(player: Player) -> None:
    today = timezone.now().date()
    PlayerFlag.objects.create(player=player, kind="fuel_overdraft", game_date=today)
    refused(
        lambda: PlayerFlag.objects.create(player=player, kind="fuel_overdraft", game_date=today)
    )
    PlayerFlag.objects.create(player=player, kind="trip_rate", game_date=today)


def test_a_day_counter_is_unique_per_day_and_kind(player: Player) -> None:
    today = timezone.now().date()
    DayCounter.objects.create(player=player, game_date=today, kind="overdraft", count=1)
    refused(lambda: DayCounter.objects.create(player=player, game_date=today, kind="overdraft"))


def test_a_grant_is_recorded_once(player: Player) -> None:
    now = timezone.now()
    GrantRecord.objects.create(player=player, kind="tutorial", key="", granted_at=now)
    refused(
        lambda: GrantRecord.objects.create(player=player, kind="tutorial", key="", granted_at=now)
    )


def test_wallet_adjustments_are_append_only(player: Player) -> None:
    actor = User.objects.create_user("ops1", is_staff=True)
    with transaction.atomic():
        entry = ledger.apply_now(
            ledger.lock_wallet(player),
            currency=Currency.BONAT,
            delta=10,
            reason=LedgerEntry.Reason.ADMIN_ADJUSTMENT,
            source=LedgerEntry.Source.ADMIN,
        )
    record = WalletAdjustment.objects.create(
        actor=actor,
        player=player,
        currency=Currency.BONAT,
        delta=10,
        reason="goodwill",
        ledger_entry=entry,
        at=timezone.now(),
    )
    record.reason = "changed"
    with pytest.raises(AppendOnlyError):
        record.save()
    with pytest.raises(AppendOnlyError):
        record.delete()
    with pytest.raises(AppendOnlyError):
        WalletAdjustment.objects.all().update(reason="changed")
    with pytest.raises(AppendOnlyError):
        WalletAdjustment.objects.all().delete()


def test_every_key_is_a_uuidv7_or_the_players() -> None:
    from django.apps import apps

    configs = [apps.get_app_config("economy"), apps.get_app_config("progress")]
    assert check_uuid7_primary_keys(configs) == []
    assert isinstance(Wallet._meta.pk, models.OneToOneField)


def test_the_ledger_names_its_operation_without_a_foreign_key() -> None:
    field = LedgerEntry._meta.get_field("op_id")
    assert isinstance(field, models.UUIDField)
    assert not field.is_relation
    assert field.null


def test_wallet_carries_the_adjust_permission() -> None:
    assert ("adjust_wallet", "Can adjust a player's balance") in Wallet._meta.permissions


def test_string_forms_name_no_secret(player: Player) -> None:
    now = timezone.now()
    flag = PlayerFlag(player=player, kind="trip_rate", game_date=now.date())
    counter = DayCounter(player=player, game_date=now.date(), kind="overdraft", count=2)
    grant = GrantRecord(player=player, kind="room", key="salon", granted_at=now)
    inventory = Inventory(player=player, booster_id="wake_all", count=3)
    entry = LedgerEntry(currency="BONAT", delta=-5, reason="booster_purchase")
    processed = ProcessedOp(op_type="trip_start", status="accepted", client_txn_id=uuid.uuid4())
    texts = [str(x) for x in (flag, counter, grant, inventory, entry, processed)]
    assert texts == [
        f"trip_rate {now.date()}",
        f"overdraft {now.date()}: 2",
        "room salon",
        "wake_all x 3",
        "BONAT -5 booster_purchase",
        "trip_start accepted",
    ]
