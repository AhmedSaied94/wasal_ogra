"""The comeback return and its gift (B03 tasks.md T069, research R9, R13, spec US6 scenario 2).

A bootstrap that starts a session after `SYNC_COMEBACK_AWAY_DAYS` Cairo days without any activity
offers a return; one `comeback_gift` claims it, at most once per return and once per cooldown.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import pytest
import time_machine
from django.utils import timezone
from pytest_django import Settings

from apps.economy.models import GrantRecord, Inventory, Wallet
from apps.economy.services.wallets import iso
from apps.economy.tests.helpers import (
    Api,
    batch,
    granted_of,
    op,
    reasons,
    run,
    signed_in_api,
    trip_start,
    wallet_of,
)

pytestmark = pytest.mark.django_db

CAIRO = ZoneInfo("Africa/Cairo")


def gift() -> dict[str, Any]:
    return op("comeback_gift", {})


def away_since(api: Api, at: datetime) -> None:
    Wallet.objects.filter(player_id=api.player_id).update(last_active_at=at)


def claimable(api: Api) -> bool:
    flag: bool = api.bootstrap().json()["comeback"]["claimable"]
    return flag


@pytest.fixture
def returned(api: Api, settings: Settings) -> datetime:
    """The player's first bootstrap, then one after a week away: the return it set."""
    api.bootstrap()
    away_since(api, timezone.now() - timedelta(days=settings.SYNC_COMEBACK_AWAY_DAYS + 1))
    assert claimable(api) is True
    return_at = wallet_of(api.player).comeback_return_at
    assert return_at is not None
    return return_at


def test_a_week_away_offers_a_return(api: Api, returned: datetime) -> None:
    assert timezone.now() - returned < timedelta(minutes=1)
    assert api.state().json()["comeback"] == {"claimable": True}


def test_a_bootstrap_within_the_session_offers_nothing(api: Api, settings: Settings) -> None:
    api.bootstrap()
    away_since(api, timezone.now() - timedelta(minutes=settings.SYNC_SESSION_GAP_MINUTES - 1))
    assert claimable(api) is False
    assert wallet_of(api.player).comeback_return_at is None


def test_a_shorter_absence_offers_nothing_new_and_keeps_an_unclaimed_return(
    api: Api, returned: datetime
) -> None:
    away_since(api, timezone.now() - timedelta(days=2))
    assert claimable(api) is True
    assert wallet_of(api.player).comeback_return_at == returned


def test_the_gift_fills_the_tank_adds_a_change_bag_and_is_claimed_once(
    api: Api, returned: datetime, published_pack: int
) -> None:
    run(api.player, trip_start("line_hay.01", published_pack))
    result = run(api.player, gift(), gift())
    assert reasons(result) == ["accepted", "already_granted"]
    assert granted_of(result) == [
        {"kind": "gift", "id": "comeback", "fuel": "max", "booster": "change_bag"}
    ]
    assert wallet_of(api.player).fuel == 5
    assert Inventory.objects.get(player_id=api.player_id, booster_id="change_bag").count == 1
    record = GrantRecord.objects.get(player_id=api.player_id, kind="comeback")
    assert record.key == iso(returned)
    assert claimable(api) is False
    assert api.state().json()["comeback"] == {"claimable": False}
    # Sent again later, through the API, it is still claimed.
    response = api.sync(batch(gift(), base=1)).json()
    assert response["results"][0]["reason"] == "already_granted"


def test_without_a_return_the_gift_is_not_eligible(api: Api) -> None:
    api.bootstrap()
    assert reasons(run(api.player, gift())) == ["not_eligible"]


def test_no_new_return_inside_the_cooldown(
    api: Api, returned: datetime, settings: Settings
) -> None:
    run(api.player, gift())
    away_since(api, timezone.now() - timedelta(days=settings.SYNC_COMEBACK_AWAY_DAYS + 1))
    assert claimable(api) is False
    assert wallet_of(api.player).comeback_return_at == returned
    # A return the cooldown doesn't allow can't be claimed either.
    Wallet.objects.filter(player_id=api.player_id).update(
        comeback_return_at=timezone.now() - timedelta(minutes=1)
    )
    assert reasons(run(api.player, gift())) == ["not_eligible"]


def test_after_the_cooldown_a_new_absence_offers_a_new_return(
    api: Api, returned: datetime, settings: Settings
) -> None:
    run(api.player, gift())
    long_ago = timezone.now() - timedelta(days=settings.SYNC_COMEBACK_COOLDOWN_DAYS + 1)
    GrantRecord.objects.filter(player_id=api.player_id, kind="comeback").update(granted_at=long_ago)
    away_since(api, timezone.now() - timedelta(days=settings.SYNC_COMEBACK_AWAY_DAYS + 1))
    assert claimable(api) is True
    assert wallet_of(api.player).comeback_return_at != returned
    assert reasons(run(api.player, gift())) == ["accepted"]
    assert GrantRecord.objects.filter(player_id=api.player_id, kind="comeback").count() == 2


@pytest.mark.parametrize(
    ("last_active", "offered"),
    [
        (datetime(2026, 10, 13, 23, 50, tzinfo=CAIRO), True),  # 7 calendar days, 6 days 20 min
        (datetime(2026, 10, 14, 0, 5, tzinfo=CAIRO), False),  # 6 calendar days
    ],
)
def test_away_days_are_counted_in_cairo_calendar_days(
    db: None, settings: Settings, last_active: datetime, offered: bool
) -> None:
    assert settings.SYNC_COMEBACK_AWAY_DAYS == 7
    with time_machine.travel(datetime(2026, 10, 20, 0, 10, tzinfo=CAIRO), tick=False):
        api = signed_in_api()
        api.bootstrap()
        away_since(api, last_active)
        assert claimable(api) is offered
