"""Reward rows written directly, for the tests of what reads them (bootstrap, the seen mark).

The callback's own tests go through `GET /v1/ads/ssv`; these rows carry no ledger entries.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from django.utils import timezone

from apps.accounts.models import Player
from apps.ads.models import AdReward
from apps.economy.services.gameday import game_date


def reward_row(
    player: Player | None,
    outcome: str = AdReward.Outcome.GRANTED,
    *,
    at: datetime | None = None,
    **fields: Any,
) -> AdReward:
    when = at or timezone.now()
    granted = outcome == AdReward.Outcome.GRANTED
    values: dict[str, Any] = {
        "transaction_id": uuid.uuid4().hex,
        "player": player,
        "placement": "morning_piggy",
        "nonce": uuid.uuid4(),
        "reward_amount": 1,
        "key_id": 1,
        "callback_at": when,
        "outcome": outcome,
        "jenehat": 30 if granted else 0,
        "bonat": 2 if granted else 0,
        "game_date": game_date(when),
        "created_at": when,
    }
    values.update(fields)
    return AdReward.objects.create(**values)
