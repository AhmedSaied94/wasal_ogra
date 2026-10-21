"""Refusals at start (M01 data-model "Validation"), ported from `validation_test.dart`.

One case per code, every problem reported at once in the Dart order and with the Dart paths, and
every shipped trip accepted.
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest
from wassal_content.loader import load_json_bytes
from wassal_content.models import TripDefinition

from tests.paths import REPO, SAMPLE
from tests.support.builders import TripBuilder, default_params, definition_of, params_with
from wassal_solver.engine import TripRefused, start
from wassal_solver.engine.params import TripParams
from wassal_solver.engine.validation import Refusal, RefusalCode, validate

Codes = list[tuple[str, str]]


def base() -> TripBuilder:
    return (
        TripBuilder()
        .station("kobri", 30)
        .station("gamaa", 60)
        .passenger("p1", seat="A_r", dest="kobri", payment=[1000])
        .passenger("p2", seat="B_m", dest="gamaa", payment=[1000])
    )


def refusals(
    definition: TripDefinition, *, params: TripParams | None = None, seed: int | None = None
) -> list[Refusal]:
    return validate(
        definition,
        params or default_params(),
        definition.seed if seed is None else seed,
    )


def codes(
    definition: TripDefinition, *, params: TripParams | None = None, seed: int | None = None
) -> Codes:
    return [(r.code, r.path) for r in refusals(definition, params=params, seed=seed)]


def edited(builder: TripBuilder, edit: Callable[[dict[str, Any]], None]) -> TripDefinition:
    document = builder.document()
    edit(document)
    return definition_of(document)


def test_the_refusal_codes_in_order() -> None:
    assert [code.value for code in RefusalCode] == [
        "bad_seed",
        "bad_params",
        "duplicate_id",
        "unknown_seat",
        "unknown_station",
        "stations_out_of_order",
        "board_after_dest",
        "seat_taken_at_start",
        "unknown_passenger",
        "group_mismatch",
        "unsupported_archetype",
        "unsupported_event",
        "event_param",
        "pickup_conflict",
    ]


def test_a_valid_trip_has_no_refusals() -> None:
    assert refusals(base().build()) == []


def test_bad_seed() -> None:
    assert codes(base().build(), seed=0) == [("bad_seed", "seed")]
    assert codes(base().build(), seed=0x100000000) == [("bad_seed", "seed")]
    assert codes(base().build(), seed=0xFFFFFFFF) == []
    assert codes(base().build(), seed=1) == []
    (refusal,) = refusals(base().build(), seed=0)
    assert refusal.message == "the seed 0 is outside 1..2^32-1"


def test_bad_params() -> None:
    found = codes(base().build(), params=params_with({"rep_revive_to": 0, "trip_hop_ms": 1}))
    assert sorted(found) == [
        ("bad_params", "params.rep_revive_to"),
        ("bad_params", "params.trip_hop_ms"),
    ]


def test_duplicate_id() -> None:
    def seat(document: dict[str, Any]) -> None:
        document["seats"][2]["seat_id"] = "A_r"

    def station(document: dict[str, Any]) -> None:
        document["stations"][1]["station_id"] = "kobri"

    assert ("duplicate_id", "$.seats[2].seat_id") in codes(edited(base(), seat))
    assert ("duplicate_id", "$.stations[1].station_id") in codes(edited(base(), station))
    passengers = base().passenger("p1", seat="C_l", dest="gamaa", payment=[1000]).build()
    assert codes(passengers) == [("duplicate_id", "$.passengers[2].passenger_id")]
    assert refusals(passengers)[0].message == "duplicate id p1"


def test_unknown_seat() -> None:
    definition = base().passenger("p3", seat="D_r", dest="gamaa", payment=[1000]).build()
    assert codes(definition) == [("unknown_seat", "$.passengers[2].seat_id")]


def test_unknown_station() -> None:
    dest = base().passenger("p3", seat="C_r", dest="souq", payment=[1000]).build()
    assert codes(dest) == [("unknown_station", "$.passengers[2].dest_station_id")]
    board = base().passenger("p3", seat="C_r", dest="gamaa", board="souq", payment=[1000]).build()
    assert codes(board) == [("unknown_station", "$.passengers[2].board_station_id")]
    event = base().event("traffic", 10, seconds=5, station="souq").build()
    assert ("unknown_station", "$.events[0].station_id") in codes(event)


def test_stations_out_of_order() -> None:
    definition = (
        TripBuilder()
        .station("kobri", 30)
        .station("gamaa", 30)
        .passenger("p1", seat="A_r", dest="kobri", payment=[1000])
        .build()
    )
    assert codes(definition) == [("stations_out_of_order", "$.stations[1].at_seconds")]


def test_board_after_dest() -> None:
    later = base().passenger("p3", seat="C_r", dest="kobri", board="gamaa", payment=[1000])
    assert codes(later.build()) == [("board_after_dest", "$.passengers[2].board_station_id")]
    same = base().passenger("p3", seat="C_r", dest="kobri", board="kobri", payment=[1000])
    assert codes(same.build()) == [("board_after_dest", "$.passengers[2].board_station_id")]


def test_seat_taken_at_start() -> None:
    taken = base().passenger("p3", seat="A_r", dest="gamaa", payment=[1000]).build()
    assert codes(taken) == [("seat_taken_at_start", "$.passengers[2].seat_id")]
    later = base().passenger("p3", seat="A_r", dest="gamaa", board="kobri", payment=[1000])
    assert codes(later.build()) == []


def test_unknown_passenger() -> None:
    definition = base().event("drop_me_here", 10, passengers=["p9"]).build()
    assert codes(definition) == [("unknown_passenger", "$.events[0].passenger_ids[0]")]


class TestGroupMismatch:
    @staticmethod
    def group() -> TripBuilder:
        return (
            base()
            .passenger(
                "p3",
                archetype="group_payer",
                seat="C_r",
                dest="gamaa",
                payment=[5000],
                group="g1",
                group_size=3,
            )
            .passenger("p4", seat="C_m", dest="gamaa", payment=[1000], group="g1", group_size=3)
        )

    def test_a_valid_group(self) -> None:
        assert codes(self.group().build()) == []

    def test_sizes_disagree(self) -> None:
        definition = self.group().passenger(
            "p5", seat="C_l", dest="gamaa", payment=[1000], group="g1", group_size=2
        )
        assert codes(definition.build()) == [("group_mismatch", "$.passengers[4].group_size")]

    def test_more_members_than_the_size(self) -> None:
        definition = (
            self.group()
            .passenger("p5", seat="C_l", dest="gamaa", payment=[1000], group="g1", group_size=3)
            .passenger("p6", seat="B_r", dest="gamaa", payment=[1000], group="g1", group_size=3)
        )
        assert codes(definition.build()) == [("group_mismatch", "$.passengers[5].group_id")]

    def test_no_group_payer_or_two(self) -> None:
        none = base().passenger(
            "p3", seat="C_r", dest="gamaa", payment=[1000], group="g1", group_size=2
        )
        assert codes(none.build()) == [("group_mismatch", "$.passengers[2].group_id")]
        two = self.group().passenger(
            "p5",
            archetype="group_payer",
            seat="C_l",
            dest="gamaa",
            payment=[5000],
            group="g1",
            group_size=3,
        )
        assert codes(two.build()) == [("group_mismatch", "$.passengers[4].archetype")]

    def test_a_payer_without_a_group_or_a_size_without_a_group(self) -> None:
        payer = base().passenger(
            "p3", archetype="group_payer", seat="C_r", dest="gamaa", payment=[5000]
        )
        assert codes(payer.build()) == [("group_mismatch", "$.passengers[2].group_id")]
        size = base().passenger("p3", seat="C_r", dest="gamaa", payment=[1000], group_size=2)
        assert codes(size.build()) == [("group_mismatch", "$.passengers[2].group_size")]
        missing = self.group().passenger("p5", seat="C_l", dest="gamaa", payment=[1000], group="g1")
        assert codes(missing.build()) == [("group_mismatch", "$.passengers[4].group_size")]


@pytest.mark.parametrize("archetype", ["dodger", "bags_lady"])
def test_unsupported_archetype(archetype: str) -> None:
    definition = base().passenger(
        "p3", archetype=archetype, seat="C_r", dest="gamaa", payment=[1000]
    )
    assert codes(definition.build()) == [("unsupported_archetype", "$.passengers[2].archetype")]


def test_unsupported_event() -> None:
    definition = base().event("traffic", 10, seconds=5).build()
    found = validate(definition, default_params(), 1, events=frozenset({"bump"}))
    assert [(r.code, r.path) for r in found] == [("unsupported_event", "$.events[0].event_id")]


class TestEventParam:
    @staticmethod
    def event_codes(add: Callable[[TripBuilder], TripBuilder]) -> Codes:
        builder = (
            base()
            .passenger(
                "p3",
                archetype="group_payer",
                seat="C_r",
                dest="gamaa",
                payment=[5000],
                group="g1",
                group_size=2,
            )
            .passenger("p4", seat="C_m", dest="gamaa", payment=[1000], group="g1", group_size=2)
        )
        return codes(add(builder).build())

    def test_forbidden_parameters(self) -> None:
        assert self.event_codes(lambda b: b.event("bump", 5, seconds=3)) == [
            ("event_param", "$.events[0].seconds")
        ]
        assert self.event_codes(lambda b: b.event("bump", 5, station="kobri")) == [
            ("event_param", "$.events[0].station_id")
        ]

    def test_missing_required_parameters(self) -> None:
        assert self.event_codes(lambda b: b.event("traffic", 5)) == [
            ("event_param", "$.events[0].seconds")
        ]
        assert self.event_codes(lambda b: b.event("fare_increase", 5)) == [
            ("event_param", "$.events[0].amount_piasters")
        ]

    def test_integer_bounds(self) -> None:
        assert self.event_codes(lambda b: b.event("traffic", 5, seconds=0)) == [
            ("event_param", "$.events[0].seconds")
        ]
        assert self.event_codes(lambda b: b.event("open_road", 5, seconds=61)) == [
            ("event_param", "$.events[0].seconds")
        ]
        assert self.event_codes(lambda b: b.event("traffic", 5, seconds=60)) == []
        assert self.event_codes(lambda b: b.event("fare_increase", 5, amount=0)) == [
            ("event_param", "$.events[0].amount_piasters")
        ]

    def test_list_lengths(self) -> None:
        assert self.event_codes(lambda b: b.event("drop_me_here", 5, passengers=["p1", "p2"])) == [
            ("event_param", "$.events[0].passenger_ids")
        ]
        assert self.event_codes(lambda b: b.event("payment_dispute", 5, passengers=["p1"])) == [
            ("event_param", "$.events[0].passenger_ids")
        ]

    def test_one_of(self) -> None:
        def request(amount: int) -> Callable[[TripBuilder], TripBuilder]:
            return lambda b: b.event("change_request", 5, passengers=["p1"], amount=amount)

        assert self.event_codes(request(500)) == [("event_param", "$.events[0].amount_piasters")]
        assert self.event_codes(request(5000)) == []

    def test_no_group_members(self) -> None:
        def dispute(ids: list[str]) -> Callable[[TripBuilder], TripBuilder]:
            return lambda b: b.event("payment_dispute", 5, passengers=ids)

        assert self.event_codes(dispute(["p1", "p4"])) == [
            ("event_param", "$.events[0].passenger_ids[1]")
        ]
        assert self.event_codes(dispute(["p1", "p2"])) == []

    def test_messages(self) -> None:
        definition = base().event("open_road", 5, seconds=61).event("traffic", 6).build()
        assert [r.message for r in refusals(definition)] == ["above 60", "required"]
        request = base().event("change_request", 5, passengers=["p1"], amount=500).build()
        assert [r.message for r in refusals(request)] == [
            "must be one of [1000, 2000, 5000, 10000, 20000]"
        ]


def test_pickup_conflict() -> None:
    twice = (
        base()
        .passenger("p3", seat="C_r", dest="gamaa", payment=[1000])
        .event("roadside_pickup", 5, passengers=["p3"])
        .event("roadside_pickup", 10, passengers=["p3"])
        .build()
    )
    assert codes(twice) == [("pickup_conflict", "$.events[1].passenger_ids[0]")]
    boarding = (
        base()
        .passenger("p3", seat="C_r", dest="gamaa", board="kobri", payment=[1000])
        .event("roadside_pickup", 5, passengers=["p3"])
        .build()
    )
    assert codes(boarding) == [("pickup_conflict", "$.events[0].passenger_ids[0]")]


def test_every_problem_is_reported_at_once_in_order_with_paths_and_messages() -> None:
    definition = (
        base()
        .passenger("p3", archetype="bags_lady", seat="D_l", dest="souq", payment=[1000])
        .event("bump", 5, seconds=2)
        .build()
    )
    found = refusals(definition, seed=0)
    assert [(r.code, r.path) for r in found] == [
        ("bad_seed", "seed"),
        ("unsupported_archetype", "$.passengers[2].archetype"),
        ("unknown_seat", "$.passengers[2].seat_id"),
        ("unknown_station", "$.passengers[2].dest_station_id"),
        ("event_param", "$.events[0].seconds"),
    ]
    assert all(r.message for r in found)


def test_start_raises_trip_refused_with_every_refusal() -> None:
    definition = base().passenger("p3", seat="D_l", dest="souq", payment=[1000]).build()
    with pytest.raises(TripRefused) as refused:
        start(definition, default_params(), definition.seed)
    assert len(refused.value.refusals) == 2
    assert isinstance(refused.value.refusals, tuple)


def _shipped() -> list[Path]:
    trips = sorted((SAMPLE / "trips").rglob("*.json"))
    valid = sorted((REPO / "content" / "examples" / "valid" / "trip").glob("*.json"))
    return trips + valid


@pytest.mark.parametrize("path", _shipped(), ids=lambda path: path.name)
def test_every_shipped_trip_is_accepted(path: Path) -> None:
    definition = definition_of(load_json_bytes(path.read_bytes()))
    assert refusals(definition, params=default_params(definition.line_id)) == []
