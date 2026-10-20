"""What the trip engine plays and says: the capabilities file (specs/004 research R13).

`content/engine/capabilities.json` is the single source. `wassal-content codegen` copies it byte
for byte into this package as `engine/capabilities.json`, and `codegen --check` catches a stale
copy, the same way as the schemas. Rules V-T8 to V-T11 read it through `capabilities()`, and so
will B05's solver.

The file is checked against its own shape on load: a misspelt rule key would otherwise silently
check nothing.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from functools import cache
from importlib import resources
from types import MappingProxyType
from typing import Any

from jsonschema import Draft202012Validator

from wassal_content.loader import ContentLoadError, load_json_bytes

__all__ = [
    "CAPABILITIES_FILE",
    "Capabilities",
    "CapabilitiesError",
    "ParameterRule",
    "SpeechSlot",
    "capabilities",
    "parse_capabilities",
]

CAPABILITIES_FILE = "capabilities.json"

_CHANGE_REQUEST = ("change_request", "amount_piasters")
_INTEGER = {"type": "integer"}
_NAMES = {"type": "array", "items": {"type": "string"}, "uniqueItems": True}
_RULE = {
    "type": "object",
    "required": ["use"],
    "properties": {
        "use": {"enum": ["required", "optional"]},
        "min": _INTEGER,
        "max": _INTEGER,
        "min_items": {"type": "integer", "minimum": 0},
        "max_items": {"type": "integer", "minimum": 0},
        "one_of": {"type": "array", "items": _INTEGER, "minItems": 1, "uniqueItems": True},
        "no_group_members": {"type": "boolean"},
    },
    "additionalProperties": False,
}
_SLOT = {
    "type": "object",
    "required": ["slot", "placeholders"],
    "properties": {"slot": {"type": "string"}, "placeholders": _NAMES},
    "additionalProperties": False,
}
_SHAPE = {
    "type": "object",
    "required": ["version", "archetypes", "events", "speech_slots"],
    "properties": {
        "version": {"type": "integer", "minimum": 1},
        "archetypes": _NAMES,
        "events": {
            "type": "object",
            "additionalProperties": {"type": "object", "additionalProperties": _RULE},
        },
        "speech_slots": {"type": "array", "items": _SLOT},
    },
    "additionalProperties": False,
}


class CapabilitiesError(ValueError):
    """A capabilities file that isn't strict JSON or doesn't have the file's shape."""


@dataclass(frozen=True)
class ParameterRule:
    """One parameter of an event's row: whether it must be given, and its bounds.

    `minimum` and `maximum` bound an integer, `min_items` and `max_items` a list's length.
    `one_of` lists the only values allowed, and `no_group_members` forbids naming a passenger who
    has a `group_id`.
    """

    required: bool
    minimum: int | None = None
    maximum: int | None = None
    min_items: int | None = None
    max_items: int | None = None
    one_of: tuple[int, ...] | None = None
    no_group_members: bool = False


@dataclass(frozen=True)
class SpeechSlot:
    """A line the engine says, and the placeholders it fills for it."""

    slot: str
    placeholders: tuple[str, ...]

    @property
    def default_key(self) -> str:
        """The speech pool the slot uses unless a passenger overrides it."""
        return f"passenger.{self.slot}"


@dataclass(frozen=True)
class Capabilities:
    """The archetypes, events and speech slots the engine supports, in the file's order.

    `events` maps each event to its parameters' rules; a parameter it doesn't list is forbidden.
    `change_request_notes` are the notes a change request may ask to break.
    """

    version: int
    archetypes: tuple[str, ...]
    events: Mapping[str, Mapping[str, ParameterRule]]
    speech_slots: Mapping[str, SpeechSlot]
    change_request_notes: tuple[int, ...]

    @property
    def placeholders(self) -> frozenset[str]:
        """Every placeholder some slot fills."""
        return frozenset(name for slot in self.speech_slots.values() for name in slot.placeholders)


def _json_path(path: Any) -> str:
    text = "$"
    for element in path:
        text += f"[{element}]" if isinstance(element, int) else f".{element}"
    return text


def _check_shape(document: Any) -> None:
    error = next(iter(Draft202012Validator(_SHAPE).iter_errors(document)), None)
    if error is not None:
        raise CapabilitiesError(f"{_json_path(error.absolute_path)}: {error.message}")
    seen: set[str] = set()
    for index, slot in enumerate(document["speech_slots"]):
        if slot["slot"] in seen:
            raise CapabilitiesError(
                f"$.speech_slots[{index}].slot: {slot['slot']!r} appears more than once"
            )
        seen.add(slot["slot"])


def _rule(row: Mapping[str, Any]) -> ParameterRule:
    one_of = row.get("one_of")
    return ParameterRule(
        required=row["use"] == "required",
        minimum=row.get("min"),
        maximum=row.get("max"),
        min_items=row.get("min_items"),
        max_items=row.get("max_items"),
        one_of=None if one_of is None else tuple(one_of),
        no_group_members=row.get("no_group_members", False),
    )


def parse_capabilities(data: bytes) -> Capabilities:
    """Read a capabilities file with the strict loader, and check its shape."""
    try:
        document = load_json_bytes(data)
    except ContentLoadError as error:
        raise CapabilitiesError(str(error)) from None
    _check_shape(document)
    events = {
        event_id: MappingProxyType({name: _rule(rule) for name, rule in row.items()})
        for event_id, row in document["events"].items()
    }
    slots = {
        slot["slot"]: SpeechSlot(slot=slot["slot"], placeholders=tuple(slot["placeholders"]))
        for slot in document["speech_slots"]
    }
    event_id, parameter = _CHANGE_REQUEST
    row = events.get(event_id)
    notes = None if row is None else row.get(parameter)
    return Capabilities(
        version=document["version"],
        archetypes=tuple(document["archetypes"]),
        events=MappingProxyType(events),
        speech_slots=MappingProxyType(slots),
        change_request_notes=() if notes is None or notes.one_of is None else notes.one_of,
    )


@cache
def capabilities() -> Capabilities:
    """The packaged capabilities file. It is read once: it never changes at run time."""
    packaged = resources.files("wassal_content").joinpath("engine", CAPABILITIES_FILE)
    return parse_capabilities(packaged.read_bytes())
