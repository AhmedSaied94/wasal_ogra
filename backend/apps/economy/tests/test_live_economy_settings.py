"""The economy reads its balancing numbers from the live settings (B10 FR-002, FR-005, FR-007)."""

from __future__ import annotations

from datetime import timedelta
from typing import Any

import pytest
import time_machine
from django.utils import timezone

from apps.accounts.models import Player
from apps.economy.models import PlayerFlag
from apps.economy.tests.helpers import Api, op, reasons, run, trip_start, wallet_of
from apps.liveops import settings as live
from apps.liveops.models import LiveSetting

pytestmark = pytest.mark.django_db


def starts(version: int, count: int) -> list[dict[str, Any]]:
    return [trip_start("line_hay.01", version) for _ in range(count)]


def test_the_overdraft_cap_comes_from_the_live_setting(
    player: Player, published_pack: int, live_settings: Any
) -> None:
    live_settings(fuel_overdraft_per_day=1)
    result = run(player, *starts(published_pack, 8))
    # Five litres, one overdraft, then the cap; the last two starts are refused.
    assert reasons(result) == ["accepted"] * 6 + ["cap_reached"] * 2
    flag = PlayerFlag.objects.get(player=player, kind=PlayerFlag.Kind.FUEL_OVERDRAFT)
    assert flag.details["count"] == 1


def test_the_comeback_gap_comes_from_the_live_setting(api: Api, live_settings: Any) -> None:
    live_settings(comeback_away_days=5)
    api.bootstrap()
    away = timezone.now() - timedelta(days=6)
    from apps.economy.models import Wallet

    Wallet.objects.filter(player_id=api.player_id).update(
        last_active_at=away, session_started_at=away
    )
    assert api.bootstrap().json()["comeback"]["claimable"] is True


def test_a_batch_reads_one_snapshot(
    player: Player,
    published_packs: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    older, newest = published_packs(2)
    live.refresh()
    calls: list[Any] = []
    real = live.current

    def current() -> Any:
        snapshot = real()
        calls.append(snapshot)
        if len(calls) == 1:
            # Another process's change, arriving mid-batch: this batch must not see it.
            LiveSetting.objects.filter(key="fuel_overdraft_per_day").update(value=0)
        return snapshot

    monkeypatch.setattr(live, "current", current)
    result = run(
        player,
        op("settings_update", {"display_name": "حمادة"}),
        trip_start("line_hay.01", older),  # a supported pack that is no longer current
        *starts(newest, 6),
    )
    assert len(calls) == 1
    assert reasons(result) == ["accepted"] * 8


def test_a_new_batch_sees_the_change_after_the_refresh_window(
    player: Player, published_pack: int
) -> None:
    live.refresh()
    run(player, *starts(published_pack, 5))  # drains the tank on the default snapshot
    LiveSetting.objects.filter(key="fuel_overdraft_per_day").update(value=0)
    with time_machine.travel(timezone.now() + timedelta(seconds=31), tick=False):
        assert reasons(run(player, trip_start("line_hay.01", published_pack))) == ["cap_reached"]
    assert wallet_of(player).fuel == 0
