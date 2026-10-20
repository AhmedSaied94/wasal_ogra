"""The engine's capabilities file and its typed loader (specs/004 research R13, T010)."""

import dataclasses
import json
from typing import Any

import pytest

from tests.paths import ENGINE
from wassal_content.engine import (
    Capabilities,
    CapabilitiesError,
    ParameterRule,
    capabilities,
    parse_capabilities,
)

SOURCE = ENGINE / "capabilities.json"
RAW: dict[str, Any] = json.loads(SOURCE.read_text())


def test_the_loader_reads_every_archetype_event_and_slot() -> None:
    caps = capabilities()
    assert caps.version == RAW["version"]
    assert caps.archetypes == tuple(RAW["archetypes"])
    assert list(caps.events) == list(RAW["events"])
    for event_id, row in RAW["events"].items():
        assert set(caps.events[event_id]) == set(row)
    assert list(caps.speech_slots) == [slot["slot"] for slot in RAW["speech_slots"]]
    for slot in RAW["speech_slots"]:
        assert caps.speech_slots[slot["slot"]].placeholders == tuple(slot["placeholders"])


def test_parameter_rules_keep_their_bounds() -> None:
    events = capabilities().events
    assert events["bump"] == {}
    assert events["traffic"]["seconds"] == ParameterRule(required=True, minimum=1, maximum=60)
    assert events["fare_increase"]["passenger_ids"] == ParameterRule(
        required=False, min_items=1, max_items=6
    )
    dispute = events["payment_dispute"]["passenger_ids"]
    assert (dispute.min_items, dispute.max_items, dispute.no_group_members) == (2, 2, True)


def test_slots_name_their_default_key_and_placeholders() -> None:
    slots = capabilities().speech_slots
    assert slots["pays"].default_key == "passenger.pays"
    assert slots["stop_near"].placeholders == ("station",)
    assert slots["thanks"].placeholders == ()
    assert capabilities().placeholders == frozenset(
        name for slot in RAW["speech_slots"] for name in slot["placeholders"]
    )


def test_the_change_request_notes_are_the_amounts_it_allows() -> None:
    row = RAW["events"]["change_request"]["amount_piasters"]
    assert capabilities().change_request_notes == tuple(row["one_of"])


def test_the_loader_is_cached_and_read_only() -> None:
    caps = capabilities()
    assert capabilities() is caps
    with pytest.raises(dataclasses.FrozenInstanceError):
        caps.version = 2  # type: ignore[misc]
    with pytest.raises(TypeError):
        caps.events["flood"] = {}  # type: ignore[index]


def test_parsing_the_source_gives_the_packaged_capabilities() -> None:
    parsed = parse_capabilities(SOURCE.read_bytes())
    assert isinstance(parsed, Capabilities)
    assert parsed == capabilities()


def _with(**changes: Any) -> bytes:
    return json.dumps({**RAW, **changes}).encode()


def _rule(**rule: Any) -> bytes:
    return _with(events={"traffic": {"seconds": rule}})


@pytest.mark.parametrize(
    ("data", "match"),
    [
        (b'{"version": 1.0}', "only integers"),
        (b"[]", r"\$: .* is not of type 'object'"),
        (_with(owner="engine"), r"\$: .*'owner' was unexpected"),
        (_with(version=0), r"\$\.version"),
        (_with(archetypes=["regular", "regular"]), r"\$\.archetypes"),
        (_rule(use="sometimes"), r"\$\.events\.traffic\.seconds\.use"),
        (_rule(use="required", max_item=6), r"seconds: .*'max_item' was unexpected"),
        (_rule(min=1), r"\$\.events\.traffic\.seconds: 'use' is a required property"),
        (_rule(use="required", one_of=[]), r"\$\.events\.traffic\.seconds\.one_of"),
        (_rule(use="required", no_group_members="yes"), r"no_group_members"),
        (
            _with(speech_slots=[{"slot": "pays", "placeholders": []}] * 2),
            r"\$\.speech_slots\[1\]\.slot: 'pays' appears more than once",
        ),
        (
            _with(speech_slots=[{"slot": "pays", "placeholders": ["amount", "amount"]}]),
            r"\$\.speech_slots\[0\]\.placeholders",
        ),
    ],
    ids=[
        "not strict JSON",
        "not an object",
        "unknown key",
        "version 0",
        "duplicate archetype",
        "unknown use",
        "unknown rule key",
        "rule without use",
        "empty one_of",
        "no_group_members not a boolean",
        "duplicate slot",
        "duplicate placeholder",
    ],
)
def test_a_malformed_file_is_refused_with_its_path(data: bytes, match: str) -> None:
    with pytest.raises(CapabilitiesError, match=match):
        parse_capabilities(data)
