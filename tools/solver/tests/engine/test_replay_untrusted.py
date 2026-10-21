"""`replay_untrusted` (contracts/mirror.md §4, research R6): every malformed input is refused with
its reason, in check order, and nothing but `ReplayRefused` ever escapes.

B08 will feed it logs that players sent, so the work it does is bounded too: at most 1,201
commands applied and at most one longest trip of steps.
"""

from __future__ import annotations

import contextlib
import copy
import json
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any

import pytest
from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

from tests.paths import FIXTURES
from wassal_solver.engine import trip as trip_module
from wassal_solver.engine.fixture import parse_fixture
from wassal_solver.engine.replay import (
    MAX_INPUT_BYTES,
    ReplayReason,
    ReplayRefused,
    replay,
    replay_untrusted,
)
from wassal_solver.engine.rules.command_handlers import apply_command
from wassal_solver.engine.rules.step import step_trip
from wassal_solver.engine.validation import RefusalCode
from wassal_solver.fixture_files import load_fixture

SAMPLES = sorted(FIXTURES.glob("sample__*.json"))
INPUT_KEYS = ("command_log", "definition", "params", "seed")
LONGEST_TRIP_STEPS = 1_500_000 // 33 + 1


def tuple_of(path: Path) -> dict[str, Any]:
    document = load_fixture(path)
    return {key: document[key] for key in INPUT_KEYS}


def valid() -> dict[str, Any]:
    return tuple_of(FIXTURES / "core__exact_change.json")


def refused(document: object) -> ReplayRefused:
    with pytest.raises(ReplayRefused) as caught:
        replay_untrusted(document)
    return caught.value


def edit(change: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
    document = valid()
    change(document)
    return document


class TestBadInput:
    @pytest.mark.parametrize("document", [[], "x", 1, None, True, ["definition"]])
    def test_not_an_object(self, document: object) -> None:
        assert refused(document).reason == ReplayReason.BAD_INPUT

    @pytest.mark.parametrize("key", INPUT_KEYS)
    def test_a_key_missing(self, key: str) -> None:
        problem = refused(edit(lambda d: d.pop(key)))
        assert problem.reason == ReplayReason.BAD_INPUT
        assert key in problem.message

    def test_an_extra_key(self) -> None:
        problem = refused(edit(lambda d: d.update(expected_result={})))
        assert problem.reason == ReplayReason.BAD_INPUT
        assert "expected_result" in problem.message

    @pytest.mark.parametrize(
        "change",
        [
            lambda d: d.update(seed=1.0),
            lambda d: d["params"].update(rep_fight=30.0),
            lambda d: d["definition"].update(rev=1.5),
            lambda d: d["command_log"].append([33.0, "ReturnHand"]),
            lambda d: d.update(seed=float("nan")),
            lambda d: d["params"].update(rep_fight=float("inf")),
        ],
        ids=["seed", "params", "definition", "log", "nan", "inf"],
    )
    def test_a_non_integer_number_anywhere(self, change: Callable[[dict[str, Any]], None]) -> None:
        assert refused(edit(change)).reason == ReplayReason.BAD_INPUT

    @pytest.mark.parametrize(
        "change",
        [
            lambda d: d.update(seed="1"),
            lambda d: d.update(seed=True),
            lambda d: d.update(seed=2**60),
            lambda d: d["definition"].update(seats=(1, 2)),
            lambda d: d["params"].update({1: 2}),
            lambda d: d.update(command_log={0}),
        ],
        ids=["string seed", "bool seed", "huge seed", "tuple", "int key", "set"],
    )
    def test_a_value_that_is_not_json_or_a_seed_that_is_not_an_integer(
        self, change: Callable[[dict[str, Any]], None]
    ) -> None:
        assert refused(edit(change)).reason == ReplayReason.BAD_INPUT

    def test_too_deep(self) -> None:
        deep: Any = 1
        for _ in range(100):
            deep = [deep]
        assert refused(edit(lambda d: d.update(command_log=deep))).reason == ReplayReason.BAD_INPUT

    def test_bytes_are_read_as_strict_json(self) -> None:
        text = json.dumps(valid())
        assert replay_untrusted(text.encode()) == replay_untrusted(valid())
        assert replay_untrusted(text) == replay_untrusted(valid())
        duplicate = text[:-1] + ', "seed": 2}'
        nan = text.replace('"seed": 1', '"seed": NaN', 1)
        for bad in (duplicate, nan, "{", b"\xff", '{"seed": 1.5}'):
            assert refused(bad).reason == ReplayReason.BAD_INPUT

    def test_text_over_the_byte_cap_is_refused_before_it_is_parsed(self) -> None:
        longest = json.dumps(tuple_of(FIXTURES / "stress__longest_trip.json"), indent=2)
        assert len(longest.encode()) * 3 < MAX_INPUT_BYTES
        replay_untrusted(longest.encode())
        padded = longest + " " * (MAX_INPUT_BYTES + 1 - len(longest))
        for big in (padded, padded.encode()):
            refusal = refused(big)
            assert refusal.reason == ReplayReason.BAD_INPUT
            assert f"over {MAX_INPUT_BYTES} bytes" in str(refusal)


class TestBadDefinition:
    def test_a_definition_that_fails_document_findings(self) -> None:
        problem = refused(edit(lambda d: d["definition"]["passengers"][0].update(archetype="cat")))
        assert problem.reason == ReplayReason.BAD_DEFINITION
        assert problem.findings
        assert all(finding.severity == "error" for finding in problem.findings)

    def test_a_definition_that_is_not_an_object(self) -> None:
        assert refused(edit(lambda d: d.update(definition=[]))).reason == (
            ReplayReason.BAD_DEFINITION
        )

    def test_an_unsupported_archetype_fails_the_engine_rules(self) -> None:
        problem = refused(
            edit(lambda d: d["definition"]["passengers"][0].update(archetype="dodger"))
        )
        assert problem.reason == ReplayReason.BAD_DEFINITION
        assert {finding.code for finding in problem.findings} == {"V-T9"}


class TestBadParams:
    def test_an_unknown_key(self) -> None:
        problem = refused(edit(lambda d: d["params"].update(trip_hop_ms_line_hay=1300)))
        assert problem.reason == ReplayReason.BAD_PARAMS

    def test_a_missing_key(self) -> None:
        assert refused(edit(lambda d: d["params"].pop("rep_fight"))).reason == (
            ReplayReason.BAD_PARAMS
        )

    def test_a_value_past_a_bound(self) -> None:
        problem = refused(edit(lambda d: d["params"].update(rep_revive_to=0)))
        assert problem.reason == ReplayReason.BAD_PARAMS
        assert "rep_revive_to" in problem.message

    def test_params_that_are_not_an_object(self) -> None:
        assert refused(edit(lambda d: d.update(params=[]))).reason == ReplayReason.BAD_PARAMS


class TestBadLog:
    def test_not_a_list(self) -> None:
        problem = refused(edit(lambda d: d.update(command_log={"0": "Tap"})))
        assert problem.reason == ReplayReason.BAD_LOG
        assert problem.index is None

    def test_more_than_1201_entries(self) -> None:
        log = [[33, "ReturnHand"]] * 1202
        problem = refused(edit(lambda d: d.update(command_log=log)))
        assert problem.reason == ReplayReason.BAD_LOG
        assert problem.index is None

    @pytest.mark.parametrize(
        "entry",
        [
            "ReturnHand",
            {"t_ms": 33},
            [-33, "ReturnHand"],
            [34, "ReturnHand"],
            [1_500_015, "ReturnHand"],
            [33, "Fly"],
            [33, "Tap"],
            [33, "Tap", "p1", "p2"],
            [33, "Tap", 1],
            [33, "ResolveClaim", "p1", 1],
            [33, "PickFromTray", 300],
            [33, "RequestBreak", 25],
        ],
        ids=repr,
    )
    def test_a_malformed_entry_is_refused_with_its_index(self, entry: object) -> None:
        log = [[0, "PickFromTray", 100], entry]
        problem = refused(edit(lambda d: d.update(command_log=log)))
        assert problem.reason == ReplayReason.BAD_LOG
        assert problem.index == 1

    def test_the_last_step_of_the_longest_trip_is_a_valid_time(self) -> None:
        log = [[1_499_982, "Abandon"]]
        problem = refused(edit(lambda d: d.update(command_log=log)))
        assert problem.reason == ReplayReason.CLOCK_STOPPED


class TestReplaysReasons:
    def test_the_trip_is_refused(self) -> None:
        problem = refused(edit(lambda d: d.update(seed=0)))
        assert problem.reason == ReplayReason.TRIP_REFUSED
        assert [r.code for r in problem.refusals] == [RefusalCode.BAD_SEED]

    def test_t_ms_goes_down(self) -> None:
        log = [[66, "PickFromTray", 100], [33, "ReturnHand"]]
        problem = refused(edit(lambda d: d.update(command_log=log)))
        assert (problem.reason, problem.index) == (ReplayReason.T_MS_GOES_DOWN, 1)

    def test_an_entry_is_rejected(self) -> None:
        log = [[0, "ReturnHand"]]
        problem = refused(edit(lambda d: d.update(command_log=log)))
        assert (problem.reason, problem.index) == (ReplayReason.ENTRY_REJECTED, 0)
        assert problem.rejection is not None
        assert problem.rejection.code == "hand_empty"


@pytest.mark.parametrize("path", sorted(FIXTURES.glob("*.json")), ids=lambda path: path.stem)
def test_a_valid_tuple_gives_the_same_result_as_replay(path: Path) -> None:
    fixture = parse_fixture(load_fixture(path))
    expected = replay(fixture.definition, fixture.seed, fixture.params, fixture.command_log)
    assert replay_untrusted(tuple_of(path)) == expected


class _Counts:
    def __init__(self) -> None:
        self.steps = 0
        self.applied = 0


@pytest.fixture
def counts(monkeypatch: pytest.MonkeyPatch) -> _Counts:
    """Counts the steps and the command applications of every trip, through the trip module."""
    found = _Counts()

    def counted_step(tx: Any) -> None:
        found.steps += 1
        step_trip(tx)

    def counted_apply(tx: Any, command: Any) -> Any:
        found.applied += 1
        return apply_command(tx, command)

    monkeypatch.setattr(trip_module, "step_trip", counted_step)
    monkeypatch.setattr(trip_module, "apply_command", counted_apply)
    return found


def _bounded(document: object, counts: _Counts) -> None:
    counts.steps = counts.applied = 0
    with contextlib.suppress(ReplayRefused):
        replay_untrusted(document)
    assert counts.applied <= 1201
    assert counts.steps <= LONGEST_TRIP_STEPS


_JSON = st.recursive(
    st.none() | st.booleans() | st.integers() | st.floats() | st.text(max_size=5),
    lambda children: (
        st.lists(children, max_size=4) | st.dictionaries(st.text(max_size=5), children, max_size=4)
    ),
    max_leaves=20,
)


@settings(max_examples=150)
@given(document=_JSON)
def test_random_json_is_only_ever_refused(document: object) -> None:
    with pytest.raises(ReplayRefused):
        replay_untrusted(document)


def _paths(value: Any, path: tuple[Any, ...] = ()) -> Iterator[tuple[Any, ...]]:
    yield path
    if isinstance(value, dict):
        for key, item in value.items():
            yield from _paths(item, (*path, key))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from _paths(item, (*path, index))


_TUPLES = [tuple_of(path) for path in SAMPLES]
_REPLACEMENTS = st.one_of(
    st.integers(min_value=-2, max_value=2_000_000),
    st.sampled_from([0, 33, 1_499_982, 1_500_015, -1, 2**53]),
    st.booleans(),
    st.none(),
    st.text(max_size=8),
    st.sampled_from(["PickFromTray", "Tap", "p1", "change_bag", "line_hay", "traffic", "A_r"]),
    st.lists(st.integers(min_value=0, max_value=20000), max_size=3),
    st.just([]),
    st.just({}),
)


@settings(max_examples=150, suppress_health_check=[HealthCheck.function_scoped_fixture])
@given(data=st.data())
def test_mutated_tuples_are_refused_or_replayed_within_bounds(
    data: st.DataObject, counts: _Counts
) -> None:
    document = copy.deepcopy(data.draw(st.sampled_from(_TUPLES)))
    for _ in range(data.draw(st.integers(min_value=1, max_value=3))):
        paths = [path for path in _paths(document) if path]
        if not paths:
            break
        path = data.draw(st.sampled_from(paths))
        parent = document
        for key in path[:-1]:
            parent = parent[key]
        if data.draw(st.booleans()) and isinstance(parent, dict):
            del parent[path[-1]]
        else:
            parent[path[-1]] = data.draw(_REPLACEMENTS)
    _bounded(document, counts)


def test_a_full_log_of_the_longest_trip_stays_within_bounds(counts: _Counts) -> None:
    document = tuple_of(FIXTURES / "stress__longest_trip.json")
    _bounded(document, counts)
    assert counts.steps == LONGEST_TRIP_STEPS
    assert counts.applied == len(document["command_log"])
