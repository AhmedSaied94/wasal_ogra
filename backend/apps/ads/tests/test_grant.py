"""A signed piggy callback grants once (B07 US1 AS1, FR-008, FR-009, FR-011, FR-012)."""

from __future__ import annotations

from typing import Any

import pytest
import time_machine
from django.core.management import call_command

from apps.accounts.models import Player
from apps.ads.models import AdReward
from apps.ads.tests.conftest import Callback
from apps.economy.models import Currency, LedgerEntry, Wallet
from apps.economy.tests.helpers import ledger_sum, wallet_of

pytestmark = pytest.mark.django_db


def test_a_signed_piggy_callback_grants(player: Player, callback: Callback) -> None:
    held = Wallet.objects.filter(pk=player.pk).values_list("state_version", flat=True)
    before = held.first() or 0
    response = callback(user_id=str(player.pk))
    assert (response.status_code, response.json()) == (200, {})
    row = AdReward.objects.get()
    assert (row.outcome, row.jenehat, row.bonat, row.player_id) == ("granted", 30, 2, player.pk)
    assert str(row.nonce) == response.nonce
    entries = LedgerEntry.objects.filter(player=player, reason="ssv_grant").order_by("currency")
    assert [(e.currency, e.delta, e.source, e.ref_type, e.ref_id) for e in entries] == sorted(
        [
            (Currency.JENEHAT, 30, "ssv", "ad_reward", str(row.pk)),
            (Currency.BONAT, 2, "ssv", "ad_reward", str(row.pk)),
        ]
    )
    wallet = wallet_of(player)
    assert (wallet.jenehat, wallet.bonat) == (30, 2)
    assert wallet.state_version == before + 1
    assert ledger_sum(player, Currency.BONAT) == wallet.bonat
    call_command("economy_check")


def test_the_game_day_is_cairo_at_processing_time(player: Player, callback: Callback) -> None:
    with time_machine.travel("2026-11-03 22:30:00Z", tick=False):  # 00:30 on the 4th in Cairo
        callback(user_id=str(player.pk))
    assert AdReward.objects.get().game_date.isoformat() == "2026-11-04"


def test_the_callback_never_names_the_amount(player: Player, callback: Callback) -> None:
    callback(user_id=str(player.pk), reward_amount="999")
    row = AdReward.objects.get()
    assert (row.reward_amount, row.jenehat, row.bonat) == (999, 30, 2)


def test_a_zero_amount_writes_no_entry(
    player: Player, callback: Callback, live_settings: Any
) -> None:
    live_settings(ads_morning_piggy_bonat=0)
    callback(user_id=str(player.pk))
    entries = LedgerEntry.objects.filter(player=player, reason="ssv_grant")
    assert [(e.currency, e.delta) for e in entries] == [(Currency.JENEHAT, 30)]
    assert AdReward.objects.get().bonat == 0


def test_a_player_without_a_wallet_gets_one(player: Player, callback: Callback) -> None:
    Wallet.objects.filter(pk=player.pk).delete()
    callback(user_id=str(player.pk))
    assert (wallet_of(player).jenehat, wallet_of(player).bonat) == (30, 2)
