"""Integer money and time (RULES.md §15) over random runs of the five sample trips, as the Dart
fuzz test checks them: after every step, every integer of the state is an int and not a bool, and
money is conserved after every step and every accepted command.

Dart keeps its ledger from the events a transition emits, which the mirror doesn't have (research
R3). The same five points are hooked here instead, at the calls that emit them in Dart:

| Dart event                          | Mirror call                                 |
| ----------------------------------- | ------------------------------------------- |
| `FareSent`                          | `TripState.new_token(FARE, …)`              |
| `PassengerSpeaks(returns_excess)`   | `TripState.new_token(RETURNED, …)`          |
| `BoosterUsed(change_bag)`           | an accepted `UseBooster(change_bag)`        |
| `ChangeDelivered`                   | `judge_change`, unless it made a redirect   |
| `DroppedLost`                       | `lose_dropped`                              |
"""

from __future__ import annotations

import dataclasses
import enum
import types
import typing
from collections import Counter
from collections.abc import Callable
from functools import cache
from pathlib import Path
from typing import Any

import pytest
from hypothesis import given, settings
from wassal_content.models import BoosterId

from tests.engine.random_runs import SAMPLES, SEEDS, run, sample
from tests.support.builders import TripBuilder, default_params
from tests.support.scripts import ok, passenger, start_trip
from wassal_solver.engine import Trip
from wassal_solver.engine.commands import (
    CollectDropped,
    Command,
    PickFromTray,
    RequestBreak,
    SendHand,
    UseBooster,
)
from wassal_solver.engine.model import MoneyToken, TokenKind, TripState, TripStatus
from wassal_solver.engine.money import CHANGE_BAG, Pieces
from wassal_solver.engine.rules import chain, change, stations

# The change_bag booster's total (RULES.md §14.2), as Dart's fuzz test spells it.
CHANGE_BAG_TOTAL = 50 * 2 + 100 * 3 + 500 * 2


def held(state: TripState) -> int:
    """The money the state holds: tray, hand, tokens and notes out for a break."""
    return (
        state.tray.total
        + state.hand.total
        + sum(token.pieces.total for token in state.tokens.values())
        + sum(pending.denomination for pending in state.pending_breaks)
    )


class Ledger:
    """Where the money should be: the initial tray plus everything that came in from passengers
    or a change bag, minus everything handed out or lost. `pending` gathers what the hooks see
    until the next check; `flows` totals each Dart event."""

    def __init__(self) -> None:
        self.expected: int | None = None
        self.pending = 0
        self.flows: Counter[str] = Counter()

    def came_in(self, event: str, amount: int) -> None:
        self.pending += amount
        self.flows[event] += amount

    def went_out(self, event: str, amount: int) -> None:
        self.pending -= amount
        self.flows[event] += amount

    def check(self, trip: Trip, command: Command | None) -> None:
        """The observer of a run: seeded from the started trip, then checked after every step
        and every accepted command."""
        if self.expected is None:
            assert self.pending == 0
            self.expected = held(trip.state)
            return
        if isinstance(command, UseBooster) and command.booster is BoosterId.CHANGE_BAG:
            self.came_in("BoosterUsed(change_bag)", CHANGE_BAG_TOTAL)
        self.expected += self.pending
        self.pending = 0
        what = "a step" if command is None else command.name
        assert held(trip.state) == self.expected, f"money after {what} at {trip.t_ms}"


def hooked(monkeypatch: pytest.MonkeyPatch, ledger: Ledger) -> None:
    new_token = TripState.new_token
    judge_change = change.judge_change
    lose_dropped = chain.lose_dropped

    def recording_new_token(
        state: TripState, kind: TokenKind, pieces: Pieces, owner: str, target: str, holder: str
    ) -> MoneyToken:
        if kind is TokenKind.FARE:
            ledger.came_in("FareSent", pieces.total)
        elif kind is TokenKind.RETURNED:
            ledger.came_in("PassengerSpeaks(returns_excess)", pieces.total)
        return new_token(state, kind, pieces, owner, target, holder)

    def recording_judge_change(tx: Trip, token: MoneyToken) -> None:
        next_id = tx.state.next_token_id
        judge_change(tx, token)
        made = tx.state.tokens.get(next_id)
        if made is None or made.kind is not TokenKind.REDIRECT:
            ledger.went_out("ChangeDelivered", token.pieces.total)

    def recording_lose_dropped(tx: Trip, token: MoneyToken) -> None:
        ledger.went_out("DroppedLost", token.pieces.total)
        lose_dropped(tx, token)

    monkeypatch.setattr(TripState, "new_token", recording_new_token)
    monkeypatch.setattr(chain, "judge_change", recording_judge_change)
    monkeypatch.setattr(chain, "lose_dropped", recording_lose_dropped)
    monkeypatch.setattr(stations, "lose_dropped", recording_lose_dropped)


@cache
def hints(cls: type) -> dict[str, Any]:
    return typing.get_type_hints(cls)


def typing_problems(value: object, hint: Any, where: str) -> list[str]:
    """Where `value` doesn't have the declared type `hint`, with an int never a bool."""
    origin = typing.get_origin(hint)
    args = typing.get_args(hint)
    if origin in (typing.Union, types.UnionType):
        if value is None and type(None) in args:
            return []
        (inner,) = [arg for arg in args if arg is not type(None)]
        return typing_problems(value, inner, where)
    if hint is int or hint is bool:
        return [] if type(value) is hint else [f"{where}: {value!r} is not an {hint.__name__}"]
    if origin in (list, set):
        if not isinstance(value, origin):
            return [f"{where}: {value!r} is not a {origin.__name__}"]
        return [p for item in value for p in typing_problems(item, args[0], f"{where}[]")]
    if origin is tuple:
        if not isinstance(value, tuple):
            return [f"{where}: {value!r} is not a tuple"]
        items = args[:1] * len(value) if args[1:] == (...,) else args
        return [
            p
            for i, (item, inner) in enumerate(zip(value, items, strict=True))
            for p in typing_problems(item, inner, f"{where}[{i}]")
        ]
    if origin is dict:
        if not isinstance(value, dict):
            return [f"{where}: {value!r} is not a dict"]
        return [
            p
            for key, item in value.items()
            for p in [
                *typing_problems(key, args[0], f"{where} key {key!r}"),
                *typing_problems(item, args[1], f"{where}[{key!r}]"),
            ]
        ]
    if not isinstance(value, hint):
        return [f"{where}: {value!r} is not a {hint.__name__}"]
    if dataclasses.is_dataclass(value) and not isinstance(value, type | enum.Enum):
        return [
            p
            for field in dataclasses.fields(value)
            for p in typing_problems(
                getattr(value, field.name), hints(type(value))[field.name], f"{where}.{field.name}"
            )
        ]
    return []


@cache
def conforms(hint: Any) -> Callable[[object], bool]:
    """`typing_problems(value, hint, …) == []`, compiled once per type: the check after every step,
    which falls back on `typing_problems` to say where."""
    origin = typing.get_origin(hint)
    args = typing.get_args(hint)
    if origin in (typing.Union, types.UnionType):
        (inner,) = [arg for arg in args if arg is not type(None)]
        check = conforms(inner)
        return lambda value: value is None or check(value)
    if hint is int or hint is bool:
        return lambda value: type(value) is hint
    if origin in (list, set):
        item = conforms(args[0])
        return lambda value: isinstance(value, origin) and all(map(item, value))
    if origin is tuple:
        if args[1:] == (...,):
            item = conforms(args[0])
            return lambda value: isinstance(value, tuple) and all(map(item, value))
        items = [conforms(arg) for arg in args]
        return lambda value: (
            isinstance(value, tuple)
            and len(value) == len(items)
            and all(check(item) for check, item in zip(items, value, strict=True))
        )
    if origin is dict:
        key, item = conforms(args[0]), conforms(args[1])
        return lambda value: (
            isinstance(value, dict) and all(key(k) and item(v) for k, v in value.items())
        )
    if isinstance(hint, type) and dataclasses.is_dataclass(hint):
        fields = [(f.name, conforms(hints(hint)[f.name])) for f in dataclasses.fields(hint)]
        return lambda value: (
            isinstance(value, hint) and all(check(getattr(value, name)) for name, check in fields)
        )
    return lambda value: isinstance(value, hint)


def floats(json: object, where: str) -> list[str]:
    """Dart's `_expectIntegers`: the doubles anywhere in `json`."""
    if isinstance(json, float):
        return [f"{where}: {json}"]
    if isinstance(json, dict):
        return [p for key, value in json.items() for p in floats(value, f"{where}.{key}")]
    if isinstance(json, list):
        return [p for i, item in enumerate(json) for p in floats(item, f"{where}[{i}]")]
    return []


def integer_check(trip: Trip, command: Command | None) -> None:
    if not conforms(TripState)(trip.state):
        problems = typing_problems(trip.state, TripState, "state")
        raise AssertionError(f"after {command or 'a step'} at {trip.t_ms}: {problems}")


def test_the_change_bag_total_is_the_booster_s() -> None:
    assert CHANGE_BAG.total == CHANGE_BAG_TOTAL


def test_the_check_finds_a_bool_or_a_float_in_an_integer_field() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000])
        .build()
    )
    assert conforms(TripState)(trip.state)
    assert typing_problems(trip.state, TripState, "state") == []
    passenger(trip, "p1").balance = True
    assert not conforms(TripState)(trip.state)
    trip.state.t_ms = 33.0  # type: ignore[assignment]
    assert typing_problems(trip.state, TripState, "state") == [
        "state.t_ms: 33.0 is not an int",
        "state.passengers[].balance: True is not an int",
    ]


@pytest.mark.parametrize("path", SAMPLES, ids=lambda path: path.stem)
@settings(max_examples=6)
@given(seed=SEEDS)
def test_every_integer_of_the_state_stays_an_int(path: Path, seed: int) -> None:
    definition = sample(path)
    trip = run(definition, default_params(definition.line_id), seed, integer_check)
    assert trip.result is not None
    assert typing_problems(trip.result, type(trip.result), "result") == []
    assert floats(trip.state.to_json(), "state") == []
    assert floats(trip.result.to_json(), "result") == []


@pytest.mark.parametrize("path", SAMPLES, ids=lambda path: path.stem)
@settings(max_examples=10)
@given(seed=SEEDS)
def test_money_is_conserved_after_every_step_and_command(path: Path, seed: int) -> None:
    definition = sample(path)
    ledger = Ledger()
    with pytest.MonkeyPatch.context() as monkeypatch:
        hooked(monkeypatch, ledger)
        trip = run(definition, default_params(definition.line_id), seed, ledger.check)
    assert trip.result is not None


def one_fare(
    *, bump_at: int | None = None, archetype: str = "regular", station: int = 30
) -> TripBuilder:
    """line_gamaa: p1 in A_r pays 1000 at 1 s; the fare hops from 1023 to 2145."""
    builder = (
        TripBuilder()
        .station("gamaa", station)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000], pays_at=1, archetype=archetype)
    )
    return builder if bump_at is None else builder.event("bump", bump_at)


def group_of_two() -> TripBuilder:
    """The payer p1 pays 2000 for two at 850, and is owed 300; p2 is the member."""
    return (
        TripBuilder()
        .station("gamaa", 30, fare=850)
        .passenger(
            "p1",
            seat="A_r",
            dest="gamaa",
            payment=[2000],
            pays_at=1,
            archetype="group_payer",
            group="g1",
            group_size=2,
        )
        .passenger("p2", seat="A_m", dest="gamaa", payment=[1000], group="g1", group_size=2)
    )


def send(passenger_id: str, *pieces: int) -> list[Command]:
    return [*(PickFromTray(piece) for piece in pieces), SendHand(passenger_id)]


@pytest.mark.parametrize(
    ("builder", "script", "flows"),
    [
        pytest.param(
            one_fare(bump_at=2), {}, {"FareSent": 1000, "DroppedLost": 1000}, id="a lost fare"
        ),
        pytest.param(
            one_fare(bump_at=3),
            {2145: send("p1", 100, 100, 100)},
            {"FareSent": 1000, "DroppedLost": 300},
            id="lost change",
        ),
        pytest.param(
            one_fare(bump_at=4, archetype="honest"),
            {2145: send("p1", 500)},
            {
                "FareSent": 1000,
                "ChangeDelivered": 500,
                "PassengerSpeaks(returns_excess)": 200,
                "DroppedLost": 200,
            },
            id="a lost return",
        ),
        pytest.param(
            one_fare(bump_at=4, archetype="honest"),
            {2145: send("p1", 500), 5016: [CollectDropped(3)]},
            {"FareSent": 1000, "ChangeDelivered": 500, "PassengerSpeaks(returns_excess)": 200},
            id="a collected return",
        ),
        pytest.param(
            one_fare(bump_at=2, station=4),
            {},
            {"FareSent": 1000, "DroppedLost": 1000},
            id="a token dropped at the end of the trip",
        ),
        pytest.param(
            group_of_two(),
            {2145: send("p2", 100, 100, 100)},
            {"FareSent": 2000, "ChangeDelivered": 300},
            id="change redirected to the payer",
        ),
        pytest.param(
            one_fare(),
            {990: [UseBooster(BoosterId.CHANGE_BAG)], 2145: [RequestBreak(1000)]},
            {"BoosterUsed(change_bag)": CHANGE_BAG_TOTAL, "FareSent": 1000},
            id="a change bag and a break",
        ),
    ],
)
def test_the_ledger_balances_on_a_scripted_trip(
    builder: TripBuilder, script: dict[int, list[Command]], flows: dict[str, int]
) -> None:
    """Each hook of the ledger, on a trip that reaches it: the random runs of the samples rarely
    lose a token, since only line_gamaa.01 has a bump."""
    ledger = Ledger()
    with pytest.MonkeyPatch.context() as monkeypatch:
        hooked(monkeypatch, ledger)
        trip = start_trip(builder.build())
        ledger.check(trip, None)
        for at, commands in script.items():
            while trip.status is TripStatus.RUNNING and trip.t_ms < at:
                trip.step()
                ledger.check(trip, None)
            for command in commands:
                ok(trip, command)
                ledger.check(trip, command)
        while trip.status is TripStatus.RUNNING:
            trip.step()
            ledger.check(trip, None)
    assert trip.status is TripStatus.FINISHED
    assert ledger.flows == flows
