"""The server models read every valid example and write it back in canonical form (FR-009)."""

import copy
from pathlib import Path
from typing import Any

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from pydantic import ValidationError

from tests.paths import EXAMPLES, SCHEMAS
from wassal_content.canonical import canonical_bytes
from wassal_content.loader import load_json_file
from wassal_content.models import ROOT_MODELS, SCHEMA_SET_VERSION, parse, to_json_dict
from wassal_content.models._generated import Denomination, Line, TripDefinition
from wassal_content.schemas import PARTS, load_schema_set

# Loaded once: hypothesis tests can't use function-scoped fixtures.
SCHEMA_SET = load_schema_set(SCHEMAS)

VALID = sorted((EXAMPLES / "valid").glob("*/*.json"))
TRIP: dict[str, Any] = load_json_file(EXAMPLES / "valid" / "trip" / "line_gamaa.12.json")


def test_every_part_has_a_root_model() -> None:
    assert set(ROOT_MODELS) == set(PARTS)
    assert SCHEMA_SET_VERSION == "1.0"


@pytest.mark.parametrize("path", VALID, ids=lambda p: f"{p.parent.name}/{p.name}")
def test_valid_examples_round_trip_canonically(path: Path) -> None:
    document = load_json_file(path)
    model = parse(path.parent.name, document)
    assert canonical_bytes(to_json_dict(model)) == canonical_bytes(document)
    assert parse(path.parent.name, to_json_dict(model)) == model


def test_unknown_fields_are_ignored() -> None:
    newer = copy.deepcopy(TRIP)
    newer["future_field"] = 1
    newer["passengers"][0]["future_field"] = {"nested": [1, 2]}
    model = parse("trip", newer)
    assert canonical_bytes(to_json_dict(model)) == canonical_bytes(TRIP)


def test_optional_fields_are_left_out_not_null() -> None:
    model = TripDefinition.model_validate(TRIP)
    dumped = to_json_dict(model)
    assert "board_station_id" not in dumped["passengers"][0]
    assert model.passengers[0].board_station_id is None


def test_aliases_are_written_back() -> None:
    model = Line.model_validate(load_json_file(EXAMPLES / "valid" / "line" / "line_hay.json"))
    assert model.name.ar_eg
    assert "ar-EG" in to_json_dict(model)["name"]


def test_models_are_strict_about_types() -> None:
    broken = copy.deepcopy(TRIP)
    broken["seed"] = "3141592653"
    with pytest.raises(ValidationError):
        parse("trip", broken)


def test_models_are_frozen() -> None:
    model = TripDefinition.model_validate(TRIP)
    with pytest.raises(ValidationError):
        model.rev = 2  # type: ignore[misc]


_piasters = st.integers(min_value=1, max_value=40).map(lambda n: n * 50)
_denominations = st.lists(st.sampled_from([int(d) for d in Denomination]), min_size=1, max_size=10)


@st.composite
def _trips(draw: st.DrawFn) -> dict[str, Any]:
    trip = copy.deepcopy(TRIP)
    trip["seed"] = draw(st.integers(min_value=1, max_value=4294967295))
    trip["rev"] = draw(st.integers(min_value=1, max_value=1000))
    times = sorted(draw(st.sets(st.integers(1, 600), min_size=3, max_size=3)))
    for station, at in zip(trip["stations"], times, strict=True):
        station["at_seconds"] = at
        station["fare_piasters"] = draw(_piasters)
    for passenger in trip["passengers"]:
        passenger["payment"] = draw(_denominations)
        if draw(st.booleans()):
            passenger["pays_at_seconds"] = draw(st.integers(0, 600))
        else:
            passenger.pop("pays_at_seconds", None)
    trip["max_earnings_jenehat"] = draw(st.integers(0, 10_000))
    return trip


@settings(max_examples=60)
@given(_trips())
def test_generated_trips_round_trip(trip: dict[str, Any]) -> None:
    assert SCHEMA_SET.validate_document("trip", trip) == []
    model = TripDefinition.model_validate(trip)
    again = TripDefinition.model_validate(to_json_dict(model))
    assert again == model
    assert canonical_bytes(to_json_dict(again)) == canonical_bytes(trip)
