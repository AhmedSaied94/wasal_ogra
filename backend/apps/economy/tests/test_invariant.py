"""The ledger invariant and `economy_check` (B03 tasks.md T018, spec FR-010).

The corruptions use raw SQL on purpose: nothing in the app can produce them.
"""

from __future__ import annotations

from io import StringIO

import pytest
from django.core.management import CommandError, call_command
from django.db import connection, transaction

from apps.accounts.models import Player
from apps.common.services import invariants
from apps.economy.invariants import wallet_equals_ledger
from apps.economy.models import Currency, LedgerEntry
from apps.economy.services import ledger

pytestmark = pytest.mark.django_db

NAME = "economy.wallet_equals_ledger"


def earn(player: Player, amount: int) -> None:
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        ledger.apply_now(
            wallet,
            currency=Currency.JENEHAT,
            delta=amount,
            reason=LedgerEntry.Reason.TRIP_EARNINGS,
            source=LedgerEntry.Source.CLIENT_OP,
        )


def check() -> tuple[bool, str]:
    connection.ensure_connection()
    return wallet_equals_ledger(connection.connection)


def test_it_is_registered_after_django_starts() -> None:
    assert NAME in invariants.registered()


def test_it_passes_when_every_wallet_equals_its_ledger(player: Player) -> None:
    earn(player, 7)
    earn(player, 5)
    assert check() == (True, "1 wallets equal their ledger, 0 players differ")


def test_it_fails_on_a_corrupted_wallet(player: Player) -> None:
    earn(player, 7)
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE economy_wallet SET jenehat = %s WHERE player_id = %s", [999, player.pk]
        )
    assert check() == (False, f"1 players differ: {player.pk}")


def test_it_fails_on_entries_without_a_wallet(player: Player) -> None:
    earn(player, 7)
    with connection.cursor() as cursor:
        cursor.execute("DELETE FROM economy_wallet WHERE player_id = %s", [player.pk])
    passed, detail = check()
    assert not passed
    assert detail == f"1 players differ: {player.pk}"


def test_the_command_prints_the_result(player: Player) -> None:
    earn(player, 3)
    out = StringIO()
    call_command("economy_check", stdout=out)
    assert (
        out.getvalue().strip() == f"{NAME}: passed, 1 wallets equal their ledger, 0 players differ"
    )


def test_the_command_exits_1_on_a_mismatch(player: Player) -> None:
    earn(player, 3)
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE economy_wallet SET jenehat = %s WHERE player_id = %s", [0, player.pk]
        )
    with pytest.raises(CommandError, match="1 players differ") as error:
        call_command("economy_check")
    assert error.value.returncode == 1
