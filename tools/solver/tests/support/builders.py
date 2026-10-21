"""Small trip definitions built in code, ported from the Dart engine's `test/support/builders.dart`.

Every `build()` is a valid trip unless a test breaks it on purpose. Defaults: `micro_old` on
`line_gamaa`, seed 1, no events, rules with no discount and two breaks.
"""

from __future__ import annotations

import json
from functools import cache
from typing import Any

from wassal_content.models import LineId, TripDefinition, VehicleId, parse

from tests.paths import APP_TUNABLES
from wassal_solver.engine.params import TripParams

_COLS = ("r", "m", "l")


def seats_of(vehicle: str) -> list[dict[str, Any]]:
    """The seats of the two layouts the tests use: `tuktuk` (one row A) and `micro_old`."""
    if vehicle == VehicleId.TUKTUK:
        return [_seat("A", col) for col in _COLS]
    return [_seat("front", "r")] + [_seat(row, col) for row in ("A", "B", "C") for col in _COLS]


def _seat(row: str, col: str) -> dict[str, Any]:
    return {
        "seat_id": f"{row}_{col}",
        "row": row,
        "col": col,
        "reachable_by_driver": row in ("front", "A"),
    }


class TripBuilder:
    """A fluent builder of trip definitions; each method returns the builder."""

    def __init__(self, vehicle: str = VehicleId.MICRO_OLD, line: str = LineId.LINE_GAMAA) -> None:
        self.vehicle = str(vehicle)
        self.line = str(line)
        self._seed = 1
        self._max_earnings = 100
        self._kind = "regular"
        self._seats: list[dict[str, Any]] | None = None
        self._stations: list[dict[str, Any]] = []
        self._passengers: list[dict[str, Any]] = []
        self._events: list[dict[str, Any]] = []
        self._tray: dict[str, int] = {"100": 4, "50": 4, "500": 2}
        self._rules: dict[str, Any] = _rules()

    def seed(self, value: int) -> TripBuilder:
        self._seed = value
        return self

    def max_earnings(self, jenehat: int) -> TripBuilder:
        self._max_earnings = jenehat
        return self

    def story(self) -> TripBuilder:
        self._kind = "story"
        return self

    def seats(self, seats: list[dict[str, Any]]) -> TripBuilder:
        self._seats = seats
        return self

    def station(self, station_id: str, at_seconds: int, *, fare: int = 700) -> TripBuilder:
        self._stations.append(
            {"station_id": station_id, "at_seconds": at_seconds, "fare_piasters": fare}
        )
        return self

    def passenger(
        self,
        passenger_id: str,
        *,
        seat: str,
        dest: str,
        payment: list[int],
        archetype: str = "regular",
        board: str | None = None,
        pays_at: int | None = None,
        group: str | None = None,
        group_size: int | None = None,
        speech_keys: dict[str, str] | None = None,
        skin: str = "worker_blue",
    ) -> TripBuilder:
        spec: dict[str, Any] = {
            "passenger_id": passenger_id,
            "archetype": str(archetype),
            "skin": skin,
            "seat_id": seat,
            "dest_station_id": dest,
            "payment": list(payment),
        }
        optional = {
            "board_station_id": board,
            "pays_at_seconds": pays_at,
            "group_id": group,
            "group_size": group_size,
            "speech_keys": speech_keys,
        }
        spec.update({key: value for key, value in optional.items() if value is not None})
        self._passengers.append(spec)
        return self

    def event(
        self,
        event_id: str,
        at_seconds: int,
        *,
        passengers: list[str] | None = None,
        amount: int | None = None,
        seconds: int | None = None,
        station: str | None = None,
    ) -> TripBuilder:
        event: dict[str, Any] = {"event_id": str(event_id), "at_seconds": at_seconds}
        optional = {
            "passenger_ids": passengers,
            "amount_piasters": amount,
            "seconds": seconds,
            "station_id": station,
        }
        event.update({key: value for key, value in optional.items() if value is not None})
        self._events.append(event)
        return self

    def tray(self, counts: dict[int, int]) -> TripBuilder:
        self._tray = {str(denomination): count for denomination, count in counts.items()}
        return self

    def rules(
        self,
        *,
        student_discount_pct: int = 0,
        max_break_requests: int = 2,
        no_fights_required: bool = False,
    ) -> TripBuilder:
        self._rules = _rules(student_discount_pct, max_break_requests, no_fights_required)
        return self

    def document(self) -> dict[str, Any]:
        """The definition as JSON data, for a test to break before parsing."""
        return {
            "trip_id": f"{self.line}.01",
            "rev": 1,
            "kind": self._kind,
            "line_id": self.line,
            "vehicle_id": self.vehicle,
            "seed": self._seed,
            "seats": [dict(seat) for seat in self._seats or seats_of(self.vehicle)],
            "stations": [dict(station) for station in self._stations],
            "initial_tray": dict(self._tray),
            "rules": dict(self._rules),
            "passengers": [json.loads(json.dumps(spec)) for spec in self._passengers],
            "events": [json.loads(json.dumps(event)) for event in self._events],
            "star_rules": {"two": "no_fights", "three": "no_fights_no_mistakes"},
            "max_earnings_jenehat": self._max_earnings,
        }

    def build(self) -> TripDefinition:
        return definition_of(self.document())


def definition_of(document: dict[str, Any]) -> TripDefinition:
    parsed = parse("trip", document)
    assert isinstance(parsed, TripDefinition)
    return parsed


def _rules(
    student_discount_pct: int = 0, max_break_requests: int = 2, no_fights_required: bool = False
) -> dict[str, Any]:
    return {
        "student_discount_pct": student_discount_pct,
        "bag_fare_piasters": 0,
        "child_free_age": 6,
        "max_break_requests": max_break_requests,
        "no_fights_required": no_fights_required,
    }


@cache
def _bundled() -> str:
    return APP_TUNABLES.read_text(encoding="utf-8")


def bundled_tunables() -> dict[str, Any]:
    """The app's bundled tunables, the one source of balancing values (constitution VIII)."""
    loaded: dict[str, Any] = json.loads(_bundled())
    return loaded


def default_params(line: str = LineId.LINE_GAMAA) -> TripParams:
    """The bundled defaults resolved for `line`."""
    return TripParams.from_tunables(bundled_tunables(), line)


def params_with(overrides: dict[str, int], line: str = LineId.LINE_GAMAA) -> TripParams:
    """The defaults for `line` with `overrides` (wire keys) applied."""
    return TripParams.from_json({**default_params(line).to_json(), **overrides})
