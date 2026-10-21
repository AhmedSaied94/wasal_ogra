"""Claims (RULES.md §4.6, §7.4, §10.1): a false claimer says they paid instead of paying, and a
tap on a passenger who has paid makes them say so truthfully. The driver insists or believes them.

Mirrors `packages/trip_engine/lib/src/rules/claims.dart`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.model import Claim, RepCause
from wassal_solver.engine.rules import fares  # fares imports this module: read at call time
from wassal_solver.engine.rules.reputation import gain_reputation, lose_reputation

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip


def claims_instead_of_paying(tx: Trip, q: int) -> bool:
    """Whether `q` is a false claimer who hasn't had a claim resolved yet."""
    return tx.course.archetype[q] == "false_claimer" and not tx.state.passengers[q].claim_resolved


def open_claim(tx: Trip, q: int, *, truthful: bool) -> None:
    """`q` says they have paid, and the claim stays open until resolved."""
    tx.state.claims[tx.state.passengers[q].passenger_id] = Claim(truthful=truthful)


def resolve_claim(tx: Trip, q: int, claim: Claim, *, insist: bool) -> None:
    """`ResolveClaim` on `q`'s open `claim` (§4.6)."""
    if not insist:
        accept_claim(tx, q)
        return
    _close(tx, q)
    if claim.truthful:
        false_accusation(tx, q)
        return
    catch_liar(tx, q)
    fares.pay_now(tx, q)


def catch_liar(tx: Trip, q: int) -> None:
    """`q` lied about paying and is caught (§4.6, §4.7). They pay next."""
    gain_reputation(tx, RepCause.LIAR_CAUGHT, tx.params.rep_liar_caught)
    tx.state.counters.caught_liars += 1


def accept_claim(tx: Trip, q: int) -> None:
    """The driver believes `q`'s open claim, at a `ResolveClaim` or when `q` gets off (§9.3.1): a
    false claimer then never pays."""
    state = tx.state.passengers[q]
    claim = tx.state.claims.get(state.passenger_id)
    false_claim = claim is not None and not claim.truthful
    _close(tx, q)
    if false_claim:
        state.never_pays = True


def _close(tx: Trip, q: int) -> None:
    state = tx.state.passengers[q]
    tx.state.claims.pop(state.passenger_id, None)
    state.claim_resolved = True


def false_accusation(tx: Trip, q: int) -> None:
    """The driver wrongly accuses `q` (§10.1): reputation, and a fight in the sense of FR-057."""
    lose_reputation(tx, RepCause.FALSE_ACCUSATION, tx.params.rep_false_accusation)
    tx.state.counters.fights += 1
