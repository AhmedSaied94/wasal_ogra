"""`manage.py auth_signing_key`: a fresh `AUTH_SIGNING_KEYS` entry (B02 research R13).

Prints `k<YYYYMMDD>:<32 random bytes, base64url>` and writes no file. Rotating keys:
docs/runbooks/auth-keys.md.
"""

from __future__ import annotations

import base64
import secrets
from typing import Any

from django.core.management.base import BaseCommand
from django.utils import timezone

KEY_BYTES = 32


class Command(BaseCommand):
    help = (
        "Print a new AUTH_SIGNING_KEYS entry, kid:key. Put it first in the environment's env "
        "file to rotate (docs/runbooks/auth-keys.md). Writes no file."
    )

    def handle(self, *args: Any, **options: Any) -> None:
        key = base64.urlsafe_b64encode(secrets.token_bytes(KEY_BYTES)).rstrip(b"=").decode()
        self.stdout.write(f"k{timezone.now():%Y%m%d}:{key}")
