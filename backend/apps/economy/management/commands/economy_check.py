"""`economy_check`: the restore drill's ledger check, on the live database (quickstart B3).

Exits 1 when a wallet differs from its ledger: a stop-the-line event (docs/runbooks/economy.md).
"""

from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError
from django.db import connection

from apps.economy.invariants import wallet_equals_ledger

NAME = "economy.wallet_equals_ledger"


class Command(BaseCommand):
    help = "Check that every wallet equals the sum of its ledger. Exits 1 on a mismatch."

    def handle(self, *args: Any, **options: Any) -> None:
        connection.ensure_connection()
        passed, detail = wallet_equals_ledger(connection.connection)  # Django's psycopg connection
        if not passed:
            raise CommandError(f"{NAME}: failed, {detail}")
        self.stdout.write(f"{NAME}: passed, {detail}")
