"""Active players per version and the blocked preview (B10 FR-031, FR-032, research R10)."""

from __future__ import annotations

from collections.abc import Callable
from datetime import timedelta

import pytest
import time_machine
from django.contrib.auth.models import Group
from django.test import Client
from django.utils import timezone

from apps.accounts.models import Player, User
from apps.accounts.tests.factories import make_player
from apps.content.tests.conftest import admin_client
from apps.economy.models import Wallet
from apps.economy.tests.helpers import run, signed_in_api
from apps.liveops import settings as live
from apps.liveops.models import LiveSetting
from apps.liveops.services import versions

pytestmark = pytest.mark.django_db


def active(**fields: object) -> Player:
    player = make_player(**fields)
    run(player)
    return player


def test_the_bootstrap_records_a_changed_client() -> None:
    api = signed_in_api()
    api.bootstrap(**{"x-client-version": "1.5.0+9", "x-platform": "ios"})
    player = api.player
    assert (player.platform, player.client_version) == ("ios", "1.5.0+9")


def test_the_bootstrap_writes_nothing_when_the_client_is_the_same() -> None:
    api = signed_in_api()
    api.bootstrap()
    before = Player.objects.get(pk=api.player_id).updated_at
    with time_machine.travel(timezone.now() + timedelta(seconds=5), tick=False):
        api.bootstrap()
    assert Player.objects.get(pk=api.player_id).updated_at == before


def test_active_counts_fold_the_build_and_skip_old_players() -> None:
    active(platform="android", client_version="1.3.0+57")
    active(platform="android", client_version="1.3.0")
    active(platform="android", client_version="1.4.0")
    old = active(platform="android", client_version="1.2.0")
    active(platform="android", client_version="")
    Wallet.objects.filter(player=old).update(last_active_at=timezone.now() - timedelta(days=8))
    assert versions.active_counts("android") == {
        "1.3.0": 2,
        "1.4.0": 1,
        versions.UNKNOWN: 1,
    }


def test_a_players_other_platform_is_not_counted() -> None:
    active(platform="ios", client_version="2.0.0")
    assert versions.active_counts("android") == {}


def test_blocked_counts_the_share_and_never_unknown() -> None:
    for version in ("1.3.0", "1.3.0+57", "1.4.0", ""):
        active(platform="android", client_version=version)
    count, share = versions.blocked("android", "1.4.0")
    assert (count, share) == (2, 0.5)
    count, share = versions.blocked("android", "9.9.9")
    assert (count, share) == (3, 0.75)  # the unknown version is never blocked
    assert versions.blocked("android", "1.0.0") == (0, 0.0)


def test_no_active_player_means_no_share() -> None:
    assert versions.blocked("android", "1.4.0") == (0, 0.0)


@pytest.fixture
def live_ops() -> Client:
    user = User.objects.create_user("liveops2", is_staff=True)
    user.groups.add(Group.objects.get(name="live_ops"))
    return admin_client(user)


PAGE = "/admin/liveops/livesetting/versions/"


@pytest.mark.urls("config.urls_admin")
def test_the_page_shows_the_versions(live_ops: Client) -> None:
    active(platform="android", client_version="1.3.0+57")
    response = live_ops.get(PAGE)
    assert response.status_code == 200
    assert b"1.3.0" in response.content


@pytest.mark.urls("config.urls_admin")
def test_the_preview_saves_only_after_the_confirm_step(
    live_ops: Client, live_settings: Callable[..., None]
) -> None:
    active(platform="android", client_version="1.2.0")
    live_settings(latest_client_version_android="1.4.0")
    preview = live_ops.post(PAGE, {"platform": "android", "minimum": "1.3.0"})
    assert preview.status_code == 200
    assert b"would block" in preview.content
    assert LiveSetting.objects.get(key="min_client_version_android").value == "1.0.0"

    confirmed = live_ops.post(PAGE, {"platform": "android", "minimum": "1.3.0", "confirm": "1"})
    assert confirmed.status_code == 302
    assert LiveSetting.objects.get(key="min_client_version_android").value == "1.3.0"
    live.refresh()
    assert live.current()["min_client_version_android"] == "1.3.0"


@pytest.mark.urls("config.urls_admin")
def test_a_minimum_above_the_latest_is_refused(
    live_ops: Client, live_settings: Callable[..., None]
) -> None:
    live_settings(latest_client_version_android="1.4.0")
    response = live_ops.post(PAGE, {"platform": "android", "minimum": "1.5.0", "confirm": "1"})
    assert response.status_code == 200
    assert LiveSetting.objects.get(key="min_client_version_android").value == "1.0.0"
