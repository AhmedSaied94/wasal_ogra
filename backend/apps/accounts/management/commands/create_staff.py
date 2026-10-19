"""`create_staff <username> [--superuser] [--deactivate]` (data-model "Lifecycle", research R5).

The password is read twice from the terminal and never echoed or logged. The new account has no
TOTP device, so it can't sign in until `staff_totp` issues one.
"""

from __future__ import annotations

import getpass
from typing import Any

from django.contrib.auth import password_validation
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError, CommandParser
from django.db import transaction

from apps.accounts.models import User


class Command(BaseCommand):
    help = "Create a staff user (no TOTP device yet), or deactivate one with --deactivate."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("username")
        parser.add_argument("--superuser", action="store_true", help="Grant every permission.")
        parser.add_argument(
            "--deactivate", action="store_true", help="Deactivate an existing staff user instead."
        )

    def handle(self, *args: Any, **options: Any) -> None:
        username = options["username"].lower()
        if options["deactivate"]:
            self._deactivate(username)
            return
        if User.objects.filter(username=username).exists():
            raise CommandError(f"User {username!r} already exists.")

        user = User(username=username, is_staff=True, is_superuser=options["superuser"])
        try:
            user.full_clean(exclude=["password"])
        except ValidationError as exc:
            raise CommandError(f"Invalid username: {'; '.join(exc.messages)}") from None

        password = getpass.getpass("Password: ")
        if getpass.getpass("Password (again): ") != password:
            raise CommandError("The passwords don't match.")
        try:
            password_validation.validate_password(password, user)
        except ValidationError as exc:
            raise CommandError(" ".join(exc.messages)) from None

        user.set_password(password)
        with transaction.atomic():
            user.save()
        self.stdout.write(f"Created staff user {username}. Issue its TOTP device with staff_totp.")

    def _deactivate(self, username: str) -> None:
        updated = User.objects.filter(username=username, is_staff=True).update(is_active=False)
        if not updated:
            raise CommandError(f"There is no staff user {username!r}.")
        self.stdout.write(f"Deactivated {username}.")
