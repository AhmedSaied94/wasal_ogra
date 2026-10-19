"""`staff_totp <username> [--reset]` (data-model "Lifecycle", research R5).

Issues the staff member's one confirmed TOTP device and prints its `otpauth://` URI and base32 key
once, for an authenticator app. `--reset` replaces a lost device.
"""

from __future__ import annotations

from base64 import b32encode
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser
from django.db import transaction
from django_otp.plugins.otp_totp.models import TOTPDevice

from apps.accounts.models import User

DEVICE_NAME = "default"


class Command(BaseCommand):
    help = "Issue a staff user's TOTP device, or replace it with --reset."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("username")
        parser.add_argument("--reset", action="store_true", help="Delete the old device first.")

    def handle(self, *args: Any, **options: Any) -> None:
        username = options["username"].lower()
        user = User.objects.filter(username=username, is_staff=True).first()
        if user is None:
            raise CommandError(f"There is no staff user {username!r}.")

        with transaction.atomic():
            devices = TOTPDevice.objects.select_for_update().filter(user=user)
            if devices.exists():
                if not options["reset"]:
                    raise CommandError(
                        f"{username} already has a device. Use --reset to replace it."
                    )
                devices.delete()
            device = TOTPDevice.objects.create(user=user, name=DEVICE_NAME, confirmed=True)

        key = b32encode(device.bin_key).decode()
        self.stdout.write("Add this to the staff member's authenticator app. It is shown once.")
        self.stdout.write(f"URI: {device.config_url}")
        self.stdout.write(f"Key: {key}")
