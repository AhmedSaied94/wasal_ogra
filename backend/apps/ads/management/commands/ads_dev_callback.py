"""`ads_dev_callback`: sign an AdMob callback with a dev key and send it (B07 quickstart).

Dev and test only. On first use it creates a P-256 key in `backend/.dev/` (gitignored) and writes
its public half there as an AdMob-shaped key list, `admob_verifier_keys.json`, which the dev
stack's `ADS_VERIFIER_KEYS_URL` names. Production and staging never see the key.
"""

from __future__ import annotations

import json
import time
import uuid
from pathlib import Path
from typing import Any

import requests
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError, CommandParser

from apps.ads.services import dev_signing

ENVIRONMENTS = ("dev", "test")
DAY_MS = 24 * 3600 * 1000


def dev_dir() -> Path:
    return Path(settings.BASE_DIR) / ".dev"


def dev_key(directory: Path) -> ec.EllipticCurvePrivateKey:
    """The dev key, made and its key list written on first use."""
    pem = directory / "admob_dev_key.pem"
    if pem.exists():
        key = serialization.load_pem_private_key(pem.read_bytes(), password=None)
        if not isinstance(key, ec.EllipticCurvePrivateKey):
            raise CommandError(f"{pem} is not a P-256 key")
        return key
    directory.mkdir(parents=True, exist_ok=True)
    key = dev_signing.new_key()
    pem.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    pem.chmod(0o600)
    keys = {"keys": [dev_signing.key_entry(key, dev_signing.DEFAULT_KEY_ID)]}
    (directory / "admob_verifier_keys.json").write_text(json.dumps(keys), encoding="utf-8")
    return key


class Command(BaseCommand):
    help = "Dev only: sign an AdMob SSV callback with the dev key and send it to the API."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--user", default="", help="The player id (user_id).")
        parser.add_argument("--placement", default="morning_piggy")
        parser.add_argument("--nonce", default="", help="The reference; a new one by default.")
        parser.add_argument("--transaction-id", default="", help="A new one by default.")
        parser.add_argument("--age-days", type=float, default=0.0, help="Date the callback back.")
        parser.add_argument("--tamper", action="store_true", help="Change a signed byte.")
        parser.add_argument("--api", default="http://localhost:8000")

    def handle(self, *args: Any, **options: Any) -> None:
        if settings.WASSAL_ENV not in ENVIRONMENTS:
            raise CommandError("ads_dev_callback runs only in dev and test")
        key = dev_key(dev_dir())
        transaction_id = options["transaction_id"] or uuid.uuid4().hex
        timestamp = int(time.time() * 1000) - int(options["age_days"] * DAY_MS)
        query, nonce = dev_signing.signed_query(
            key,
            user_id=options["user"],
            placement=options["placement"],
            nonce=options["nonce"] or None,
            transaction_id=transaction_id,
            timestamp=str(timestamp),
        )
        if options["tamper"]:
            query = query.replace("reward_item=piggy", "reward_item=pigge", 1)
        self.stdout.write(f"reference {nonce}  transaction {transaction_id}")
        api = options["api"].rstrip("/")
        try:
            response = requests.get(f"{api}/v1/ads/ssv?{query}", timeout=10)
        except requests.RequestException:
            raise CommandError(f"the API at {api} didn't answer; is the dev stack up?") from None
        self.stdout.write(f"{response.status_code} {response.text}")
