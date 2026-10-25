"""`GET /v1/bootstrap`: where the player stands at launch (contracts/api.md, research R13, R16).

It creates the wallet on first use, marks the session and, at a session's start after a long
absence, sets the comeback return; nothing else is written. The wallet's fuel is recounted to now
for the answer only.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from django.db import transaction
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import Player
from apps.common.client import ClientInfo, as_tuple, parse_client_version
from apps.content.services import lookups
from apps.economy.models import Wallet
from apps.economy.services import comeback, entitlements, ledger, settings, wallets
from apps.economy.services.gameday import game_date
from apps.economy.services.settings import EconomySettings
from apps.economy.services.timeline import from_ms, to_ms


def bootstrap(player: Player, client: ClientInfo) -> dict[str, Any]:
    now = from_ms(to_ms(timezone.now()))
    config = settings.current()
    with transaction.atomic():
        wallet = ledger.lock_wallet(player, now=now)
        _mark_session(wallet, now, config)
        claimable = comeback.claimable(wallet, now, config)
    providers = sorted(player.identities.values_list("provider", flat=True))
    return {
        "server_time": wallets.iso(now),
        "player": {
            "player_id": str(player.pk),
            "display_name": player.display_name,
            "driver_level": player.driver_level,
            "country": player.country,
            "providers": providers,
        },
        "wallet": wallets.answer(wallet, player, now, config),
        "entitlements": entitlements.entitlements_for(player, now),
        "state_version": wallet.state_version,
        "content": {
            "version": lookups.current_version(),
            "manifest_url": reverse("content-manifest"),
        },
        "client": {
            "min_version": config.client_min_version,
            "latest_version": config.client_latest_version,
            "force_update": _below(client.version, config.client_min_version),
        },
        "daily": {
            "game_date": game_date(now).isoformat(),
            "challenge_available": False,
            "reward_claimable": False,
        },
        "comeback": {"claimable": claimable},
    }


def _mark_session(wallet: Wallet, now: datetime, config: EconomySettings) -> None:
    """Activity now; a new session after `SYNC_SESSION_GAP_MINUTES` without any, and with it a
    comeback return after a long absence (research R13)."""
    fields = ["last_active_at", "updated_at"]
    if now - wallet.last_active_at >= timedelta(minutes=config.session_gap_minutes):
        wallet.session_started_at = now
        fields.append("session_started_at")
        if comeback.offer(wallet, now, config):
            fields.append("comeback_return_at")
    wallet.last_active_at = now
    wallet.save(update_fields=fields)


def _below(header: str, minimum: str) -> bool:
    version = parse_client_version(header)
    return version is not None and version < as_tuple(minimum)
