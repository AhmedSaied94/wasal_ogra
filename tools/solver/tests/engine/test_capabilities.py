"""The mirror supports what the engine declares (spec FR-003, US1 scenario 5).

`SUPPORTED` is written out in the mirror's code, and `content/engine/capabilities.json` is what
content validation reads. The two must name the same archetypes, events and event parameter rules.
Speech slots aren't mirrored (research R3), so they aren't compared.
"""

from __future__ import annotations

import dataclasses
from types import MappingProxyType

from wassal_content.engine import ParameterRule, capabilities

from wassal_solver.engine.capabilities import SUPPORTED, Supported, differences


def test_the_mirror_supports_exactly_the_declared_capabilities() -> None:
    assert differences(SUPPORTED, capabilities()) == []
    assert set(SUPPORTED.archetypes) == set(capabilities().archetypes)
    assert dict(SUPPORTED.events) == dict(capabilities().events)
    assert SUPPORTED.change_request_notes == capabilities().change_request_notes


def test_the_counts() -> None:
    assert len(SUPPORTED.archetypes) == 12
    assert len(SUPPORTED.events) == 8
    assert SUPPORTED.change_request_notes == (1000, 2000, 5000, 10000, 20000)


def test_an_archetype_on_one_side_only_is_a_difference() -> None:
    more = dataclasses.replace(SUPPORTED, archetypes=(*SUPPORTED.archetypes, "dodger"))
    assert differences(more, capabilities()) == ["archetype dodger: only the mirror supports it"]
    fewer = dataclasses.replace(SUPPORTED, archetypes=SUPPORTED.archetypes[1:])
    assert differences(fewer, capabilities()) == [
        f"archetype {SUPPORTED.archetypes[0]}: only capabilities.json declares it"
    ]


def test_an_event_on_one_side_only_is_a_difference() -> None:
    events = dict(SUPPORTED.events)
    del events["bump"]
    fewer = dataclasses.replace(SUPPORTED, events=MappingProxyType(events))
    assert differences(fewer, capabilities()) == ["event bump: only capabilities.json declares it"]
    events = dict(SUPPORTED.events) | {"rain": MappingProxyType({})}
    more = dataclasses.replace(SUPPORTED, events=MappingProxyType(events))
    assert differences(more, capabilities()) == ["event rain: only the mirror supports it"]


def test_a_changed_parameter_rule_is_a_difference() -> None:
    events = dict(SUPPORTED.events)
    events["traffic"] = MappingProxyType(
        {"seconds": ParameterRule(required=True, minimum=1, maximum=90)}
    )
    changed = dataclasses.replace(SUPPORTED, events=MappingProxyType(events))
    assert differences(changed, capabilities()) == [
        "event traffic, parameter seconds: the rules differ"
    ]
    events["traffic"] = MappingProxyType({})
    dropped = dataclasses.replace(SUPPORTED, events=MappingProxyType(events))
    assert differences(dropped, capabilities()) == [
        "event traffic, parameter seconds: only capabilities.json declares it"
    ]


def test_supported_is_frozen() -> None:
    assert isinstance(SUPPORTED, Supported)
    assert dataclasses.is_dataclass(SUPPORTED)
    assert isinstance(SUPPORTED.events, MappingProxyType)
