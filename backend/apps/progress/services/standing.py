"""A player's progress as the unlock rules read it, from the database (B03 research R6).

For reads outside a sync batch: the conflict summary and the state snapshot. A batch builds the
same view from its own in-memory state (`BatchState.player_view`).
"""

from __future__ import annotations

from apps.accounts.models import Player
from apps.progress.models import Ownership, TripProgress
from apps.progress.services.unlocks import PlayerView


def player_view(player: Player) -> PlayerView:
    stars = dict(TripProgress.objects.filter(player=player).values_list("trip_id", "best_stars"))
    owned = frozenset(Ownership.objects.filter(player=player).values_list("kind", "sku_id"))
    return PlayerView(best_stars=stars, owned=owned)
