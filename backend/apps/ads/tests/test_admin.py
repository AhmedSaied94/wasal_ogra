"""The ad rewards in the staff admin (B07 US3 AS3, FR-023, contracts/admin.md)."""

from __future__ import annotations

import pytest
from django.contrib.auth.models import Group
from django.db import transaction
from django.test import Client

from apps.accounts.models import Player, User
from apps.accounts.tests.factories import make_player
from apps.ads.models import AdReward
from apps.ads.tests.helpers import reward_row
from apps.content.tests.conftest import admin_client
from apps.economy.models import Currency, LedgerEntry
from apps.economy.services import ledger

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

LIST = "/admin/ads/adreward/"


def staff(username: str, group: str | None = None, *, superuser: bool = False) -> Client:
    user = User.objects.create_user(username, is_staff=True, is_superuser=superuser)
    if group:
        user.groups.add(Group.objects.get(name=group))
    return admin_client(user)


@pytest.fixture
def player() -> Player:
    return make_player()


@pytest.fixture
def granted(player: Player) -> AdReward:
    row = reward_row(player, transaction_id="txn-admin-1")
    with transaction.atomic():
        wallet = ledger.lock_wallet(player)
        for currency, delta in ((Currency.JENEHAT, 30), (Currency.BONAT, 2)):
            ledger.apply_now(
                wallet,
                currency=currency,
                delta=delta,
                reason=LedgerEntry.Reason.SSV_GRANT,
                source=LedgerEntry.Source.SSV,
                ref_type="ad_reward",
                ref_id=str(row.pk),
            )
    return row


@pytest.mark.parametrize("group", ["live_ops", "economy_ops"])
def test_the_two_groups_see_the_list_and_a_detail(group: str, granted: AdReward) -> None:
    client = staff(f"{group}-1", group)
    assert client.get(LIST).status_code == 200
    detail = client.get(f"{LIST}{granted.pk}/change/")
    assert detail.status_code == 200
    page = detail.content.decode()
    assert "jenehat +30" in page.lower()
    assert "bonat +2" in page.lower()


def test_filters_and_exact_searches(granted: AdReward, player: Player) -> None:
    other = reward_row(None, "unattributed", transaction_id="txn-admin-2")
    client = staff("ops-2", "economy_ops")
    for query, shown, hidden in (
        ("?outcome=granted", granted, other),
        ("?outcome=unattributed", other, granted),
        ("?placement=morning_piggy", granted, None),
        (f"?game_date__year={granted.game_date.year}", granted, None),
        (f"?q={player.pk}", granted, other),
        ("?q=txn-admin-2", other, granted),
        ("?q=txn-admin", None, granted),  # exact, never a prefix
    ):
        page = client.get(LIST + query).content.decode()
        if shown is not None:
            assert f"/{shown.pk}/change/" in page, query
        if hidden is not None:
            assert f"/{hidden.pk}/change/" not in page, query


def test_no_one_adds_changes_or_deletes(granted: AdReward) -> None:
    root = staff("root-1", superuser=True)
    for path in (f"{LIST}add/", f"{LIST}{granted.pk}/delete/"):
        assert root.get(path).status_code == 403
    assert root.post(f"{LIST}{granted.pk}/change/", {"jenehat": 999}).status_code == 403
    assert "delete_selected" not in root.get(LIST).content.decode()
    assert AdReward.objects.get(pk=granted.pk).jenehat == 30


@pytest.mark.parametrize("group", ["content_author", "player_support"])
def test_other_groups_see_nothing(group: str, granted: AdReward) -> None:
    assert staff(f"{group}-1", group).get(LIST).status_code == 403


def test_the_player_page_links_the_rewards(granted: AdReward, player: Player) -> None:
    page = staff("ops-3", "economy_ops").get(f"/admin/accounts/player/{player.pk}/change/")
    assert page.status_code == 200
    text = page.content.decode()
    assert f"{LIST}?q={player.pk}" in text
    assert "Morning piggy today" in text
