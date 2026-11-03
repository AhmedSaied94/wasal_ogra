"""The operator's alerts on the callback (B07 research R11, FR-007, SC-007).

Each refused signature counts in a 5-minute bucket in the cache; the last 12 buckets are the
rolling hour. Past `ALERT_SIGNATURE_THRESHOLD` in an hour, one Sentry warning, then none for
`ALERT_WINDOW_SECONDS`. A key list that can't be fetched alerts the same way under its own guard.
Losing the cache loses a count, never a grant.
"""

from __future__ import annotations

import logging
import time

import sentry_sdk
from django.core.cache import cache
from redis.exceptions import RedisError

logger = logging.getLogger("apps.ads")

ALERT_SIGNATURE_THRESHOLD = 20
ALERT_WINDOW_SECONDS = 3600
BUCKET_SECONDS = 300
BUCKETS = ALERT_WINDOW_SECONDS // BUCKET_SECONDS
BUCKET_TTL_SECONDS = 2 * ALERT_WINDOW_SECONDS
SIGNATURE_FINGERPRINT = ["ads", "ssv-signature"]
KEYS_FINGERPRINT = ["ads", "ssv-keys"]


def signature_refused() -> None:
    try:
        now = time.time()
        bucket = int(now // BUCKET_SECONDS)
        key = f"ads:ssv:refused:{bucket}"
        cache.add(key, 0, BUCKET_TTL_SECONDS)
        cache.incr(key)
        counts = cache.get_many([f"ads:ssv:refused:{bucket - n}" for n in range(BUCKETS)])
        if sum(int(v) for v in counts.values()) > ALERT_SIGNATURE_THRESHOLD:
            _alert("signature", "AdMob SSV: refused signatures", SIGNATURE_FINGERPRINT, now)
    except (RedisError, ValueError):
        logger.warning("ads_alert_counter_unavailable")


def keys_unavailable() -> None:
    try:
        _alert("keys", "AdMob SSV: verifier keys unavailable", KEYS_FINGERPRINT, time.time())
    except RedisError:
        logger.warning("ads_alert_counter_unavailable")


def _alert(name: str, message: str, fingerprint: list[str], now: float) -> None:
    """At most once per `ALERT_WINDOW_SECONDS`, by the time the last alert was sent."""
    guard = f"ads:alert:{name}"
    if not cache.add(guard, now, BUCKET_TTL_SECONDS):
        sent = cache.get(guard)
        if sent is not None and now - float(sent) < ALERT_WINDOW_SECONDS:
            return
        cache.set(guard, now, BUCKET_TTL_SECONDS)
    sentry_sdk.capture_message(message, level="warning", fingerprint=fingerprint)
