"""The mirror's state (data-model.md "Mirror state", M01 data-model "State" and "TripResult").

Mirrors `packages/trip_engine/lib/src/model/`. The state is a tree of `@dataclass(slots=True)`
objects that a step changes in place, like Dart's `Transition` (research R2). It has no event list
and no PRNG state (research R3). `clone()` copies field by field, for the solver's branches. The
small records are frozen, so a clone can share them.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from wassal_content.models import BoosterId

from wassal_solver.engine.money import Pieces

DRIVER = "DRIVER"
"""The holder that is the driver. Any other holder is a passenger id (Dart's `Holder`)."""


class TripStatus(StrEnum):
    RUNNING = "running"
    PAUSED = "paused"
    FAILED = "failed"
    FINISHED = "finished"
    ABANDONED = "abandoned"


class Presence(StrEnum):
    WAITING = "waiting"
    """Not boarded yet."""
    ABOARD = "aboard"
    GONE = "gone"


class Alertness(StrEnum):
    """The alertness state machine of M01 data-model."""

    ASLEEP = "asleep"
    WAKING = "waking"
    AWAKE = "awake"
    MUTED = "muted"
    ATTENTIVE = "attentive"


class AlightOutcome(StrEnum):
    THANKED = "thanked"
    FIGHT = "fight"
    LEFT_UNPAID = "left_unpaid"
    MISSED_STOP = "missed_stop"


class TokenKind(StrEnum):
    FARE = "fare"
    CHANGE = "change"
    RETURNED = "return"
    REDIRECT = "redirect"
    BREAK_OUT = "break_out"
    BREAK_IN = "break_in"


TOWARD_DRIVER = frozenset({TokenKind.FARE, TokenKind.RETURNED, TokenKind.BREAK_IN})
"""Fares, returns and the second half of a change request travel to the driver; the rest travel
to a passenger."""


class MistakeKind(StrEnum):
    OVER = "over"
    """Gave more than was owed; the amount is the excess."""
    NOT_OWED = "not_owed"
    """Gave change to a passenger who hadn't paid or was owed nothing; the amount is the token."""
    UNRETURNED = "unreturned"
    """A passenger got off still owed change; the amount is what they were owed."""


class RepCause(StrEnum):
    """Why reputation changed, in M01's order. Losses are recorded in `reputation_lost`."""

    FIGHT = "fight"
    FALSE_ACCUSATION = "false_accusation"
    MISSED_STOP = "missed_stop"
    SHORT_CHANGE = "short_change"
    IMPATIENT = "impatient"
    CHANGE_REQUEST_DECLINED = "change_request_declined"
    EXACT_CHANGE = "exact_change"
    LIAR_CAUGHT = "liar_caught"
    REVIVE = "revive"


class TripOutcome(StrEnum):
    FINISHED = "finished"
    FAILED = "failed"
    ABANDONED = "abandoned"


@dataclass(slots=True)
class PassengerState:
    """One passenger (M01 data-model "PassengerState")."""

    passenger_id: str
    presence: Presence
    seat_id: str
    """Their seat. They sit in it only while aboard."""
    alertness: Alertness
    alert_until_ms: int | None = None
    """When `waking` ends, `awake` ends (sleeper), or `attentive` ends."""
    taps: int = 0
    """Taps while muted. Reset when attentive."""
    fare_sent: bool = False
    fare_piasters: int | None = None
    """Fixed when the fare is sent, including the group sum for a payer."""
    balance: int = 0
    """Payment minus fare: above 0 change is owed, below 0 the passenger owes."""
    paid_in: int = 0
    """Fare money from this passenger that reached the driver."""
    patience_ms: int | None = None
    patience_start_ms: int | None = None
    half_patience_spoken: bool = False
    impatient: bool = False
    claim_resolved: bool = False
    never_pays: bool = False
    deadline_ms: int | None = None
    pickup_due: bool = False
    outcome: AlightOutcome | None = None

    @property
    def is_able(self) -> bool:
        """Aboard, and awake or attentive."""
        return self.presence is Presence.ABOARD and (
            self.alertness is Alertness.AWAKE or self.alertness is Alertness.ATTENTIVE
        )

    @property
    def is_owed(self) -> bool:
        """The fare is sent and change is owed."""
        return self.fare_sent and self.balance > 0

    def clone(self) -> PassengerState:
        return PassengerState(
            self.passenger_id,
            self.presence,
            self.seat_id,
            self.alertness,
            self.alert_until_ms,
            self.taps,
            self.fare_sent,
            self.fare_piasters,
            self.balance,
            self.paid_in,
            self.patience_ms,
            self.patience_start_ms,
            self.half_patience_spoken,
            self.impatient,
            self.claim_resolved,
            self.never_pays,
            self.deadline_ms,
            self.pickup_due,
            self.outcome,
        )

    def to_json(self) -> dict[str, object]:
        out: dict[str, object] = {
            "passenger_id": self.passenger_id,
            "presence": self.presence.value,
            "seat_id": self.seat_id,
            "alertness": self.alertness.value,
        }
        if self.alert_until_ms is not None:
            out["alert_until_ms"] = self.alert_until_ms
        out["taps"] = self.taps
        out["fare_sent"] = self.fare_sent
        if self.fare_piasters is not None:
            out["fare_piasters"] = self.fare_piasters
        out["balance"] = self.balance
        out["paid_in"] = self.paid_in
        if self.patience_ms is not None:
            out["patience_ms"] = self.patience_ms
        if self.patience_start_ms is not None:
            out["patience_start_ms"] = self.patience_start_ms
        out["half_patience_spoken"] = self.half_patience_spoken
        out["impatient"] = self.impatient
        out["claim_resolved"] = self.claim_resolved
        out["never_pays"] = self.never_pays
        if self.deadline_ms is not None:
            out["deadline_ms"] = self.deadline_ms
        out["pickup_due"] = self.pickup_due
        if self.outcome is not None:
            out["outcome"] = self.outcome.value
        return out


@dataclass(slots=True)
class MoneyToken:
    """Money in transit (M01 data-model "MoneyToken", RULES.md §5). The hop in progress is kept
    flat: `hop_to` is set while moving."""

    token_id: int
    """Creation order, from 1."""
    kind: TokenKind
    pieces: Pieces
    owner: str
    """The passenger it concerns: the payer of a fare or a return, the recipient of change."""
    target: str
    holder: str
    hop_to: str | None = None
    hop_elapsed_ms: int = 0
    hop_duration_ms: int = 0
    hops_done: int = 0
    """0 while on its first hop (for undo)."""
    blocked_by: str | None = None
    """The passenger stopping it, if any."""
    dropped_until_ms: int | None = None
    """Set by a bump: the deadline for `CollectDropped`."""

    @property
    def is_dropped(self) -> bool:
        return self.dropped_until_ms is not None

    def clone(self) -> MoneyToken:
        return MoneyToken(
            self.token_id,
            self.kind,
            self.pieces,
            self.owner,
            self.target,
            self.holder,
            self.hop_to,
            self.hop_elapsed_ms,
            self.hop_duration_ms,
            self.hops_done,
            self.blocked_by,
            self.dropped_until_ms,
        )

    def to_json(self) -> dict[str, object]:
        out: dict[str, object] = {
            "token_id": self.token_id,
            "kind": self.kind.value,
            "pieces": self.pieces.to_json(),
            "owner": self.owner,
            "target": self.target,
            "holder": self.holder,
        }
        if self.hop_to is not None:
            out["hop"] = {
                "to": self.hop_to,
                "elapsed_ms": self.hop_elapsed_ms,
                "duration_ms": self.hop_duration_ms,
            }
        out["hops_done"] = self.hops_done
        if self.blocked_by is not None:
            out["blocked_by"] = self.blocked_by
        if self.dropped_until_ms is not None:
            out["dropped_until_ms"] = self.dropped_until_ms
        return out


@dataclass(slots=True)
class StationState:
    """One station of the trip's schedule (M01 data-model "StationState")."""

    station_id: str
    at_ms: int
    """Current arrival time: the authored time plus every shift so far."""
    fare_piasters: int
    """Authored fare. The current fare adds `TripState.fare_increase_piasters`."""
    warned: bool = False

    def clone(self) -> StationState:
        return StationState(self.station_id, self.at_ms, self.fare_piasters, self.warned)

    def to_json(self) -> dict[str, object]:
        return {
            "station_id": self.station_id,
            "at_ms": self.at_ms,
            "fare_piasters": self.fare_piasters,
            "warned": self.warned,
        }


@dataclass(frozen=True, slots=True)
class Claim:
    """An open claim, keyed by passenger. `truthful` when they really sent their fare."""

    truthful: bool


@dataclass(frozen=True, slots=True)
class Dispute:
    """An open payment dispute, keyed by its event index."""

    a: str
    b: str


@dataclass(frozen=True, slots=True)
class ChangeRequest:
    """An open change request, keyed by passenger."""

    note_piasters: int


@dataclass(frozen=True, slots=True)
class PendingBreak:
    """A «حد معاه فكة؟» request that hasn't completed."""

    denomination: int
    completes_at_ms: int


@dataclass(frozen=True, slots=True)
class LastSend:
    """The last `SendHand`, for undo."""

    token_id: int
    until_ms: int


@dataclass(slots=True)
class Counters:
    """What a trip counts (M01 data-model "Counters")."""

    fights: int = 0
    """Fights at stops and false accusations."""
    lost_fares: int = 0
    missed_stops: int = 0
    impatient: int = 0
    caught_liars: int = 0
    tips_piasters: int = 0
    overpaid_piasters: int = 0

    def clone(self) -> Counters:
        return Counters(
            self.fights,
            self.lost_fares,
            self.missed_stops,
            self.impatient,
            self.caught_liars,
            self.tips_piasters,
            self.overpaid_piasters,
        )

    def to_json(self) -> dict[str, object]:
        return {
            "fights": self.fights,
            "lost_fares": self.lost_fares,
            "missed_stops": self.missed_stops,
            "impatient": self.impatient,
            "caught_liars": self.caught_liars,
            "tips_piasters": self.tips_piasters,
            "overpaid_piasters": self.overpaid_piasters,
        }


@dataclass(frozen=True, slots=True)
class Mistake:
    passenger_id: str
    kind: MistakeKind
    amount_piasters: int

    def to_json(self) -> dict[str, object]:
        return {
            "passenger_id": self.passenger_id,
            "kind": self.kind.value,
            "amount_piasters": self.amount_piasters,
        }


def reputation_lost_json(lost: dict[RepCause, int]) -> dict[str, int]:
    """`lost` in wire form, in RepCause order."""
    return {cause.value: lost[cause] for cause in RepCause if cause in lost}


@dataclass(frozen=True, slots=True)
class StarFlags:
    reached: bool
    no_fights: bool
    no_mistakes: bool

    def to_json(self) -> dict[str, object]:
        return {
            "reached": self.reached,
            "no_fights": self.no_fights,
            "no_mistakes": self.no_mistakes,
        }


@dataclass(frozen=True, slots=True)
class TripResult:
    """The outcome of a trip (M01 data-model "TripResult"), field for field."""

    trip_id: str
    rev: int
    outcome: TripOutcome
    stars: int
    """0..3, and 0 unless finished."""
    star_flags: StarFlags
    fares_collected_piasters: int
    """Σ `min(fare, paid_in)` over passengers who sent their fare."""
    overpaid_piasters: int
    tips_piasters: int
    earnings_jenehat: int
    """0 unless finished."""
    fights: int
    lost_fares: int
    missed_stops: int
    impatient: int
    caught_liars: int
    mistakes: tuple[Mistake, ...]
    reputation: int
    """The final reputation, 0..100."""
    reputation_lost: tuple[tuple[RepCause, int], ...]
    """Penalties by cause, in RepCause order; only causes with a loss."""
    duration_ms: int
    """The clock when the trip ended."""
    boosters_used: tuple[BoosterId, ...]
    revived: bool
    command_log_hash: str
    """Lowercase hex SHA-256 of the command log (M01 research R9)."""

    def to_json(self) -> dict[str, object]:
        return {
            "trip_id": self.trip_id,
            "rev": self.rev,
            "outcome": self.outcome.value,
            "stars": self.stars,
            "star_flags": self.star_flags.to_json(),
            "fares_collected_piasters": self.fares_collected_piasters,
            "overpaid_piasters": self.overpaid_piasters,
            "tips_piasters": self.tips_piasters,
            "earnings_jenehat": self.earnings_jenehat,
            "fights": self.fights,
            "lost_fares": self.lost_fares,
            "missed_stops": self.missed_stops,
            "impatient": self.impatient,
            "caught_liars": self.caught_liars,
            "mistakes": [mistake.to_json() for mistake in self.mistakes],
            "reputation": self.reputation,
            "reputation_lost": {cause.value: amount for cause, amount in self.reputation_lost},
            "duration_ms": self.duration_ms,
            "boosters_used": [booster.value for booster in self.boosters_used],
            "revived": self.revived,
            "command_log_hash": self.command_log_hash,
        }


@dataclass(slots=True)
class TripState:
    """The whole trip at one moment (M01 data-model "TripState"), minus events and the PRNG."""

    t_ms: int
    """The clock, a multiple of 33."""
    status: TripStatus
    reputation: int
    """0..100 as reported. It goes below 0 only in the change that fails the trip."""
    tray: Pieces
    hand: Pieces
    passengers: list[PassengerState]
    """In definition order, including those not yet aboard and those gone."""
    tokens: dict[int, MoneyToken]
    """Live tokens by id. Ids only grow, so the dict's order is id order."""
    next_token_id: int
    schedule: list[StationState]
    next_station_index: int
    """The index of the next unprocessed station; the station count once all are done."""
    events_fired: list[bool]
    """Per authored event: fired or skipped."""
    fare_increase_piasters: int
    old_fare_payers: set[str]
    """Passengers listed by any `fare_increase`. Only read for membership."""
    traffic_active: bool
    claims: dict[str, Claim]
    disputes: dict[int, Dispute]
    """Keyed by the event's index, in the order they opened."""
    change_requests: dict[str, ChangeRequest]
    pending_breaks: list[PendingBreak]
    breaks_used: int
    ledger_peek_until_ms: int | None
    last_send: LastSend | None
    counters: Counters
    mistakes: list[Mistake]
    reputation_lost: dict[RepCause, int]
    """Penalties applied, by cause."""
    boosters_used: list[BoosterId]
    revived: bool
    revivable: bool
    """False after a story-trip fight, or once revived."""
    commands_accepted: int
    """Against the cap of 1,200, which `Abandon` is exempt from."""
    result: TripResult | None
    """Set when the trip finishes, fails or is abandoned."""
    occupants: dict[str, int] | None = field(default=None, compare=False, repr=False)
    """Seat → aboard passenger, derived and rebuilt after anyone boards or leaves."""

    def occupant(self, seat_id: str) -> int | None:
        """The index of the passenger aboard in `seat_id`, or None."""
        occupants = self.occupants
        if occupants is None:
            occupants = self.occupants = {
                p.seat_id: i for i, p in enumerate(self.passengers) if p.presence is Presence.ABOARD
            }
        return occupants.get(seat_id)

    def set_presence(self, passenger: int, presence: Presence) -> None:
        self.passengers[passenger].presence = presence
        self.occupants = None

    def new_token(
        self, kind: TokenKind, pieces: Pieces, owner: str, target: str, holder: str
    ) -> MoneyToken:
        """Creates a token at `holder` with the next id."""
        token = MoneyToken(self.next_token_id, kind, pieces, owner, target, holder)
        self.next_token_id += 1
        self.tokens[token.token_id] = token
        return token

    def clone(self) -> TripState:
        return TripState(
            self.t_ms,
            self.status,
            self.reputation,
            self.tray,
            self.hand,
            [passenger.clone() for passenger in self.passengers],
            {token_id: token.clone() for token_id, token in self.tokens.items()},
            self.next_token_id,
            [station.clone() for station in self.schedule],
            self.next_station_index,
            list(self.events_fired),
            self.fare_increase_piasters,
            set(self.old_fare_payers),
            self.traffic_active,
            dict(self.claims),
            dict(self.disputes),
            dict(self.change_requests),
            list(self.pending_breaks),
            self.breaks_used,
            self.ledger_peek_until_ms,
            self.last_send,
            self.counters.clone(),
            list(self.mistakes),
            dict(self.reputation_lost),
            list(self.boosters_used),
            self.revived,
            self.revivable,
            self.commands_accepted,
            self.result,
            None if self.occupants is None else dict(self.occupants),
        )

    def to_json(self) -> dict[str, object]:
        """The canonical form tests compare, as Dart's `TripState.toJson()` minus the PRNG."""
        out: dict[str, object] = {
            "t_ms": self.t_ms,
            "status": self.status.value,
            "reputation": self.reputation,
            "tray": self.tray.to_json(),
            "hand": self.hand.to_json(),
            "passengers": [passenger.to_json() for passenger in self.passengers],
            "tokens": [token.to_json() for token in self.tokens.values()],
            "next_token_id": self.next_token_id,
            "schedule": [station.to_json() for station in self.schedule],
            "next_station": self.next_station_index,
            "events_fired": list(self.events_fired),
            "fare_increase_piasters": self.fare_increase_piasters,
            "old_fare_payers": sorted(self.old_fare_payers),
            "traffic_active": self.traffic_active,
            "claims": {key: {"truthful": claim.truthful} for key, claim in self.claims.items()},
            "disputes": {
                str(key): {"a": dispute.a, "b": dispute.b} for key, dispute in self.disputes.items()
            },
            "change_requests": {
                key: {"note_piasters": request.note_piasters}
                for key, request in self.change_requests.items()
            },
            "pending_breaks": [
                {"denomination": pending.denomination, "completes_at_ms": pending.completes_at_ms}
                for pending in self.pending_breaks
            ],
            "breaks_used": self.breaks_used,
        }
        if self.ledger_peek_until_ms is not None:
            out["ledger_peek_until_ms"] = self.ledger_peek_until_ms
        if self.last_send is not None:
            out["last_send"] = {
                "token_id": self.last_send.token_id,
                "until_ms": self.last_send.until_ms,
            }
        out["counters"] = self.counters.to_json()
        out["mistakes"] = [mistake.to_json() for mistake in self.mistakes]
        out["reputation_lost"] = reputation_lost_json(self.reputation_lost)
        out["boosters_used"] = [booster.value for booster in self.boosters_used]
        out["revived"] = self.revived
        out["revivable"] = self.revivable
        out["commands_accepted"] = self.commands_accepted
        if self.result is not None:
            out["result"] = self.result.to_json()
        return out
