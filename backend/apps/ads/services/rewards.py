"""The app's reward lookup (B07 research R9, FR-014-FR-016). It never writes."""

from __future__ import annotations

import uuid
from typing import Any

from django.utils import timezone

from apps.accounts.models import Player
from apps.ads.models import AdReward
from apps.economy.models import Wallet
from apps.economy.services import settings, wallets


def lookup(player: Player, nonce: uuid.UUID) -> dict[str, Any] | None:
    """The player's reward with this reference, or None: not arrived yet, someone else's,
    unattributed or never used all look the same (FR-015)."""
    row = AdReward.objects.filter(player=player, nonce=nonce).first()
    if row is None:
        return None
    if row.outcome != AdReward.Outcome.GRANTED:
        return {"status": "refused", "reason": row.outcome}
    wallet = Wallet.objects.get(pk=player.pk)  # a grant created it
    return {
        "status": "granted",
        "jenehat": row.jenehat,
        "bonat": row.bonat,
        "granted_at": wallets.iso(row.created_at),
        "wallet": wallets.answer(wallet, player, timezone.now(), settings.current()),
    }
