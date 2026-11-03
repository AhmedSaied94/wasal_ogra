"""The piggy's numbers are live (B07 US3 AS1, SC-004, research R10)."""

from __future__ import annotations

from datetime import timedelta
from typing import Any

import pytest
import time_machine
from django.conf import settings

from apps.accounts.models import Player, User
from apps.ads.models import AdReward
from apps.ads.services import ssv
from apps.ads.tests.conftest import AdmobKeys, Callback, new_player
from apps.ads.tests.signing import signed_query
from apps.liveops import settings as live
from apps.liveops.services import settings_admin

pytestmark = pytest.mark.django_db


def test_a_change_applies_after_the_refresh(admob_keys: AdmobKeys, live_settings: Any) -> None:
    actor = User.objects.create_user("live-1", is_staff=True)
    live_settings()  # its teardown puts the defaults back
    with time_machine.travel("2026-11-03 06:00:00Z", tick=False) as traveller:
        live.refresh()
        settings_admin.change_many({"ads_morning_piggy_bonat": 5}, actor, note="test")
        live.reset()
        live.current()  # a process holding the old value...
        traveller.shift(timedelta(seconds=settings.LIVEOPS_REFRESH_SECONDS))  # ...refreshes
        player = new_player()
        ssv.process(signed_query(user_id=str(player.pk))[0])
    assert AdReward.objects.get(player=player).bonat == 5
    settings_admin.change_many({"ads_morning_piggy_bonat": 2}, actor, note="test teardown")


def test_a_cap_of_zero_refuses(player: Player, callback: Callback, live_settings: Any) -> None:
    live_settings(ads_morning_piggy_daily_cap=0)
    callback(user_id=str(player.pk))
    assert AdReward.objects.get().outcome == "cap_reached"


def test_a_callback_reads_one_snapshot(
    player: Player, callback: Callback, monkeypatch: pytest.MonkeyPatch
) -> None:
    reads: list[int] = []
    current = live.current

    def counted() -> Any:
        reads.append(1)
        return current()

    monkeypatch.setattr(live, "current", counted)
    callback(user_id=str(player.pk))
    assert len(reads) == 1
