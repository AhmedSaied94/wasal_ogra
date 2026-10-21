"""The rule numbers a trip runs with (M01 data-model "TripParams", research R5).

Mirrors `packages/trip_engine/lib/src/params.dart`. The values come from the app's tunables;
there are no defaults in code (constitution VIII).
"""

from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass, fields

from wassal_solver.engine.clock import STEP_MS
from wassal_solver.engine.money import scale


class ParamsError(ValueError):
    """A params object with a missing, unknown or non-integer key."""


@dataclass(frozen=True, slots=True)
class ParamProblem:
    """One out-of-bounds param, for the `bad_params` refusal."""

    key: str
    message: str


@dataclass(frozen=True, slots=True)
class TripParams:
    """The 28 params, in the wire order of M01 data-model "TripParams"."""

    trip_hop_ms: int
    trip_undo_window_ms: int
    rep_fight: int
    rep_false_accusation: int
    rep_missed_stop: int
    rep_liar_caught: int
    rep_exact_change: int
    rep_revive_to: int
    trip_station_warning_ms: int
    trip_hop_pct_hajja: int
    trip_hop_pct_chatty_row: int
    trip_group_redirect_hop_ms: int
    trip_wake_ms: int
    trip_sleeper_awake_ms: int
    trip_headphones_attentive_ms: int
    trip_patience_ms: int
    trip_patience_pct_hurry: int
    trip_patience_drain_pct_traffic: int
    trip_bump_collect_ms: int
    trip_break_min_piasters: int
    trip_break_delay_ms: int
    trip_tip_piasters_regular_customer: int
    booster_ledger_peek_ms: int
    booster_traffic_jam_ms: int
    booster_traffic_jam_max_per_trip: int
    rep_short_change: int
    rep_impatient: int
    rep_change_request_declined: int

    @staticmethod
    def from_json(json: Mapping[str, object]) -> TripParams:
        """The wire form, a flat object keyed by tunable name. Raises ParamsError naming a
        missing, unknown or non-integer key."""
        for key in json:
            if key not in _KEY_SET:
                raise ParamsError(f"unknown TripParams key: {key}")
        return _read(json, lambda key: key)

    @staticmethod
    def from_tunables(values: Mapping[str, object], line_id: str) -> TripParams:
        """Resolves a flat tunables map, such as the app's `tunables.json`, for `line_id`:
        `trip_hop_ms` comes from `trip_hop_ms_<line_id>`. Other keys are ignored."""
        hop = f"trip_hop_ms_{line_id}"
        return _read(values, lambda key: hop if key == "trip_hop_ms" else key)

    def to_json(self) -> dict[str, int]:
        return {key: getattr(self, key) for key in PARAM_KEYS}

    def problems(self) -> list[ParamProblem]:
        """Every value outside its bounds, and every percent that scales a hop or a hurried
        passenger's patience below one step. A scaled duration is checked only when its own
        params are within bounds."""
        own: list[ParamProblem] = []
        for key in PARAM_KEYS:
            value = getattr(self, key)
            low, high = _BOUNDS.get(key, (0, None))
            if value < low or (high is not None and value > high):
                own.append(
                    ParamProblem(
                        key,
                        f"{key} is {value}, below {low}"
                        if high is None
                        else f"{key} is {value}, outside {low}..{high}",
                    )
                )
        bad = {problem.key for problem in own}
        return own + self._scaled_problems(bad)

    def _scaled_problems(self, bad: set[str]) -> list[ParamProblem]:
        hops = "trip_hop_ms" not in bad
        hajja_ok = hops and "trip_hop_pct_hajja" not in bad
        chatty_ok = hops and "trip_hop_pct_chatty_row" not in bad
        hurry_ok = "trip_patience_ms" not in bad and "trip_patience_pct_hurry" not in bad
        hajja = scale(self.trip_hop_ms, self.trip_hop_pct_hajja)
        chatty = scale(self.trip_hop_ms, self.trip_hop_pct_chatty_row)
        both = scale(hajja, self.trip_hop_pct_chatty_row)
        hurry = scale(self.trip_patience_ms, self.trip_patience_pct_hurry)
        out: list[ParamProblem] = []
        if hajja_ok and hajja < STEP_MS:
            out.append(
                ParamProblem(
                    "trip_hop_pct_hajja", f"a hajja's hop would be {hajja} ms, below {STEP_MS}"
                )
            )
        if chatty_ok and (chatty < STEP_MS or (hajja_ok and hajja >= STEP_MS and both < STEP_MS)):
            out.append(
                ParamProblem(
                    "trip_hop_pct_chatty_row",
                    f"a hop in a chatty row would be {min(chatty, both)} ms, below {STEP_MS}",
                )
            )
        if hurry_ok and hurry < STEP_MS:
            out.append(
                ParamProblem(
                    "trip_patience_pct_hurry",
                    f"a hurried passenger's patience would be {hurry} ms, below {STEP_MS}",
                )
            )
        return out


PARAM_KEYS = tuple(field.name for field in fields(TripParams))
"""The 28 wire keys, in order."""

_KEY_SET = frozenset(PARAM_KEYS)

# Rule bounds, not balancing numbers (RULES.md §1.4, M01 data-model "TripParams"): a duration is
# at least a step, a percent is 1..1000, reputation is out of 100, and the two traffic-jam bounds
# keep the longest trip at 1,500 s. Every other param is at least 0.
_BOUNDS: Mapping[str, tuple[int, int | None]] = {
    "trip_hop_ms": (STEP_MS, None),
    "trip_group_redirect_hop_ms": (STEP_MS, None),
    "trip_patience_ms": (STEP_MS, None),
    "trip_hop_pct_hajja": (1, 1000),
    "trip_hop_pct_chatty_row": (1, 1000),
    "trip_patience_pct_hurry": (1, 1000),
    "trip_patience_drain_pct_traffic": (1, 1000),
    "rep_revive_to": (1, 100),
    "booster_traffic_jam_ms": (0, 60000),
    "booster_traffic_jam_max_per_trip": (0, 5),
}


def _read(json: Mapping[str, object], source: Callable[[str], str]) -> TripParams:
    values: dict[str, int] = {}
    for key in PARAM_KEYS:
        name = source(key)
        value = json.get(name)
        if type(value) is not int:
            raise ParamsError(
                f"TripParams key {name} must be an integer"
                if name in json
                else f"TripParams key {name} is missing"
            )
        values[key] = value
    return TripParams(**values)
