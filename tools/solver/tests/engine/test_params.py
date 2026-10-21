"""TripParams: the wire form, the bundled tunables and the bounds (M01 data-model "TripParams").

Ported from `params_test.dart` and `params_tunables_test.dart`.
"""

from __future__ import annotations

import json
from typing import Any

import pytest
from wassal_content.loader import load_json_bytes
from wassal_content.models import LineId

from tests.paths import APP_TUNABLES, FIXTURES
from tests.support.builders import TripBuilder
from wassal_solver.engine import TripRefused, start
from wassal_solver.engine.params import PARAM_KEYS, ParamsError, TripParams

KEYS = [
    "trip_hop_ms",
    "trip_undo_window_ms",
    "rep_fight",
    "rep_false_accusation",
    "rep_missed_stop",
    "rep_liar_caught",
    "rep_exact_change",
    "rep_revive_to",
    "trip_station_warning_ms",
    "trip_hop_pct_hajja",
    "trip_hop_pct_chatty_row",
    "trip_group_redirect_hop_ms",
    "trip_wake_ms",
    "trip_sleeper_awake_ms",
    "trip_headphones_attentive_ms",
    "trip_patience_ms",
    "trip_patience_pct_hurry",
    "trip_patience_drain_pct_traffic",
    "trip_bump_collect_ms",
    "trip_break_min_piasters",
    "trip_break_delay_ms",
    "trip_tip_piasters_regular_customer",
    "booster_ledger_peek_ms",
    "booster_traffic_jam_ms",
    "booster_traffic_jam_max_per_trip",
    "rep_short_change",
    "rep_impatient",
    "rep_change_request_declined",
]


def tunables() -> dict[str, Any]:
    loaded: dict[str, Any] = json.loads(APP_TUNABLES.read_text(encoding="utf-8"))
    return loaded


def wire(line: LineId = LineId.LINE_GAMAA) -> dict[str, Any]:
    return dict(TripParams.from_tunables(tunables(), line).to_json())


def problem_keys(values: dict[str, Any]) -> list[str]:
    return [problem.key for problem in TripParams.from_json(values).problems()]


def test_the_wire_form_has_exactly_the_28_keys_in_order() -> None:
    assert len(KEYS) == 28
    assert list(PARAM_KEYS) == KEYS
    assert list(wire()) == KEYS


def test_from_json_and_to_json_round_trip() -> None:
    values = wire()
    assert TripParams.from_json(values).to_json() == values
    assert TripParams.from_json(values).trip_hop_ms == 1100


@pytest.mark.parametrize("key", KEYS)
def test_a_missing_key_is_refused_by_name(key: str) -> None:
    values = wire()
    del values[key]
    with pytest.raises(ParamsError, match=f"TripParams key {key} is missing"):
        TripParams.from_json(values)


@pytest.mark.parametrize("bad", ["1000", 1000.5, True, False, None, [1]])
def test_a_non_integer_is_refused_by_name(bad: object) -> None:
    values = wire()
    values["rep_fight"] = bad
    with pytest.raises(ParamsError, match="TripParams key rep_fight must be an integer"):
        TripParams.from_json(values)


def test_an_unknown_key_is_refused_by_name() -> None:
    values = wire()
    values["trip_hop_ms_line_hay"] = 1300
    with pytest.raises(ParamsError, match="unknown TripParams key: trip_hop_ms_line_hay"):
        TripParams.from_json(values)


def test_params_are_frozen() -> None:
    params = TripParams.from_json(wire())
    with pytest.raises(AttributeError):
        params.rep_fight = 1  # type: ignore[misc]


class TestProblems:
    def test_the_defaults_have_none(self) -> None:
        for line in LineId:
            assert TripParams.from_tunables(tunables(), line).problems() == []

    @pytest.mark.parametrize(
        "key", ["trip_hop_ms", "trip_group_redirect_hop_ms", "trip_patience_ms"]
    )
    def test_the_step_sized_durations_are_at_least_33(self, key: str) -> None:
        below = wire() | {key: 32}
        # At 33 ms, a percent below 100 would scale it below a step.
        at_step = wire() | {key: 33, "trip_patience_pct_hurry": 100}
        assert problem_keys(below) == [key]
        assert problem_keys(at_step) == []
        assert TripParams.from_json(below).problems()[0].message == f"{key} is 32, below 33"

    @pytest.mark.parametrize(
        "key",
        [
            "trip_hop_pct_hajja",
            "trip_hop_pct_chatty_row",
            "trip_patience_pct_hurry",
            "trip_patience_drain_pct_traffic",
        ],
    )
    def test_every_percent_is_1_to_1000(self, key: str) -> None:
        # Long enough durations that 1% of them is still a step.
        long = wire() | {"trip_hop_ms": 3300, "trip_patience_ms": 3300}
        assert problem_keys(long | {key: 0}) == [key]
        assert problem_keys(long | {key: 1001}) == [key]
        assert problem_keys(long | {key: 1}) == []
        assert problem_keys(long | {key: 1000}) == []
        message = TripParams.from_json(long | {key: 1001}).problems()[0].message
        assert message == f"{key} is 1001, outside 1..1000"

    def test_a_percent_never_scales_a_hop_or_patience_below_one_step(self) -> None:
        # trip_hop_ms 100: 32% of it is 32 ms, 33% is 33 ms.
        short = wire() | {"trip_hop_ms": 100, "trip_patience_ms": 100}
        hajja = TripParams.from_json(short | {"trip_hop_pct_hajja": 32}).problems()
        assert [(q.key, q.message) for q in hajja] == [
            ("trip_hop_pct_hajja", "a hajja's hop would be 32 ms, below 33"),
        ]
        assert problem_keys(short | {"trip_hop_pct_hajja": 33}) == []
        chatty = TripParams.from_json(short | {"trip_hop_pct_chatty_row": 32}).problems()
        assert [(q.key, q.message) for q in chatty] == [
            ("trip_hop_pct_chatty_row", "a hop in a chatty row would be 32 ms, below 33"),
        ]
        hurry = TripParams.from_json(short | {"trip_patience_pct_hurry": 32}).problems()
        assert [(q.key, q.message) for q in hurry] == [
            ("trip_patience_pct_hurry", "a hurried passenger's patience would be 32 ms, below 33"),
        ]
        assert problem_keys(short | {"trip_patience_pct_hurry": 33}) == []
        # A hajja in a chatty row: 60% of 60% of 100 ms is 36 ms, 50% of 60% is 30 ms.
        both = short | {"trip_hop_pct_hajja": 60}
        assert problem_keys(both | {"trip_hop_pct_chatty_row": 60}) == []
        mixed = TripParams.from_json(both | {"trip_hop_pct_chatty_row": 50}).problems()
        assert [(q.key, q.message) for q in mixed] == [
            ("trip_hop_pct_chatty_row", "a hop in a chatty row would be 30 ms, below 33"),
        ]

    def test_a_scaled_duration_is_checked_only_when_its_own_params_are_in_bounds(self) -> None:
        short = wire() | {"trip_hop_ms": 32, "trip_hop_pct_hajja": 1, "trip_patience_ms": 32}
        assert problem_keys(short) == ["trip_hop_ms", "trip_patience_ms"]
        assert problem_keys(wire() | {"trip_hop_pct_hajja": 0}) == ["trip_hop_pct_hajja"]

    def test_rep_revive_to_is_1_to_100(self) -> None:
        assert problem_keys(wire() | {"rep_revive_to": 0}) == ["rep_revive_to"]
        assert problem_keys(wire() | {"rep_revive_to": 101}) == ["rep_revive_to"]
        assert problem_keys(wire() | {"rep_revive_to": 1}) == []
        assert problem_keys(wire() | {"rep_revive_to": 100}) == []

    def test_the_traffic_jam_is_bounded(self) -> None:
        assert problem_keys(wire() | {"booster_traffic_jam_ms": 60001}) == [
            "booster_traffic_jam_ms"
        ]
        assert problem_keys(wire() | {"booster_traffic_jam_ms": 60000}) == []
        assert problem_keys(wire() | {"booster_traffic_jam_max_per_trip": 6}) == [
            "booster_traffic_jam_max_per_trip"
        ]
        assert problem_keys(wire() | {"booster_traffic_jam_max_per_trip": 5}) == []

    def test_every_other_field_is_at_least_0(self) -> None:
        bounded = {
            "trip_hop_ms",
            "trip_group_redirect_hop_ms",
            "trip_patience_ms",
            "trip_hop_pct_hajja",
            "trip_hop_pct_chatty_row",
            "trip_patience_pct_hurry",
            "trip_patience_drain_pct_traffic",
            "rep_revive_to",
        }
        for key in KEYS:
            if key in bounded:
                continue
            assert problem_keys(wire() | {key: -1}) == [key], key
            assert problem_keys(wire() | {key: 0}) == [], key

    def test_every_problem_is_reported(self) -> None:
        assert sorted(problem_keys(wire() | {"rep_fight": -1, "trip_hop_ms": 0})) == [
            "rep_fight",
            "trip_hop_ms",
        ]


@pytest.mark.parametrize(
    ("key", "edge", "past"),
    [
        ("trip_hop_ms", 33, 32),
        ("trip_patience_ms", 66, 32),
        ("trip_group_redirect_hop_ms", 33, 32),
        ("trip_hop_pct_hajja", 1000, 1001),
        ("trip_patience_drain_pct_traffic", 1, 0),
        ("rep_revive_to", 100, 101),
        ("booster_traffic_jam_ms", 60000, 60001),
        ("booster_traffic_jam_max_per_trip", 0, -1),
        ("rep_fight", 0, -1),
    ],
)
def test_a_bound_at_its_edge_starts_and_one_past_it_is_bad_params(
    key: str, edge: int, past: int
) -> None:
    definition = (
        TripBuilder()
        .station("kobri", 30)
        .passenger("p1", seat="A_r", dest="kobri", payment=[1000])
        .build()
    )
    start(definition, TripParams.from_json(wire() | {key: edge}), 1)
    with pytest.raises(TripRefused) as refused:
        start(definition, TripParams.from_json(wire() | {key: past}), 1)
    assert [(r.code, r.path) for r in refused.value.refusals] == [("bad_params", f"params.{key}")]


class TestTunables:
    def test_trip_hop_ms_resolves_per_line(self) -> None:
        hop = {
            LineId.LINE_HAY: 1300,
            LineId.LINE_GAMAA: 1100,
            LineId.LINE_SOUQ: 900,
            LineId.LINE_MASYAF: 900,
            LineId.LINE_SAFAR: 900,
        }
        for line, ms in hop.items():
            assert TripParams.from_tunables(tunables(), line).trip_hop_ms == ms
            assert TripParams.from_tunables(tunables(), line.value).trip_hop_ms == ms

    def test_every_other_key_is_the_tunable_of_the_same_name(self) -> None:
        values = tunables()
        for key, value in TripParams.from_tunables(values, LineId.LINE_HAY).to_json().items():
            if key != "trip_hop_ms":
                assert values[key] == value, key

    def test_the_bundled_defaults_round_trip_for_every_line(self) -> None:
        for line in LineId:
            params = TripParams.from_tunables(tunables(), line)
            assert TripParams.from_json(params.to_json()) == params

    def test_a_missing_or_mistyped_tunable_is_refused_by_name(self) -> None:
        missing = tunables()
        del missing["trip_patience_ms"]
        with pytest.raises(ParamsError, match="trip_patience_ms is missing"):
            TripParams.from_tunables(missing, LineId.LINE_HAY)
        mistyped = tunables() | {"trip_hop_ms_line_hay": "fast"}
        with pytest.raises(ParamsError, match="trip_hop_ms_line_hay must be an integer"):
            TripParams.from_tunables(mistyped, LineId.LINE_HAY)

    def test_presentation_keys_are_not_params(self) -> None:
        keys = TripParams.from_tunables(tunables(), LineId.LINE_HAY).to_json()
        assert not [k for k in keys if k.startswith(("trip_bubble_min_ms", "trip_hints_mode"))]
        assert not [k for k in keys if k.startswith("fuel_")]


@pytest.mark.parametrize("path", sorted(FIXTURES.glob("*.json")), ids=lambda path: path.stem)
def test_every_fixtures_params_round_trip(path: Any) -> None:
    document = load_json_bytes(path.read_bytes())
    params = TripParams.from_json(document["params"])
    assert params.to_json() == document["params"]
    assert list(params.to_json()) == KEYS
