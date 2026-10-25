"""The content version an operation declares (B03 tasks.md T046, spec US2 scenario 8, FR-014,
research R2).

Every operation that reads the pack is checked against the version it was recorded with: a number
never published is `unknown_content_version`, one too old or no longer indexed is
`content_version_unsupported`, and an honest offline player on the previous version pays that
version's prices.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import timedelta
from typing import Any

import pytest
import time_machine
from django.utils import timezone
from pytest_django import Settings

from apps.accounts.models import Player
from apps.content.models import PackPriceIndex, PackRulesIndex
from apps.economy.models import Currency, LedgerEntry
from apps.economy.services import sync
from apps.economy.tests.helpers import grant, op, reasons, run, spend, trip_start, wallet_of

pytestmark = pytest.mark.django_db

Builder = Callable[[int], dict[str, Any]]

# A valid operation of each type that declares a content version, at version `v`.
BUILDERS: dict[str, Builder] = {
    "trip_start": lambda v: trip_start("line_hay.01", v),
    "spend_jenehat": lambda v: spend("item", "salon.nish", 400, v, variant="classic"),
    "spend_bonat": lambda v: spend("booster", "change_bag", 10, v),
    "story_progress": lambda v: op(
        "story_progress",
        {"chapter_id": "ch1_first_job", "scene_id": "the_stand", "content_version": v},
    ),
    "claim_request": lambda v: op(
        "claim_request", {"request_id": "req_nish_crystal", "content_version": v}
    ),
}


def versioned() -> list[str]:
    return sorted(t for t, r in sync.registered().items() if r.content_version)


def test_every_operation_that_reads_the_pack_has_a_case() -> None:
    assert set(versioned()) <= set(BUILDERS)


def nothing_applied(player: Player) -> None:
    wallet = wallet_of(player)
    assert (wallet.jenehat, wallet.bonat, wallet.fuel, wallet.state_version) == (1_000, 1_000, 5, 0)


@pytest.fixture
def funded(player: Player) -> Player:
    grant(player, Currency.JENEHAT, 1_000)
    grant(player, Currency.BONAT, 1_000)
    return player


@pytest.mark.parametrize("op_type", versioned())
def test_a_version_never_published_is_unknown(
    funded: Player, published_pack: int, op_type: str
) -> None:
    assert reasons(run(funded, BUILDERS[op_type](published_pack + 98))) == [
        "unknown_content_version"
    ]
    nothing_applied(funded)


@pytest.mark.parametrize("op_type", versioned())
def test_a_version_too_old_is_unsupported(
    funded: Player,
    published_packs: Callable[[int], list[int]],
    settings: Settings,
    op_type: str,
) -> None:
    long_ago = timezone.now() - timedelta(days=settings.SYNC_CONTENT_MAX_AGE_DAYS + 1)
    with time_machine.travel(long_ago, tick=False):
        [old] = published_packs(1)
    published_packs(1)  # the current one
    assert reasons(run(funded, BUILDERS[op_type](old))) == ["content_version_unsupported"]
    nothing_applied(funded)


@pytest.mark.parametrize("op_type", versioned())
def test_a_version_no_longer_indexed_is_unsupported(
    funded: Player, published_packs: Callable[[int], list[int]], op_type: str
) -> None:
    old, _ = published_packs(2)
    PackRulesIndex.objects.filter(version=old).delete()
    assert reasons(run(funded, BUILDERS[op_type](old))) == ["content_version_unsupported"]
    nothing_applied(funded)


def test_the_current_version_stays_supported_however_old(
    funded: Player, published_packs: Callable[[int], list[int]], settings: Settings
) -> None:
    long_ago = timezone.now() - timedelta(days=settings.SYNC_CONTENT_MAX_AGE_DAYS + 30)
    with time_machine.travel(long_ago, tick=False):
        [only] = published_packs(1)
    assert reasons(run(funded, trip_start("line_hay.01", only))) == ["accepted"]


def test_an_offline_player_pays_the_prices_of_their_version(
    funded: Player, published_packs: Callable[[int], list[int]]
) -> None:
    previous, current = published_packs(2)
    PackPriceIndex.objects.filter(version=current, sku_id="change_bag").update(amount=11)
    result = run(
        funded,
        spend("booster", "change_bag", 10, previous),
        spend("booster", "change_bag", 10, current),
        spend("booster", "change_bag", 11, current),
    )
    assert reasons(result) == ["accepted", "price_mismatch", "accepted"]
    deltas = LedgerEntry.objects.filter(player=funded, reason="booster_purchase")
    assert sorted(e.delta for e in deltas) == [-11, -10]
