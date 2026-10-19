"""The B2 settings shared by `backup_db` and `restore_drill fetch` (contracts/environment.md).

Django skips command modules whose names start with `_`, so this is a helper, not a command. A bad
value is refused by name, never by value.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import urlsplit

from django.core.exceptions import ImproperlyConfigured

from config.env import Env

PREFIX = re.compile(r"[a-z0-9][a-z0-9-]{0,31}")
# B2 bucket names: 6 to 50 letters, digits and hyphens.
BUCKET = re.compile(r"[A-Za-z0-9-]{6,50}")


@dataclass(frozen=True)
class Storage:
    endpoint: str
    region: str
    daily_bucket: str
    weekly_bucket: str
    prefix: str


def read_storage(env: Env) -> Storage:
    endpoint = env.string("B2_S3_ENDPOINT")
    parts = urlsplit(endpoint)
    if parts.scheme != "https" or not parts.hostname or parts.path not in ("", "/"):
        raise ImproperlyConfigured("B2_S3_ENDPOINT is invalid")
    prefix = env.string("BACKUP_PREFIX", "prod")
    if not PREFIX.fullmatch(prefix):
        raise ImproperlyConfigured("BACKUP_PREFIX is invalid")
    buckets = {name: env.string(name) for name in ("B2_DAILY_BUCKET", "B2_WEEKLY_BUCKET")}
    for name, bucket in buckets.items():
        if not BUCKET.fullmatch(bucket):
            raise ImproperlyConfigured(f"{name} is invalid")
    return Storage(
        endpoint=endpoint.rstrip("/"),
        region=env.string("B2_REGION"),
        daily_bucket=buckets["B2_DAILY_BUCKET"],
        weekly_bucket=buckets["B2_WEEKLY_BUCKET"],
        prefix=prefix,
    )
