"""Fares and payments (RULES.md §6.1 to §6.4).

Mirrors `packages/trip_engine/lib/src/rules/fares.dart`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from wassal_solver.engine.model import DRIVER, TokenKind
from wassal_solver.engine.money import DENOMINATIONS, Pieces, fewest_pieces, scale
from wassal_solver.engine.rules import claims  # claims imports this module: read at call time
from wassal_solver.engine.rules.passengers import start_patience

if TYPE_CHECKING:
    from wassal_solver.engine.trip import Trip

__all__ = ["base_fare", "fare_of", "own_fare", "pay_now", "pay_rest", "scale", "scheduled_payments"]

_PERCENT = 100


def base_fare(tx: Trip, passenger: int) -> int:
    """The current fare of `passenger`'s destination: authored plus increases."""
    state = tx.state
    return (
        state.schedule[tx.course.dest_index[passenger]].fare_piasters + state.fare_increase_piasters
    )


def own_fare(tx: Trip, passenger: int) -> int:
    """`passenger`'s own fare: a student's is discounted and rounded up to the smallest coin."""
    base = base_fare(tx, passenger)
    if tx.course.archetype[passenger] != "student":
        return base
    coin = DENOMINATIONS[0]
    unit = _PERCENT * coin
    discounted = base * (_PERCENT - tx.course.definition.rules.student_discount_pct)
    return (discounted + unit - 1) // unit * coin


def fare_of(tx: Trip, passenger: int) -> int:
    """The fare `passenger` pays. A group payer pays their own, each listed member's, and their
    own base fare for each member the trip doesn't list."""
    own = own_fare(tx, passenger)
    if not tx.course.is_payer(passenger):
        return own
    members = tx.course.members_of.get(passenger, ())
    size = tx.course.definition.passengers[passenger].group_size or 1
    fare = own
    for member in members:
        fare += own_fare(tx, member)
    return fare + (size - 1 - len(members)) * base_fare(tx, passenger)


def pay_now(tx: Trip, passenger: int) -> None:
    """`passenger` pays now (§6.2): their authored pieces, topped up after a fare increase they
    weren't listed by, go to the driver in a fare token."""
    trip = tx.state
    state = trip.passengers[passenger]
    passenger_id = state.passenger_id
    fare = fare_of(tx, passenger)
    payment = Pieces.of_list(tx.course.payment[passenger])
    old_fare = passenger_id in trip.old_fare_payers
    if trip.fare_increase_piasters > 0 and not old_fare and payment.total < fare:
        payment = payment.plus(fewest_pieces(fare - payment.total))
    had_claim = passenger_id in trip.claims
    if had_claim:
        del trip.claims[passenger_id]
    state.fare_sent = True
    state.fare_piasters = fare
    state.balance = payment.total - fare
    state.never_pays = False
    if had_claim:
        state.claim_resolved = True
    _close_disputes_without_liar(tx, passenger_id)
    start_patience(tx, passenger)
    _send_fare(tx, passenger_id, payment)


def _close_disputes_without_liar(tx: Trip, passenger_id: str) -> None:
    """Once `passenger_id` has paid, a dispute naming them whose other passenger paid too has no
    liar left, and closes with no event (§6.2)."""
    trip = tx.state
    index = tx.course.passenger_index
    settled = [
        key
        for key, dispute in trip.disputes.items()
        if passenger_id in (dispute.a, dispute.b)
        and trip.passengers[index[dispute.b if dispute.a == passenger_id else dispute.a]].fare_sent
    ]
    for key in settled:
        del trip.disputes[key]


def pay_rest(tx: Trip, passenger: int) -> None:
    """A passenger who owes the driver pays the rest in the fewest pieces (§6.4)."""
    state = tx.state.passengers[passenger]
    rest = -state.balance
    state.balance = 0
    _send_fare(tx, state.passenger_id, fewest_pieces(rest))


def _send_fare(tx: Trip, passenger_id: str, pieces: Pieces) -> None:
    tx.state.new_token(TokenKind.FARE, pieces, passenger_id, DRIVER, passenger_id)


def scheduled_payments(tx: Trip) -> None:
    """Scheduled payments (§3 step 4): each passenger whose time has come and who is able pays,
    unless they have paid, have an open claim, never pay, or are a group member."""
    trip = tx.state
    pays_at = tx.course.pays_at_ms
    for q, state in enumerate(trip.passengers):
        at = pays_at[q]
        if at is None or at > trip.t_ms:
            continue
        if (
            not state.is_able
            or state.fare_sent
            or state.never_pays
            or state.passenger_id in trip.claims
            or tx.course.is_member(q)
        ):
            continue
        if claims.claims_instead_of_paying(tx, q):
            claims.open_claim(tx, q, truthful=False)
        else:
            pay_now(tx, q)
