"""`AdReward`'s constraints and its guarded queryset (B07 data-model.md)."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Any

import pytest
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.accounts.models import Player
from apps.ads.models import AdReward, RewardRecordLocked

pytestmark = pytest.mark.django_db

Outcome = AdReward.Outcome


def reward(player: Player | None = None, **fields: Any) -> AdReward:
    values: dict[str, Any] = {
        "transaction_id": uuid.uuid4().hex,
        "player": player,
        "placement": "morning_piggy",
        "nonce": uuid.uuid4(),
        "reward_amount": 1,
        "key_id": 1,
        "outcome": Outcome.UNATTRIBUTED,
        "game_date": date(2026, 11, 3),
        "created_at": timezone.now(),
    }
    values.update(fields)
    return AdReward.objects.create(**values)


def refused(**fields: Any) -> None:
    with pytest.raises(IntegrityError), transaction.atomic():
        reward(**fields)


def test_a_transaction_is_recorded_once() -> None:
    reward(transaction_id="t-1")
    refused(transaction_id="t-1")


def test_a_reference_is_held_once_but_null_is_not_a_reference() -> None:
    nonce = uuid.uuid4()
    reward(nonce=nonce)
    refused(nonce=nonce)
    reward(nonce=None)
    reward(nonce=None)


def test_amounts_only_when_granted(player: Player) -> None:
    refused(player=player, outcome=Outcome.CAP_REACHED, jenehat=30)
    refused(player=player, outcome=Outcome.CAP_REACHED, bonat=2)
    reward(player=player, outcome=Outcome.GRANTED, jenehat=30, bonat=2)


def test_a_grant_has_a_player() -> None:
    refused(outcome=Outcome.GRANTED, jenehat=30)


def test_shown_only_when_granted(player: Player) -> None:
    refused(player=player, outcome=Outcome.CAP_REACHED, shown_at=timezone.now())
    reward(player=player, outcome=Outcome.GRANTED, jenehat=30, shown_at=timezone.now())


def test_the_queryset_updates_only_shown_at(player: Player) -> None:
    row = reward(player=player, outcome=Outcome.GRANTED, jenehat=30)
    rows = AdReward.objects.filter(pk=row.pk)
    assert rows.update(shown_at=timezone.now()) == 1
    with pytest.raises(RewardRecordLocked):
        rows.update(jenehat=999)
    with pytest.raises(RewardRecordLocked):
        rows.update(shown_at=None, bonat=1)


def test_granted_rows_are_never_deleted(player: Player) -> None:
    granted = reward(player=player, outcome=Outcome.GRANTED, jenehat=30)
    other = reward()
    with pytest.raises(RewardRecordLocked):
        AdReward.objects.all().delete()
    with pytest.raises(RewardRecordLocked):
        granted.delete()
    assert AdReward.objects.filter(pk=other.pk).delete()[0] == 1
    assert AdReward.objects.filter(pk=granted.pk).exists()


def test_save_changes_only_shown_at(player: Player) -> None:
    row = reward(player=player, outcome=Outcome.GRANTED, jenehat=30)
    row.shown_at = timezone.now()
    row.save()
    row.jenehat = 999
    with pytest.raises(RewardRecordLocked):
        row.save()
    fresh = AdReward.objects.get(pk=row.pk)
    assert fresh.jenehat == 30
    assert fresh.shown_at is not None
