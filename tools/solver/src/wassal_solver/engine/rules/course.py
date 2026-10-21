"""What a trip's definition fixes for its whole run, worked out once at start so the rules never
search the definition: indexes, seats, groups.

Mirrors `packages/trip_engine/lib/src/rules/course.dart`.
"""

from __future__ import annotations

from wassal_content.models import TripDefinition, TripEvent

from wassal_solver.engine.clock import MS_PER_SECOND

_ROW_INDEX = {"front": 0, "A": 1, "B": 2, "C": 3, "D": 4}

LAST_NEAR_ROW = 1
"""The last row one hop from the driver: rows `front` and `A` are."""


class Course:
    """The definition's fixed facts, by passenger and station index."""

    __slots__ = (
        "archetype",
        "board_index",
        "definition",
        "dest_index",
        "events",
        "max_break_requests",
        "members_of",
        "passenger_ids",
        "passenger_index",
        "payer_of",
        "payment",
        "pays_at_ms",
        "picked_up",
        "seat_at",
        "seat_col",
        "seat_row",
        "station_count",
        "station_index",
    )

    def __init__(self, definition: TripDefinition) -> None:
        self.definition = definition
        passengers = definition.passengers
        self.passenger_ids: tuple[str, ...] = tuple(p.passenger_id for p in passengers)
        self.passenger_index: dict[str, int] = {p.passenger_id: i for i, p in enumerate(passengers)}
        self.station_index: dict[str, int] = {
            s.station_id: i for i, s in enumerate(definition.stations)
        }
        self.station_count = len(definition.stations)
        # Rows from the driver backwards: front 0, A 1, B 2, C 3, D 4.
        self.seat_row: dict[str, int] = {
            seat.seat_id: _ROW_INDEX[seat.row.value] for seat in definition.seats
        }
        self.seat_col: dict[str, str] = {seat.seat_id: seat.col.value for seat in definition.seats}
        # The seat at (row, column), if the vehicle has one.
        self.seat_at: dict[tuple[int, str], str] = {
            (_ROW_INDEX[seat.row.value], seat.col.value): seat.seat_id for seat in definition.seats
        }
        self.archetype: tuple[str, ...] = tuple(p.archetype.value for p in passengers)
        # Each passenger's authored payment, in piasters.
        self.payment: tuple[tuple[int, ...], ...] = tuple(
            tuple(int(piece) for piece in p.payment) for p in passengers
        )
        self.pays_at_ms: tuple[int | None, ...] = tuple(
            None if p.pays_at_seconds is None else p.pays_at_seconds * MS_PER_SECOND
            for p in passengers
        )
        self.dest_index: tuple[int, ...] = tuple(
            self.station_index.get(p.dest_station_id, 0) for p in passengers
        )
        self.board_index: tuple[int | None, ...] = tuple(
            None if p.board_station_id is None else self.station_index.get(p.board_station_id)
            for p in passengers
        )
        # Passengers listed by a `roadside_pickup`.
        picked_up: set[int] = set()
        for event in definition.events:
            if event.event_id.value != "roadside_pickup":
                continue
            for passenger_id in event.passenger_ids or ():
                index = self.passenger_index.get(passenger_id)
                if index is not None:
                    picked_up.add(index)
        self.picked_up = frozenset(picked_up)
        # For a group member, the index of the group's payer; for a payer, the members listed.
        payers = {
            p.group_id: i
            for i, p in enumerate(passengers)
            if p.group_id is not None and p.archetype.value == "group_payer"
        }
        payer_of: list[int | None] = []
        members_of: dict[int, list[int]] = {}
        for i, p in enumerate(passengers):
            payer = payers.get(p.group_id) if p.group_id is not None else None
            if payer is not None and payer != i:
                payer_of.append(payer)
                members_of.setdefault(payer, []).append(i)
            else:
                payer_of.append(None)
        self.payer_of: tuple[int | None, ...] = tuple(payer_of)
        self.members_of: dict[int, tuple[int, ...]] = {
            payer: tuple(members) for payer, members in members_of.items()
        }
        self.events: tuple[TripEvent, ...] = definition.events
        self.max_break_requests = definition.rules.max_break_requests

    def index_of(self, passenger_id: str) -> int:
        """The index of passenger `passenger_id`. Every id the rules hold is one."""
        return self.passenger_index[passenger_id]

    def is_member(self, passenger: int) -> bool:
        return self.payer_of[passenger] is not None

    def is_payer(self, passenger: int) -> bool:
        return self.archetype[passenger] == "group_payer"
