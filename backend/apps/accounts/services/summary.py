"""What a conflict shows of each player (B02 research R7, FR-025; B03 research R16, FR-038)."""

from __future__ import annotations

from typing import Any

from apps.accounts.models import Player
from apps.content.services import lookups
from apps.economy.models import Wallet
from apps.progress.services import standing, unlocks

# The glossary's first chapter: where every player starts.
FIRST_CHAPTER = "ch1_first_job"


def summarize(player: Player) -> dict[str, Any]:
    """The player's progress as the server holds it now. Nothing personal, and read-only: a player
    with no wallet yet shows the starting values, and none is created.

    `chapter_id` is where the player is in the current pack's story (`unlocks.current_chapter`),
    or the first chapter when no pack is published.
    """
    bonat = Wallet.objects.filter(player=player).values_list("bonat", flat=True).first() or 0
    version = lookups.current_version()
    rules = lookups.rules(version) if version is not None else None
    chapter = unlocks.current_chapter(rules, standing.player_view(player)) if rules else None
    return {
        "driver_level": player.driver_level,
        "chapter_id": chapter or FIRST_CHAPTER,
        "bonat": bonat,
    }
