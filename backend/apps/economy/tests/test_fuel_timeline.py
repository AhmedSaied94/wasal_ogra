"""The fuel timeline (B03 tasks.md T061, research R7, contracts/fuel.md "The effective time").

`t = clamp(occurred_at, timeline_at, server_now)`, with `timeline_at` kept on the wallet across
batches. A phone's clock that runs backward or ahead is clamped, never rejected, and an honest
late sync gives the liters the phone had.
"""

from __future__ import annotations

from datetime import datetime, timedelta

import pytest
import time_machine
from django.utils import timezone
from pytest_django import Settings

from apps.accounts.models import Player
from apps.economy.models import PlayerFlag
from apps.economy.services.timeline import to_ms
from apps.economy.tests.helpers import reasons, run, trip_result, trip_start, wallet_of

pytestmark = pytest.mark.django_db


@pytest.fixture
def t0(player: Player) -> datetime:
    """The wallet was created three hours ago."""
    start = timezone.now().replace(microsecond=0) - timedelta(hours=3)
    with time_machine.travel(start, tick=False):
        run(player)
    return start


def test_the_timeline_never_goes_back_across_batches(
    player: Player, published_pack: int, t0: datetime
) -> None:
    later, earlier = t0 + timedelta(minutes=30), t0 + timedelta(minutes=10)
    run(player, trip_start("line_hay.01", published_pack, at=later))
    run(player, trip_start("line_hay.03", published_pack, at=earlier))
    wallet = wallet_of(player)
    assert wallet.timeline_at == later
    # The second start counted at the first's time: no liter came back in between.
    assert wallet.fuel == 3
    assert wallet.fuel_updated_at == later


def test_a_clock_backward_or_ahead_is_clamped_not_rejected(
    player: Player, published_pack: int, t0: datetime
) -> None:
    before_the_wallet = t0 - timedelta(days=2)
    ahead = timezone.now() + timedelta(hours=5)
    result = run(
        player,
        trip_start("line_hay.01", published_pack, at=before_the_wallet),
        trip_start("line_hay.03", published_pack, at=ahead),
    )
    assert reasons(result) == ["accepted", "accepted"]
    wallet = wallet_of(player)
    assert wallet.timeline_at <= timezone.now()
    assert to_ms(timezone.now()) - to_ms(wallet.timeline_at) < 60_000


def test_a_late_sync_of_five_trips_gives_the_phones_liters(
    player: Player, published_pack: int, t0: datetime
) -> None:
    """Five trips over two hours, synced at once: every start had its liter, as on the phone."""
    ops = []
    for n in range(5):
        at = t0 + timedelta(minutes=30 * n)
        start = trip_start("line_hay.01", published_pack, at=at)
        ops += [start, trip_result(start, "line_hay.01", at=at + timedelta(minutes=2))]
    assert reasons(run(player, *ops)) == ["accepted"] * 10
    wallet = wallet_of(player)
    assert wallet.fuel == 4
    assert wallet.fuel_updated_at == t0 + timedelta(minutes=120)
    assert not PlayerFlag.objects.filter(player=player).exists()


def test_a_large_clamp_is_flagged_once_a_day_with_a_count(
    player: Player, published_pack: int, t0: datetime, settings: Settings
) -> None:
    ahead = timezone.now() + timedelta(minutes=settings.SYNC_CLOCK_CLAMP_FLAG_MINUTES + 10)
    run(player, trip_start("line_hay.01", published_pack, at=ahead))
    run(player, trip_start("line_hay.03", published_pack, at=ahead))
    small = timezone.now() + timedelta(minutes=settings.SYNC_CLOCK_CLAMP_FLAG_MINUTES - 5)
    run(player, trip_start("line_hay.01", published_pack, at=small))
    flag = PlayerFlag.objects.get(player=player)
    assert flag.kind == PlayerFlag.Kind.CLOCK_CLAMPED
    assert flag.details["count"] == 2
    assert flag.details["moved_ms"] > settings.SYNC_CLOCK_CLAMP_FLAG_MINUTES * 60_000
