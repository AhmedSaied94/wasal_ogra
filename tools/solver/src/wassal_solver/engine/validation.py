"""Refusals at start (RULES.md §2.1, M01 data-model "Validation").

Mirrors `packages/trip_engine/lib/src/validation.dart`: the same checks in the same order, with
the same codes, paths and messages. The definition is assumed to pass `trip.schema.json`.
"""

from __future__ import annotations

from collections.abc import Callable, Collection, Mapping, Sequence
from dataclasses import dataclass
from enum import StrEnum

from wassal_content.engine import ParameterRule
from wassal_content.models import TripDefinition

from wassal_solver.engine.capabilities import SUPPORTED
from wassal_solver.engine.params import TripParams

_SEED_MAX = 0xFFFFFFFF


class RefusalCode(StrEnum):
    BAD_SEED = "bad_seed"
    BAD_PARAMS = "bad_params"
    DUPLICATE_ID = "duplicate_id"
    UNKNOWN_SEAT = "unknown_seat"
    UNKNOWN_STATION = "unknown_station"
    STATIONS_OUT_OF_ORDER = "stations_out_of_order"
    BOARD_AFTER_DEST = "board_after_dest"
    SEAT_TAKEN_AT_START = "seat_taken_at_start"
    UNKNOWN_PASSENGER = "unknown_passenger"
    GROUP_MISMATCH = "group_mismatch"
    UNSUPPORTED_ARCHETYPE = "unsupported_archetype"
    UNSUPPORTED_EVENT = "unsupported_event"
    EVENT_PARAM = "event_param"
    PICKUP_CONFLICT = "pickup_conflict"


@dataclass(frozen=True, slots=True)
class Refusal:
    """One problem: its code, the path of the offending field (`seed`, `params.<key>`, or a JSON
    path into the definition) and an English message for developers."""

    code: RefusalCode
    path: str
    message: str

    def to_json(self) -> dict[str, str]:
        return {"code": self.code.value, "path": self.path, "message": self.message}

    def __str__(self) -> str:
        return f"{self.code.value} at {self.path}: {self.message}"


class TripRefused(Exception):
    """Raised by `start` with every problem found."""

    def __init__(self, refusals: Sequence[Refusal]) -> None:
        self.refusals = tuple(refusals)
        super().__init__("; ".join(str(refusal) for refusal in self.refusals))


_Refuse = Callable[[RefusalCode, str, str], None]


def validate(
    definition: TripDefinition,
    params: TripParams,
    seed: int,
    *,
    archetypes: Collection[str] = SUPPORTED.archetypes,
    events: Collection[str] = SUPPORTED.events.keys(),
) -> list[Refusal]:
    """Every problem of `definition` with `params` and `seed`. Tests narrow `archetypes` and
    `events` to check the unsupported codes."""
    out: list[Refusal] = []

    def refuse(code: RefusalCode, path: str, message: str) -> None:
        out.append(Refusal(code, path, message))

    if seed < 1 or seed > _SEED_MAX:
        refuse(RefusalCode.BAD_SEED, "seed", f"the seed {seed} is outside 1..2^32-1")
    for problem in params.problems():
        refuse(RefusalCode.BAD_PARAMS, f"params.{problem.key}", problem.message)

    seats = _unique([seat.seat_id for seat in definition.seats], "$.seats", "seat_id", refuse)
    stations = _unique(
        [station.station_id for station in definition.stations],
        "$.stations",
        "station_id",
        refuse,
    )
    passengers = _unique(
        [passenger.passenger_id for passenger in definition.passengers],
        "$.passengers",
        "passenger_id",
        refuse,
    )

    for i in range(1, len(definition.stations)):
        if definition.stations[i].at_seconds <= definition.stations[i - 1].at_seconds:
            refuse(
                RefusalCode.STATIONS_OUT_OF_ORDER,
                f"$.stations[{i}].at_seconds",
                "station times must strictly increase",
            )

    picked_up = _pickups(definition, refuse)
    seated_at_start: set[str] = set()
    seat_ids = set(seats)
    for i, passenger in enumerate(definition.passengers):
        path = f"$.passengers[{i}]"
        if passenger.archetype.value not in archetypes:
            refuse(
                RefusalCode.UNSUPPORTED_ARCHETYPE,
                f"{path}.archetype",
                f"the engine does not support {passenger.archetype.value}",
            )
        if passenger.seat_id not in seat_ids:
            refuse(RefusalCode.UNKNOWN_SEAT, f"{path}.seat_id", f"no seat {passenger.seat_id}")
        dest = _index(stations, passenger.dest_station_id)
        if dest < 0:
            refuse(
                RefusalCode.UNKNOWN_STATION,
                f"{path}.dest_station_id",
                f"no station {passenger.dest_station_id}",
            )
        board = passenger.board_station_id
        if board is not None:
            board_index = _index(stations, board)
            if board_index < 0:
                refuse(
                    RefusalCode.UNKNOWN_STATION, f"{path}.board_station_id", f"no station {board}"
                )
            elif dest >= 0 and board_index >= dest:
                refuse(
                    RefusalCode.BOARD_AFTER_DEST,
                    f"{path}.board_station_id",
                    f"boards at {board}, not before {passenger.dest_station_id}",
                )
        aboard_at_start = board is None and passenger.passenger_id not in picked_up
        if aboard_at_start:
            if passenger.seat_id in seated_at_start:
                refuse(
                    RefusalCode.SEAT_TAKEN_AT_START,
                    f"{path}.seat_id",
                    f"two passengers start in {passenger.seat_id}",
                )
            seated_at_start.add(passenger.seat_id)

    _groups(definition, refuse)
    _events(definition, passengers, events, refuse)
    return out


def _index(ids: list[str], wanted: str) -> int:
    try:
        return ids.index(wanted)
    except ValueError:
        return -1


def _unique(ids: list[str], where: str, name: str, refuse: _Refuse) -> list[str]:
    seen: set[str] = set()
    for i, value in enumerate(ids):
        if value in seen:
            refuse(RefusalCode.DUPLICATE_ID, f"{where}[{i}].{name}", f"duplicate id {value}")
        seen.add(value)
    return ids


def _pickups(definition: TripDefinition, refuse: _Refuse) -> set[str]:
    """Passengers listed by a `roadside_pickup`, with pickup conflicts refused."""
    boards = {p.passenger_id for p in definition.passengers if p.board_station_id is not None}
    picked: set[str] = set()
    for i, event in enumerate(definition.events):
        if event.event_id.value != "roadside_pickup":
            continue
        for j, passenger_id in enumerate(event.passenger_ids or ()):
            if passenger_id in picked or passenger_id in boards:
                refuse(
                    RefusalCode.PICKUP_CONFLICT,
                    f"$.events[{i}].passenger_ids[{j}]",
                    f"{passenger_id} is boarded by more than one pickup or station",
                )
            picked.add(passenger_id)
    return picked


def _groups(definition: TripDefinition, refuse: _Refuse) -> None:
    first_size: dict[str, int] = {}
    members: dict[str, int] = {}
    payers: dict[str, int] = {}
    first_index: dict[str, int] = {}
    for i, passenger in enumerate(definition.passengers):
        path = f"$.passengers[{i}]"
        group = passenger.group_id
        is_payer = passenger.archetype.value == "group_payer"
        if group is None:
            if is_payer:
                refuse(
                    RefusalCode.GROUP_MISMATCH, f"{path}.group_id", "a group_payer needs a group"
                )
            elif passenger.group_size is not None:
                refuse(
                    RefusalCode.GROUP_MISMATCH, f"{path}.group_size", "a group_size needs a group"
                )
            continue
        first_index.setdefault(group, i)
        size = passenger.group_size
        if size is None:
            refuse(RefusalCode.GROUP_MISMATCH, f"{path}.group_size", f"{group} needs a group_size")
        elif first_size.setdefault(group, size) != size:
            refuse(
                RefusalCode.GROUP_MISMATCH,
                f"{path}.group_size",
                f"{group} has group_size {first_size[group]} elsewhere",
            )
        count = members[group] = members.get(group, 0) + 1
        limit = first_size.get(group)
        if limit is not None and count > limit:
            refuse(RefusalCode.GROUP_MISMATCH, f"{path}.group_id", f"{group} has more than {limit}")
        if is_payer:
            payer_count = payers[group] = payers.get(group, 0) + 1
            if payer_count > 1:
                refuse(
                    RefusalCode.GROUP_MISMATCH, f"{path}.archetype", f"{group} has two group_payers"
                )
    for group, i in first_index.items():
        if group not in payers:
            refuse(
                RefusalCode.GROUP_MISMATCH,
                f"$.passengers[{i}].group_id",
                f"{group} has no group_payer",
            )


def _events(
    definition: TripDefinition,
    passengers: list[str],
    supported: Collection[str],
    refuse: _Refuse,
) -> None:
    grouped = {p.passenger_id for p in definition.passengers if p.group_id is not None}
    stations = {station.station_id for station in definition.stations}
    known = set(passengers)
    for i, event in enumerate(definition.events):
        path = f"$.events[{i}]"
        event_id = event.event_id.value
        if event_id not in supported:
            refuse(
                RefusalCode.UNSUPPORTED_EVENT,
                f"{path}.event_id",
                f"the engine does not support {event_id}",
            )
            continue
        for j, passenger_id in enumerate(event.passenger_ids or ()):
            if passenger_id not in known:
                refuse(
                    RefusalCode.UNKNOWN_PASSENGER,
                    f"{path}.passenger_ids[{j}]",
                    f"no passenger {passenger_id}",
                )
        if event.station_id is not None and event.station_id not in stations:
            refuse(
                RefusalCode.UNKNOWN_STATION, f"{path}.station_id", f"no station {event.station_id}"
            )
        rules: Mapping[str, ParameterRule] = SUPPORTED.events.get(event_id, {})
        values: dict[str, int | tuple[str, ...] | str | None] = {
            "passenger_ids": event.passenger_ids,
            "station_id": event.station_id,
            "amount_piasters": event.amount_piasters,
            "seconds": event.seconds,
        }
        for name, value in values.items():
            problem = _param_problem(rules.get(name), value, grouped)
            if problem is not None:
                suffix, message = problem
                refuse(RefusalCode.EVENT_PARAM, f"{path}.{name}{suffix}", message)


def _param_problem(
    rule: ParameterRule | None, value: int | tuple[str, ...] | str | None, grouped: set[str]
) -> tuple[str, str] | None:
    """The problem with one event parameter, as (path suffix, message), or None."""
    if rule is None:
        return None if value is None else ("", "not allowed for this event")
    if value is None:
        return ("", "required") if rule.required else None
    if isinstance(value, int):
        if rule.minimum is not None and value < rule.minimum:
            return ("", f"below {rule.minimum}")
        if rule.maximum is not None and value > rule.maximum:
            return ("", f"above {rule.maximum}")
        if rule.one_of is not None and value not in rule.one_of:
            return ("", f"must be one of {list(rule.one_of)}")
    elif isinstance(value, tuple):
        if rule.min_items is not None and len(value) < rule.min_items:
            return ("", f"fewer than {rule.min_items}")
        if rule.max_items is not None and len(value) > rule.max_items:
            return ("", f"more than {rule.max_items}")
        if rule.no_group_members:
            for j, passenger_id in enumerate(value):
                if passenger_id in grouped:
                    return (f"[{j}]", f"{passenger_id} is in a group")
    return None
