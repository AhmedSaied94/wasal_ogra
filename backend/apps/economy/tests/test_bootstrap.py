"""`GET /v1/bootstrap` (B03 tasks.md T052, contracts/api.md "GET /v1/bootstrap", spec US3)."""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime, timedelta

import pytest
import time_machine
from django.utils import timezone
from pytest_django import Settings

from apps.accounts.models import Identity, Player
from apps.economy.models import Wallet
from apps.economy.services.gameday import game_date
from apps.economy.tests.helpers import Api, iso, run, trip_result, trip_start, wallet_of

pytestmark = pytest.mark.django_db

KEYS = {
    "server_time",
    "player",
    "wallet",
    "entitlements",
    "state_version",
    "content",
    "client",
    "daily",
    "comeback",
}


def parse(value: str) -> datetime:
    return datetime.fromisoformat(value)


def test_a_new_player_starts_with_a_full_tank(api: Api, settings: Settings) -> None:
    before = timezone.now()
    response = api.bootstrap()
    assert response.status_code == 200, response.content
    body = response.json()
    assert set(body) == KEYS
    assert before - timedelta(seconds=1) <= parse(body["server_time"]) <= timezone.now()
    assert body["server_time"].endswith("Z")
    assert body["state_version"] == 0
    wallet = body["wallet"]
    assert (wallet["jenehat"], wallet["bonat"]) == (0, 0)
    assert wallet["fuel"] == wallet["fuel_max"] == settings.ECONOMY_FUEL_MAX
    assert wallet["fuel_unlimited_until"] is None
    assert body["player"] == {
        "player_id": api.player_id,
        "display_name": "",
        "driver_level": 1,
        "country": "EG",  # from the sign-in's locale (B02)
        "providers": [],
    }
    # A second call creates nothing new.
    again = api.bootstrap().json()
    assert again["wallet"] == body["wallet"]
    assert Wallet.objects.filter(player_id=api.player_id).count() == 1


def test_the_neutral_blocks(api: Api, settings: Settings) -> None:
    body = api.bootstrap().json()
    assert body["entitlements"] == {
        "remove_ads": False,
        "subscription": None,
        "season_passes": [],
        "flags": {"no_interstitials": False, "fuel_max_bonus": 0},
    }
    assert body["daily"] == {
        "game_date": game_date(timezone.now()).isoformat(),
        "challenge_available": False,
        "reward_claimable": False,
    }
    assert body["comeback"] == {"claimable": False}
    assert body["client"] == {
        "min_version": settings.CLIENT_MIN_VERSION,
        "latest_version": settings.CLIENT_LATEST_VERSION,
        "force_update": False,
    }


def test_content_names_the_current_version(
    api: Api, published_packs: Callable[[int], list[int]]
) -> None:
    assert api.bootstrap().json()["content"] == {
        "version": None,
        "manifest_url": "/v1/content/manifest",
    }
    _, current = published_packs(2)
    assert api.bootstrap().json()["content"] == {
        "version": current,
        "manifest_url": "/v1/content/manifest",
    }


def test_a_player_with_progress_sees_where_they_stand(api: Api, published_pack: int) -> None:
    Player.objects.filter(pk=api.player_id).update(
        display_name="Hamada", driver_level=4, country="EG"
    )
    Identity.objects.create(
        player_id=api.player_id, provider="google", subject="g-1", linked_at=timezone.now()
    )
    start = trip_start("line_hay.01", published_pack)
    api.sync({"base_state_version": 0, "ops": [start, trip_result(start, "line_hay.01")]})
    body = api.bootstrap().json()
    assert body["player"] == {
        "player_id": api.player_id,
        "display_name": "Hamada",
        "driver_level": 4,
        "country": "EG",
        "providers": ["google"],
    }
    assert body["wallet"]["jenehat"] == 10
    assert body["wallet"]["fuel"] == 4
    assert body["state_version"] == 1


def test_the_fuel_is_recounted_to_now(api: Api, published_pack: int) -> None:
    t0 = (timezone.now() - timedelta(minutes=25)).replace(microsecond=0)
    with time_machine.travel(t0, tick=False):
        run(api.player)  # the wallet, created then
        run(api.player, trip_start("line_hay.01", published_pack))
    stored = wallet_of(api.player)
    assert stored.fuel == 4
    wallet = api.bootstrap().json()["wallet"]
    # One liter came back 20 minutes after the start, which is when the tank filled.
    assert wallet["fuel"] == 5
    assert wallet["fuel_updated_at"] == iso(t0 + timedelta(minutes=20))
    assert wallet_of(api.player).fuel == 4  # a read doesn't write the fuel


def test_an_app_below_the_minimum_must_update_and_still_gets_its_answer(
    api: Api, settings: Settings
) -> None:
    settings.CLIENT_MIN_VERSION = "1.2.0"
    settings.CLIENT_LATEST_VERSION = "1.3.0"
    old = api.bootstrap(**{"x-client-version": "1.1.9+40"})
    assert old.status_code == 200
    assert old.json()["client"] == {
        "min_version": "1.2.0",
        "latest_version": "1.3.0",
        "force_update": True,
    }
    current = api.bootstrap(**{"x-client-version": "1.2.0+41"}).json()
    assert current["client"]["force_update"] is False


def test_a_bootstrap_after_the_session_gap_starts_a_session(api: Api, settings: Settings) -> None:
    api.bootstrap()
    first = wallet_of(api.player)
    assert first.session_started_at == first.last_active_at
    # Within the gap: the same session.
    earlier = timezone.now() - timedelta(minutes=settings.SYNC_SESSION_GAP_MINUTES - 5)
    Wallet.objects.filter(pk=first.pk).update(last_active_at=earlier, session_started_at=earlier)
    api.bootstrap()
    within = wallet_of(api.player)
    assert within.session_started_at == earlier
    assert within.last_active_at > earlier
    # After it: a new one.
    long_ago = timezone.now() - timedelta(minutes=settings.SYNC_SESSION_GAP_MINUTES + 1)
    Wallet.objects.filter(pk=first.pk).update(last_active_at=long_ago)
    api.bootstrap()
    after = wallet_of(api.player)
    assert after.session_started_at > earlier
    assert after.session_started_at == after.last_active_at


def test_a_sync_or_a_state_read_marks_activity_but_no_session(api: Api) -> None:
    long_ago = datetime(2026, 1, 1, tzinfo=UTC)
    api.bootstrap()
    Wallet.objects.filter(player_id=api.player_id).update(
        last_active_at=long_ago, session_started_at=long_ago
    )
    api.sync({"base_state_version": 0, "ops": []})
    wallet = wallet_of(api.player)
    assert wallet.last_active_at > long_ago
    assert wallet.session_started_at == long_ago
