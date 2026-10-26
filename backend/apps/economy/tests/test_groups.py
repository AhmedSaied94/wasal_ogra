"""The economy's staff groups (B03 tasks.md T080, contracts/admin.md "Groups and permissions")."""

from __future__ import annotations

from io import StringIO
from unittest import mock

import pytest
from django.contrib.auth.models import Group
from django.core.management import call_command

from apps.accounts.models import User

pytestmark = pytest.mark.django_db

SUPPORT_ADDS = {
    "economy.view_wallet",
    "economy.view_ledgerentry",
    "economy.view_processedop",
    "economy.view_inventory",
    "economy.view_grantrecord",
    "economy.view_playerflag",
    "economy.change_playerflag",
    "progress.view_ownership",
    "progress.view_tripprogress",
    "progress.view_storystate",
}
OPS_ADDS = {
    "economy.adjust_wallet",
    "economy.view_walletadjustment",
    "accounts.view_namefilterentry",
    "accounts.add_namefilterentry",
    "accounts.change_namefilterentry",
    "accounts.delete_namefilterentry",
}


def permissions(group: str) -> set[str]:
    return {
        f"{p.content_type.app_label}.{p.codename}"
        for p in Group.objects.get(name=group).permissions.select_related("content_type")
    }


def test_player_support_can_see_the_economy_and_review_flags() -> None:
    held = permissions("player_support")
    assert held >= SUPPORT_ADDS
    assert {"accounts.view_player", "accounts.change_player"} <= held  # B02's
    assert not held & OPS_ADDS


def test_economy_ops_has_support_and_the_two_writes() -> None:
    held = permissions("economy_ops")
    assert SUPPORT_ADDS | OPS_ADDS | {"accounts.view_player"} <= held
    assert "accounts.change_player" not in held  # the tester flag stays with support


def test_create_staff_puts_a_user_in_economy_ops() -> None:
    out = StringIO()
    with mock.patch("getpass.getpass", side_effect=["a-long-enough-password-1"] * 2):
        call_command("create_staff", "ops1", "--group", "economy_ops", stdout=out)
    user = User.objects.get(username="ops1")
    assert user.has_perm("economy.adjust_wallet")
    assert not user.has_perm("economy.delete_ledgerentry")
