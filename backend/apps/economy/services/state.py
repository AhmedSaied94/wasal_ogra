"""`GET /v1/state`: everything the server holds of the player, at one `state_version`
(contracts/api.md, research R16).

The wallet row is read under a shared lock, so a batch can't commit between two of the reads:
a batch takes the row `FOR UPDATE` first, so it either finished before the snapshot or waits for
it. Readers don't block each other. Django has no `FOR SHARE`, hence the raw statement, which is
parameterized.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from django.db import connection, transaction
from django.db.models import Sum
from django.utils import timezone

from apps.accounts.models import Player
from apps.economy.models import GrantRecord, Inventory, Wallet
from apps.economy.services import comeback, ledger, settings, wallets
from apps.economy.services.timeline import from_ms, to_ms
from apps.progress.models import DailyState, Ownership, StoryState, TripProgress, TripSession

SHARE_LOCK = "SELECT 1 FROM economy_wallet WHERE player_id = %s FOR SHARE"
BOOSTERS = ("change_bag", "wake_all", "ledger_peek", "traffic_jam")


def snapshot(player: Player) -> dict[str, Any]:
    now = from_ms(to_ms(timezone.now()))
    config = settings.current()
    with transaction.atomic():
        if not Wallet.objects.filter(pk=player.pk).exists():
            ledger.create_wallet(player, now=now)
        with connection.cursor() as cursor:
            cursor.execute(SHARE_LOCK, [player.pk])
        wallet = Wallet.objects.get(pk=player.pk)
        answer = _read(player, wallet, now)
        answer["wallet"] = wallets.answer(wallet, player, now, config)
        answer["comeback"] = {"claimable": comeback.claimable(wallet, now, config)}
    # After the snapshot's transaction, so readers never wait on each other for it.
    Wallet.objects.filter(pk=player.pk).update(last_active_at=now)
    return answer


def _read(player: Player, wallet: Wallet, now: datetime) -> dict[str, Any]:
    profile = Player.objects.filter(pk=player.pk).values("display_name", "driver_level", "settings")
    stock = dict(Inventory.objects.filter(player=player).values_list("booster_id", "count"))
    trips = TripProgress.objects.filter(player=player).order_by("trip_id")
    totals = trips.aggregate(plays=Sum("plays"), stars=Sum("best_stars"))
    session = TripSession.objects.filter(player=player).first()
    grants = set(
        GrantRecord.objects.filter(
            player=player, kind__in=(GrantRecord.Kind.TUTORIAL, GrantRecord.Kind.REQUEST)
        ).values_list("kind", "key")
    )
    streak = DailyState.objects.filter(player=player).values_list("longest_streak", flat=True)
    return {
        "state_version": wallet.state_version,
        "server_time": wallets.iso(now),
        "player": dict(profile.get()),
        "inventory": {booster: stock.get(booster, 0) for booster in BOOSTERS},
        "ownership": list(
            Ownership.objects.filter(player=player)
            .order_by("kind", "sku_id")
            .values("kind", "sku_id", "variant")
        ),
        "trips": list(trips.values("trip_id", "best_stars", "best_time_ms", "plays")),
        "open_trip": _open_trip(session),
        "last_result": _last_result(session),
        "story": {
            "chapters": list(
                StoryState.objects.filter(player=player)
                .order_by("chapter_id")
                .values("chapter_id", "status", "scenes_seen")
            ),
            "requests_claimed": sorted(key for kind, key in grants if kind == "request"),
        },
        "grants": {"tutorial": any(kind == "tutorial" for kind, _ in grants)},
        "stats": {
            "trips_played": totals["plays"] or 0,
            "stars_total": totals["stars"] or 0,
            "longest_streak": streak.first() or 0,
        },
    }


def _open_trip(session: TripSession | None) -> dict[str, Any] | None:
    if session is None or session.open_start is None:
        return None
    return {
        "start_txn": str(session.open_start),
        "trip_id": session.open_trip_id,
        "content_version": session.open_content_version,
        "revived": session.open_revived,
        "traffic_jam_ads": session.open_traffic_jam_ads,
    }


def _last_result(session: TripSession | None) -> dict[str, Any] | None:
    if session is None or session.last_start is None:
        return None
    return {
        "start_txn": str(session.last_start),
        "outcome": session.last_outcome,
        "earnings_jenehat": session.last_earnings,
        "doubled": session.last_doubled,
    }
