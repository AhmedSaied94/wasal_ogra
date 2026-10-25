"""The ledger invariant, run by the restore drill and `economy_check` (FR-010, SC-009).

For every player and each currency, the wallet balance equals the sum of the player's ledger
entries. One grouped aggregate, with the currencies as parameters.
"""

from __future__ import annotations

from typing import Any

import psycopg

from apps.common.services.invariants import register

MAX_LISTED = 10

QUERY = """
SELECT w.player_id
FROM economy_wallet AS w
LEFT JOIN (
    SELECT player_id,
           COALESCE(SUM(delta) FILTER (WHERE currency = %s), 0) AS jenehat,
           COALESCE(SUM(delta) FILTER (WHERE currency = %s), 0) AS bonat
    FROM economy_ledgerentry
    GROUP BY player_id
) AS l ON l.player_id = w.player_id
WHERE w.jenehat <> COALESCE(l.jenehat, 0) OR w.bonat <> COALESCE(l.bonat, 0)
UNION
SELECT l.player_id
FROM economy_ledgerentry AS l
LEFT JOIN economy_wallet AS w ON w.player_id = l.player_id
WHERE w.player_id IS NULL
ORDER BY 1
"""


@register("economy.wallet_equals_ledger")
def wallet_equals_ledger(connection: psycopg.Connection[Any]) -> tuple[bool, str]:
    """Players whose wallet differs from their ledger, or who have entries and no wallet."""
    total = connection.execute("SELECT count(*) FROM economy_wallet").fetchone()
    differing = connection.execute(QUERY, ["JENEHAT", "BONAT"]).fetchall()
    count = total[0] if total else 0
    if not differing:
        return True, f"{count} wallets equal their ledger, 0 players differ"
    listed = ", ".join(str(player_id) for (player_id,) in differing[:MAX_LISTED])
    return False, f"{len(differing)} players differ: {listed}"
