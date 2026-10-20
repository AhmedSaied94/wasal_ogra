"""Rules V-T8 to V-T11: content the engine can play and say (specs/004, content-contract §3, T008).

Each case breaks one copy of a sample trip, or of the sample pack, and expects exactly the findings
it names, by code, entity, identifier and path. The rules read the packaged capabilities file, so
the cases that cover every event build their events from it.
"""

import copy
import json
import shutil
from pathlib import Path
from typing import Any

import pytest

from tests.paths import EXAMPLES
from wassal_content.cli import main
from wassal_content.engine import ParameterRule, capabilities
from wassal_content.findings import Finding
from wassal_content.loader import load_json_file
from wassal_content.rules import engine_findings, trip_engine_findings
from wassal_content.schemas import SchemaSet
from wassal_content.source import assemble_pack, read_layout
from wassal_content.validate import document_findings, validate_pack

SAMPLE = EXAMPLES / "sample"
VALID_TRIPS = sorted((EXAMPLES / "valid" / "trip").glob("*.json"))
# Sample line_hay.02: p1 and p2 travel as group g1, p3 and p4 alone.
TRIP: dict[str, Any] = load_json_file(SAMPLE / "trips" / "line_hay" / "line_hay.02.json")
HAY_02 = ("trip", "line_hay.02")
ALONE = ["p3", "p4"]
EVENT_IDS = list(capabilities().events)

Key = tuple[str, str, str, str]


def _keys(findings: list[Finding]) -> set[Key]:
    return {(f.code, f.entity, f.id, f.path) for f in findings}


def _sample_pack() -> dict[str, Any]:
    tree, findings = read_layout(SAMPLE)
    assert findings == []
    return assemble_pack(tree, 1)


def _with_events(*events: dict[str, Any]) -> dict[str, Any]:
    trip = copy.deepcopy(TRIP)
    trip["events"] = list(events)
    return trip


def _valid_value(rule: ParameterRule) -> Any:
    if rule.one_of is not None:
        return rule.one_of[0]
    if rule.min_items is not None:
        return ALONE[: rule.min_items]
    return rule.minimum


def _minimal(event_id: str) -> dict[str, Any]:
    """The event with only its required parameters, each at a value its row allows."""
    event: dict[str, Any] = {"event_id": event_id, "at_seconds": 20}
    for name, rule in capabilities().events[event_id].items():
        if rule.required:
            event[name] = _valid_value(rule)
    return event


def _pack_trip(pack: dict[str, Any], trip_id: str) -> dict[str, Any]:
    return next(trip for trip in pack["trips"] if trip["trip_id"] == trip_id)


def _pool(pack: dict[str, Any], key: str) -> dict[str, Any]:
    return next(pool for pool in pack["speech_pools"] if pool["speech_key"] == key)


# V-T8: event parameters

V_T8: list[tuple[str, dict[str, Any], str]] = [
    ("bump with seconds", {"event_id": "bump", "at_seconds": 20, "seconds": 5},
     "$.events[0].seconds"),
    ("traffic without seconds", {"event_id": "traffic", "at_seconds": 20}, "$.events[0].seconds"),
    ("traffic for 0 seconds", {"event_id": "traffic", "at_seconds": 20, "seconds": 0},
     "$.events[0].seconds"),
    ("traffic for 61 seconds", {"event_id": "traffic", "at_seconds": 20, "seconds": 61},
     "$.events[0].seconds"),
    ("fare_increase without amount_piasters", {"event_id": "fare_increase", "at_seconds": 20},
     "$.events[0].amount_piasters"),
    ("drop_me_here with 2 passengers",
     {"event_id": "drop_me_here", "at_seconds": 20, "passenger_ids": ["p3", "p4"]},
     "$.events[0].passenger_ids"),
    ("payment_dispute with 1 passenger",
     {"event_id": "payment_dispute", "at_seconds": 20, "passenger_ids": ["p3"]},
     "$.events[0].passenger_ids"),
    ("payment_dispute naming a group member",
     {"event_id": "payment_dispute", "at_seconds": 20, "passenger_ids": ["p3", "p2"]},
     "$.events[0].passenger_ids[1]"),
    ("change_request for 500",
     {"event_id": "change_request", "at_seconds": 20, "passenger_ids": ["p3"],
      "amount_piasters": 500},
     "$.events[0].amount_piasters"),
    ("roadside_pickup with 7 passengers",
     {"event_id": "roadside_pickup", "at_seconds": 20,
      "passenger_ids": [f"p{n}" for n in range(1, 8)]},
     "$.events[0].passenger_ids"),
]  # fmt: skip


@pytest.mark.parametrize(("event", "path"), [pytest.param(e, p, id=name) for name, e, p in V_T8])
def test_v_t8_refuses_a_parameter_its_row_doesnt_allow(event: dict[str, Any], path: str) -> None:
    assert _keys(trip_engine_findings(_with_events(event))) == {("V-T8", *HAY_02, path)}


@pytest.mark.parametrize("event_id", EVENT_IDS)
def test_v_t8_refuses_a_station_on_every_event(event_id: str) -> None:
    event = {**_minimal(event_id), "station_id": "forn"}
    assert _keys(trip_engine_findings(_with_events(event))) == {
        ("V-T8", *HAY_02, "$.events[0].station_id")
    }


@pytest.mark.parametrize("event_id", EVENT_IDS)
def test_an_event_with_its_required_parameters_is_clean(event_id: str) -> None:
    assert trip_engine_findings(_with_events(_minimal(event_id))) == []


def test_optional_parameters_may_be_given() -> None:
    trip = _with_events(
        {"event_id": "fare_increase", "at_seconds": 20, "amount_piasters": 50,
         "passenger_ids": ["p1", "p2", "p3"]},
        {"event_id": "drop_me_here", "at_seconds": 30, "passenger_ids": ["p1"], "seconds": 60},
        {"event_id": "open_road", "at_seconds": 40, "seconds": 1},
    )  # fmt: skip
    assert trip_engine_findings(trip) == []


def test_every_engine_finding_is_an_error_of_the_content_rules_stage() -> None:
    trip = _with_events(*(event for _, event, _ in V_T8))
    findings = trip_engine_findings(trip)
    assert len(findings) == len(V_T8)
    assert {(f.severity, f.stage) for f in findings} == {("error", "content_rules")}
    assert all(f.message for f in findings)


# V-T9: archetypes and events the engine supports


def test_v_t9_refuses_an_archetype_the_engine_doesnt_play() -> None:
    trip = copy.deepcopy(TRIP)
    trip["passengers"][2]["archetype"] = "bags_lady"
    assert _keys(trip_engine_findings(trip)) == {("V-T9", *HAY_02, "$.passengers[2].archetype")}


def test_v_t9_refuses_an_event_the_engine_doesnt_play() -> None:
    # The schema's enum already refuses it: a trip built in code bypasses the schema.
    trip = _with_events({"event_id": "flood", "at_seconds": 20, "seconds": 5})
    assert _keys(trip_engine_findings(trip)) == {("V-T9", *HAY_02, "$.events[0].event_id")}


# V-T10: a pool for every slot


def test_v_t10_refuses_a_pack_without_a_slots_default_pool() -> None:
    pack = _sample_pack()
    pack["speech_pools"].remove(_pool(pack, "passenger.tip"))
    assert _keys(engine_findings(pack)) == {("V-T10", "pack", "core", "$.speech_pools")}


# V-T11: slot placeholders and slot names


def test_v_t11_refuses_a_placeholder_the_default_slot_doesnt_fill() -> None:
    pack = _sample_pack()
    text = _pool(pack, "passenger.pays")["lines"][0]["text"]
    text["ar-EG"] += " على {station}"
    # line_hay.02's p1 also says passenger.pays for pays_group, which doesn't fill it either.
    # line_hay.03's p1 says it for pays: that is the default pair, reported once on the pool.
    assert _keys(engine_findings(pack)) == {
        ("V-T11", "speech_pool", "passenger.pays", "$.lines[0].text.ar-EG"),
        ("V-T11", *HAY_02, "$.passengers[0].speech_keys.pays_group"),
    }


def test_v_t11_refuses_an_override_pool_with_a_placeholder_its_slot_doesnt_fill() -> None:
    pack = _sample_pack()
    pack["speech_pools"].append(
        {"speech_key": "passenger.hajja_stop", "lines": [{"text": {"ar-EG": "خد {amount} ونزّلني"}}]}
    )
    _pack_trip(pack, "line_hay.02")["passengers"][2]["speech_keys"] = {
        "stop_near": "passenger.hajja_stop"
    }
    assert _keys(engine_findings(pack)) == {
        ("V-T11", *HAY_02, "$.passengers[2].speech_keys.stop_near")
    }


def test_v_t11_refuses_an_override_under_a_name_that_is_not_a_slot() -> None:
    pack = _sample_pack()
    _pack_trip(pack, "line_hay.02")["passengers"][2]["speech_keys"] = {
        "stop": "passenger.stop_near"
    }
    assert _keys(engine_findings(pack)) == {("V-T11", *HAY_02, "$.passengers[2].speech_keys.stop")}


def test_v_t11_leaves_unknown_placeholders_to_v_x2(schema_set: SchemaSet) -> None:
    pack = _sample_pack()
    _pool(pack, "passenger.thanks")["lines"][0]["text"]["ar-EG"] += " {target}"
    assert engine_findings(pack) == []
    report = validate_pack(pack, file_size=None, schema_set=schema_set)
    assert {f.code for f in report.findings} == {"V-X2"}


# Through validate_pack, a lone document and the CLI


def test_the_sample_pack_is_clean(schema_set: SchemaSet) -> None:
    pack = _sample_pack()
    assert engine_findings(pack) == []
    report = validate_pack(pack, file_size=None, schema_set=schema_set)
    assert report.findings == []
    assert report.passed


@pytest.mark.parametrize("path", VALID_TRIPS, ids=lambda path: path.name)
def test_the_valid_trip_examples_are_clean(path: Path, schema_set: SchemaSet) -> None:
    trip = load_json_file(path)
    assert trip_engine_findings(trip) == []
    assert document_findings("trip", trip, schema_set=schema_set) == []


def test_validate_pack_runs_the_engine_rules_in_the_content_rules_stage(
    schema_set: SchemaSet,
) -> None:
    pack = _sample_pack()
    _pack_trip(pack, "line_hay.02")["events"][0] = {"event_id": "bump", "at_seconds": 40,
                                                    "seconds": 10}  # fmt: skip
    pack["speech_pools"].remove(_pool(pack, "passenger.tip"))
    report = validate_pack(pack, file_size=None, schema_set=schema_set)
    assert report.stages["schema"] == report.stages["references"] == "passed"
    assert report.stages["content_rules"] == "failed"
    assert _keys(report.findings) == {
        ("V-T8", *HAY_02, "$.events[0].seconds"),
        ("V-T10", "pack", "core", "$.speech_pools"),
    }


def test_a_lone_trip_gets_v_t8_and_v_t9_with_its_file(schema_set: SchemaSet) -> None:
    trip = _with_events({"event_id": "bump", "at_seconds": 20, "seconds": 5})
    trip["passengers"][2]["archetype"] = "bags_lady"
    findings = document_findings("trip", trip, file="daily.json", schema_set=schema_set)
    assert _keys(findings) == {
        ("V-T8", *HAY_02, "$.events[0].seconds"),
        ("V-T9", *HAY_02, "$.passengers[2].archetype"),
    }
    assert {f.file for f in findings} == {"daily.json"}


def test_a_lone_trip_that_fails_the_schema_gets_only_the_schema_findings(
    schema_set: SchemaSet,
) -> None:
    trip = _with_events({"event_id": "traffic", "at_seconds": 20, "seconds": 61})
    trip["passengers"][2]["archetype"] = "bags_lady"
    findings = document_findings("trip", trip, schema_set=schema_set)
    assert _keys(findings) == {("V-SC", *HAY_02, "$.events[0].seconds")}


def test_a_lone_trip_is_not_checked_for_pack_rules(schema_set: SchemaSet) -> None:
    # V-T10 and V-T11 need the pack's pools, so they run only on packs.
    trip = copy.deepcopy(TRIP)
    trip["passengers"][2]["speech_keys"] = {"stop": "passenger.nowhere"}
    assert document_findings("trip", trip, schema_set=schema_set) == []


def test_other_parts_get_only_the_schema(schema_set: SchemaSet) -> None:
    line = load_json_file(SAMPLE / "lines" / "line_hay.json")
    assert document_findings("line", line, schema_set=schema_set) == []


def test_validate_reports_v_t8_and_v_t9_on_a_lone_trip(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    trip = _with_events({"event_id": "bump", "at_seconds": 20, "seconds": 5})
    trip["passengers"][2]["archetype"] = "bags_lady"
    path = tmp_path / "daily.json"
    path.write_text(json.dumps(trip, ensure_ascii=False))
    assert main(["validate", str(path), "--part", "trip"]) == 1
    out = capsys.readouterr().out
    assert f"{path}: $.events[0].seconds [V-T8] trip line_hay.02: " in out
    assert f"{path}: $.passengers[2].archetype [V-T9] trip line_hay.02: " in out


def test_validate_source_reports_a_missing_engine_pool(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    shutil.copytree(SAMPLE, tmp_path / "sample")
    (tmp_path / "sample" / "speech" / "passenger.tip.json").unlink()
    assert main(["validate-source", str(tmp_path / "sample")]) == 1
    assert "$.speech_pools [V-T10] pack core: " in capsys.readouterr().out
