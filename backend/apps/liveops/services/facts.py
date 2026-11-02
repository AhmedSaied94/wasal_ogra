"""What an offer rule may read about one player (B10 contracts/offers.md, research R12).

One player row (already loaded by authentication) and one `progress.StoryState` query, whatever the
number of offers. The purchase fields come from one function that B06 replaces.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime

from apps.accounts.models import Player
from apps.progress.models import StoryState


@dataclass(frozen=True)
class PlayerFacts:
    country: str
    installed_at: datetime
    has_purchase: bool
    entitlements: frozenset[str]
    chapters: Mapping[str, str]


def purchases(player: Player) -> tuple[bool, frozenset[str]]:
    """`(has a granted purchase, the entitlements held)`. B06 replaces this one function."""
    return False, frozenset()


def for_player(player: Player) -> PlayerFacts:
    """The facts of one offer listing. Two queries at most."""
    chapters = dict(StoryState.objects.filter(player=player).values_list("chapter_id", "status"))
    has_purchase, entitlements = purchases(player)
    return PlayerFacts(
        country=player.country,
        installed_at=player.created_at,
        has_purchase=has_purchase,
        entitlements=entitlements,
        chapters=chapters,
    )
