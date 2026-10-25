"""The comeback return (research R9, R13): when a bootstrap offers one, and when it is claimable.

A return is the instant a bootstrap found the player back after `SYNC_COMEBACK_AWAY_DAYS` game days
without activity. `comeback_gift` claims it once, recorded as `GrantRecord(comeback, <return
iso>)`, so the return stays on the wallet after the claim and a later one replaces it. At most one
gift per `SYNC_COMEBACK_COOLDOWN_DAYS`.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from apps.economy.models import GrantRecord, Wallet
from apps.economy.services import wallets
from apps.economy.services.gameday import game_date
from apps.economy.services.settings import EconomySettings


def away_days(last_active_at: datetime, now: datetime) -> int:
    """Whole game days between the two, by the calendar (research R13)."""
    return (game_date(now) - game_date(last_active_at)).days


def cooldown_passed(last_gift_at: datetime | None, at: datetime, config: EconomySettings) -> bool:
    return last_gift_at is None or at - last_gift_at >= timedelta(
        days=config.comeback_cooldown_days
    )


def return_key(return_at: datetime) -> str:
    """The `GrantRecord` key of a return: its time as the answers write it."""
    return wallets.iso(return_at)


def offer(wallet: Wallet, now: datetime, config: EconomySettings) -> bool:
    """At a bootstrap that starts a session, before `last_active_at` moves: set a new return when
    the player was away long enough and the cooldown allows a gift. True if it set one."""
    if away_days(wallet.last_active_at, now) < config.comeback_away_days:
        return False
    if not cooldown_passed(_last_gift_at(wallet), now, config):
        return False
    wallet.comeback_return_at = now
    return True


def claimable(wallet: Wallet, now: datetime, config: EconomySettings) -> bool:
    return_at = wallet.comeback_return_at
    if return_at is None:
        return False
    gifts = GrantRecord.objects.filter(player_id=wallet.pk, kind=GrantRecord.Kind.COMEBACK)
    if gifts.filter(key=return_key(return_at)).exists():
        return False
    return cooldown_passed(_last_gift_at(wallet), now, config)


def _last_gift_at(wallet: Wallet) -> datetime | None:
    return (
        GrantRecord.objects.filter(player_id=wallet.pk, kind=GrantRecord.Kind.COMEBACK)
        .order_by("-granted_at")
        .values_list("granted_at", flat=True)
        .first()
    )
