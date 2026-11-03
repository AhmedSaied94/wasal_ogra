"""Bootstrap's `ads` block (B07 research R8, FR-017).

Imports only `ads.models`: bootstrap passes its own game day and the snapshot's cap, so `economy`
never imports an `ads` module that imports `economy` (B07 plan, boundaries; a test checks).
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from typing import Any

from apps.accounts.models import Player
from apps.ads.models import AdReward

PIGGY = "morning_piggy"
UNSEEN_LIMIT = 5


def piggy_block(player: Player, game_date: date, cap: int) -> dict[str, Any]:
    """`{"available", "unseen"}`, in two indexed queries (`ad_reward_daily_cap`, `_unseen`)."""
    granted = AdReward.objects.filter(player=player, outcome=AdReward.Outcome.GRANTED)
    today = granted.filter(placement=PIGGY, game_date=game_date).count()
    unseen = granted.filter(shown_at__isnull=True, nonce__isnull=False).order_by("-created_at")
    return {
        "available": today < cap,
        "unseen": [
            {"nonce": str(nonce), "jenehat": jenehat, "bonat": bonat, "granted_at": _iso(at)}
            for nonce, jenehat, bonat, at in unseen.values_list(
                "nonce", "jenehat", "bonat", "created_at"
            )[:UNSEEN_LIMIT]
        ],
    }


def _iso(instant: datetime) -> str:
    """As `economy.services.wallets.iso`: UTC with `Z`, to the millisecond when it has one."""
    utc = instant.astimezone(UTC)
    millis = utc.microsecond // 1000
    stamp = utc.strftime("%Y-%m-%dT%H:%M:%S")
    return f"{stamp}.{millis:03d}Z" if millis else f"{stamp}Z"
