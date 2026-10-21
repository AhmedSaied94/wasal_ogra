"""What the mirror supports: its own table of archetypes, events and event parameter rules.

Mirrors `EngineCapabilities` in `packages/trip_engine/lib/src/capabilities.dart`. It is written out
here, not read from `content/engine/capabilities.json`, so a test can require the two to be equal
(spec FR-003): an archetype or event added to one side only fails it. Speech slots aren't mirrored
(research R3).
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from types import MappingProxyType

from wassal_content.engine import Capabilities, ParameterRule


@dataclass(frozen=True, slots=True)
class Supported:
    """The archetypes and events the mirror implements, and each event's parameter rules. A
    parameter an event doesn't list is forbidden."""

    archetypes: tuple[str, ...]
    events: Mapping[str, Mapping[str, ParameterRule]]
    change_request_notes: tuple[int, ...]


CHANGE_REQUEST_NOTES = (1000, 2000, 5000, 10000, 20000)
"""The notes a change request may ask for."""

_SECONDS = ParameterRule(required=True, minimum=1, maximum=60)

SUPPORTED = Supported(
    # The 12 supported archetypes (M01 spec FR-004).
    archetypes=(
        "regular",
        "honest",
        "hajja",
        "sleeper",
        "hurry",
        "big_note",
        "student",
        "headphones",
        "false_claimer",
        "group_payer",
        "chatty",
        "regular_customer",
    ),
    events=MappingProxyType(
        {
            "bump": MappingProxyType({}),
            "traffic": MappingProxyType({"seconds": _SECONDS}),
            "open_road": MappingProxyType({"seconds": _SECONDS}),
            "fare_increase": MappingProxyType(
                {
                    "amount_piasters": ParameterRule(required=True, minimum=50),
                    "passenger_ids": ParameterRule(required=False, min_items=1, max_items=6),
                }
            ),
            "drop_me_here": MappingProxyType(
                {
                    "passenger_ids": ParameterRule(required=True, min_items=1, max_items=1),
                    "seconds": ParameterRule(required=False, minimum=1, maximum=60),
                }
            ),
            "payment_dispute": MappingProxyType(
                {
                    "passenger_ids": ParameterRule(
                        required=True, min_items=2, max_items=2, no_group_members=True
                    ),
                }
            ),
            "change_request": MappingProxyType(
                {
                    "passenger_ids": ParameterRule(required=True, min_items=1, max_items=1),
                    "amount_piasters": ParameterRule(required=True, one_of=CHANGE_REQUEST_NOTES),
                }
            ),
            "roadside_pickup": MappingProxyType(
                {"passenger_ids": ParameterRule(required=True, min_items=1, max_items=6)}
            ),
        }
    ),
    change_request_notes=CHANGE_REQUEST_NOTES,
)


def differences(mirror: Supported, declared: Capabilities) -> list[str]:
    """How `mirror` and the capabilities file differ, one line per archetype, event or
    parameter. Empty when they agree."""
    out: list[str] = []
    out += _only("archetype", mirror.archetypes, declared.archetypes)
    out += _only("event", tuple(mirror.events), tuple(declared.events))
    for event, rules in mirror.events.items():
        other = declared.events.get(event)
        if other is None:
            continue
        where = f"event {event}, parameter"
        out += _only(where, tuple(rules), tuple(other))
        out += [
            f"{where} {name}: the rules differ"
            for name, rule in rules.items()
            if name in other and other[name] != rule
        ]
    if mirror.change_request_notes != declared.change_request_notes:
        out.append("change request notes: they differ")
    return out


def _only(what: str, mirror: tuple[str, ...], declared: tuple[str, ...]) -> list[str]:
    return [
        f"{what} {name}: only the mirror supports it" for name in mirror if name not in declared
    ] + [
        f"{what} {name}: only capabilities.json declares it"
        for name in declared
        if name not in mirror
    ]
