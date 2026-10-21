"""One 33 ms logic step, in the fixed order of RULES.md §3.

Mirrors `packages/trip_engine/lib/src/rules/step.dart`. The caller checks that the trip is
running (§3.1): a trip that isn't doesn't move.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.clock import STEP_MS
from wassal_solver.engine.rules.aids import complete_breaks, ledger_peek_timer
from wassal_solver.engine.rules.authored_events import authored_events
from wassal_solver.engine.rules.chain import drop_deadlines, move_tokens
from wassal_solver.engine.rules.fares import scheduled_payments
from wassal_solver.engine.rules.passengers import (
    alertness_timers,
    attention_timers,
    drain_patience,
)
from wassal_solver.engine.rules.reputation import failure_check
from wassal_solver.engine.rules.stations import (
    end_check,
    reach_deadlines,
    reach_stations,
    warn_station,
)

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip


def step_trip(tx: Trip) -> None:
    """Advances a running trip by one step, changing its state in place."""
    tx.state.t_ms += STEP_MS
    # §3.2: alertness timers, the ledger peek, dropped tokens, pending breaks.
    alertness_timers(tx)
    attention_timers(tx)
    ledger_peek_timer(tx)
    drop_deadlines(tx)
    complete_breaks(tx)
    authored_events(tx)
    scheduled_payments(tx)
    move_tokens(tx)
    drain_patience(tx)
    warn_station(tx)
    reach_deadlines(tx)
    reach_stations(tx)
    failure_check(tx)
    end_check(tx)
