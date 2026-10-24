"""What a conflict shows of each player (B02 research R7, FR-025)."""

from __future__ import annotations

from typing import Any

from apps.accounts.models import Player

# The glossary's first chapter: where every player starts.
FIRST_CHAPTER = "ch1_first_job"


def summarize(player: Player) -> dict[str, Any]:
    """The player's progress as the server holds it now. Nothing personal.

    B03 replaces `chapter_id` and `bonat` with the player's own, from its story and wallet tables.
    Until then they are the starting values, which is what every player has.
    """
    return {"driver_level": player.driver_level, "chapter_id": FIRST_CHAPTER, "bonat": 0}
