"""Engine rules V-T8 to V-T11: content the trip engine can play and say (specs/004 research R15).

Every list these rules check against comes from the packaged capabilities file, through
`wassal_content.engine.capabilities()`, so the validator can't drift from the engine. They run in
the `content_rules` stage on content that passed the schema stage, and every finding is an error.

- **V-T8 (trip):** each event's parameters follow its row: required ones present, any the row
  doesn't list absent, and the row's bounds respected.
- **V-T9 (trip):** every archetype and every event is one the engine plays.
- **V-T10 (pack):** every slot's default pool exists.
- **V-T11 (pack):** a pool reached through a slot, by its default key or a passenger's override,
  uses only the placeholders that slot fills, and every override is under a slot's name. A
  placeholder that no slot fills is V-X2's, so one mistake gives one finding.

V-T8 and V-T9 need only the trip, so they also run on a lone trip (`trip_engine_findings`).
"""

from __future__ import annotations

from collections.abc import Iterator, Mapping
from typing import Any

from wassal_content.engine import Capabilities, ParameterRule, SpeechSlot, capabilities
from wassal_content.findings import Finding
from wassal_content.rules.content_rules import PLACEHOLDER, localized_texts

__all__ = ["engine_findings", "trip_engine_findings"]

STAGE = "content_rules"
# Every event's own fields. No row lists them: everything else on an event is a parameter.
_EVENT_FIELDS = frozenset({"event_id", "at_seconds"})

Entity = tuple[str, str]


def _error(code: str, entity: Entity, path: str, message: str) -> Finding:
    return Finding(
        path=path, code=code, message=message, stage=STAGE, entity=entity[0], id=entity[1]
    )


# V-T8 and V-T9: one trip


def _list_bounds(
    value: list[Any], rule: ParameterRule, where: tuple[Entity, str, str, str]
) -> Iterator[Finding]:
    entity, path, event_id, name = where
    if rule.min_items is not None and len(value) < rule.min_items:
        yield _error(
            "V-T8",
            entity,
            path,
            f"{event_id} needs at least {rule.min_items} {name}, not {len(value)}",
        )
    if rule.max_items is not None and len(value) > rule.max_items:
        yield _error(
            "V-T8",
            entity,
            path,
            f"{event_id} takes at most {rule.max_items} {name}, not {len(value)}",
        )


def _integer_bounds(
    value: int, rule: ParameterRule, where: tuple[Entity, str, str, str]
) -> Iterator[Finding]:
    entity, path, event_id, name = where
    if rule.minimum is not None and value < rule.minimum:
        yield _error("V-T8", entity, path, f"{name} of {event_id} must be at least {rule.minimum}")
    if rule.maximum is not None and value > rule.maximum:
        yield _error("V-T8", entity, path, f"{name} of {event_id} must be at most {rule.maximum}")
    if rule.one_of is not None and value not in rule.one_of:
        allowed = ", ".join(str(option) for option in rule.one_of)
        yield _error(
            "V-T8", entity, path, f"{name} of {event_id} must be one of {allowed}, not {value}"
        )


def _parameter(
    value: Any,
    rule: ParameterRule,
    where: tuple[Entity, str, str, str],
    groups: Mapping[str, str],
) -> Iterator[Finding]:
    entity, path, event_id, _ = where
    if isinstance(value, list):
        yield from _list_bounds(value, rule, where)
        if rule.no_group_members:
            for m, passenger_id in enumerate(value):
                if passenger_id in groups:
                    yield _error(
                        "V-T8",
                        entity,
                        f"{path}[{m}]",
                        f"{passenger_id} travels in group {groups[passenger_id]}: "
                        f"{event_id} can't name a group member",
                    )
    elif isinstance(value, int) and not isinstance(value, bool):
        yield from _integer_bounds(value, rule, where)


def _events(trip: Mapping[str, Any], entity: Entity, caps: Capabilities) -> Iterator[Finding]:
    groups = {p["passenger_id"]: p["group_id"] for p in trip["passengers"] if "group_id" in p}
    for n, event in enumerate(trip["events"]):
        base = f"$.events[{n}]"
        event_id = event["event_id"]
        row = caps.events.get(event_id)
        if row is None:
            yield _error(
                "V-T9", entity, f"{base}.event_id", f"the engine doesn't play event {event_id!r}"
            )
            continue
        for name in sorted(set(event) - _EVENT_FIELDS - set(row)):
            yield _error("V-T8", entity, f"{base}.{name}", f"{event_id} doesn't take {name}")
        for name, rule in row.items():
            where = (entity, f"{base}.{name}", event_id, name)
            if name in event:
                yield from _parameter(event[name], rule, where, groups)
            elif rule.required:
                yield _error("V-T8", entity, f"{base}.{name}", f"{event_id} needs {name}")


def _archetypes(trip: Mapping[str, Any], entity: Entity, caps: Capabilities) -> Iterator[Finding]:
    for n, passenger in enumerate(trip["passengers"]):
        archetype = passenger["archetype"]
        if archetype not in caps.archetypes:
            yield _error(
                "V-T9",
                entity,
                f"$.passengers[{n}].archetype",
                f"the engine doesn't play archetype {archetype!r}",
            )


def trip_engine_findings(trip: Mapping[str, Any]) -> list[Finding]:
    """V-T8 and V-T9 of one trip that passed the schema stage."""
    caps = capabilities()
    entity: Entity = ("trip", trip["trip_id"])
    return [*_archetypes(trip, entity, caps), *_events(trip, entity, caps)]


# V-T10 and V-T11: the pack's speech


def _default_pools(
    pack: Mapping[str, Any], pools: Mapping[str, Any], caps: Capabilities
) -> Iterator[Finding]:
    for slot in caps.speech_slots.values():
        if slot.default_key not in pools:
            yield _error(
                "V-T10",
                ("pack", pack["pack_id"]),
                "$.speech_pools",
                f"no speech pool {slot.default_key!r} for the engine's slot {slot.slot}",
            )


def _accepted(slot: SpeechSlot) -> str:
    return ", ".join(f"{{{name}}}" for name in slot.placeholders) or "none"


def _unfilled(pool: Any, slot: SpeechSlot, caps: Capabilities) -> Iterator[tuple[str, str]]:
    """(path, name) of every placeholder in `pool` that some slot fills, but not `slot`."""
    for path, text in localized_texts(pool, "$"):
        for name in PLACEHOLDER.findall(text):
            if name in caps.placeholders and name not in slot.placeholders:
                yield path, name


def _default_placeholders(pools: Mapping[str, Any], caps: Capabilities) -> Iterator[Finding]:
    for slot in caps.speech_slots.values():
        pool = pools.get(slot.default_key)
        if pool is None:
            continue  # V-T10
        for path, name in _unfilled(pool, slot, caps):
            yield _error(
                "V-T11",
                ("speech_pool", slot.default_key),
                path,
                f"slot {slot.slot} doesn't fill {{{name}}} (accepted: {_accepted(slot)})",
            )


def _overrides(trip: Any, pools: Mapping[str, Any], caps: Capabilities) -> Iterator[Finding]:
    entity: Entity = ("trip", trip["trip_id"])
    for n, passenger in enumerate(trip["passengers"]):
        for name, key in sorted(passenger.get("speech_keys", {}).items()):
            path = f"$.passengers[{n}].speech_keys.{name}"
            slot = caps.speech_slots.get(name)
            if slot is None:
                yield _error(
                    "V-T11",
                    entity,
                    path,
                    f"{name!r} is not an engine speech slot, so the override is never used",
                )
                continue
            # A missing pool is V-T6's; a slot's own default pool is reported on the pool.
            if key not in pools or key == slot.default_key:
                continue
            unfilled = sorted({placeholder for _, placeholder in _unfilled(pools[key], slot, caps)})
            if unfilled:
                listed = ", ".join(f"{{{placeholder}}}" for placeholder in unfilled)
                yield _error(
                    "V-T11",
                    entity,
                    path,
                    f"pool {key!r} uses {listed}, which slot {name} doesn't fill "
                    f"(accepted: {_accepted(slot)})",
                )


def engine_findings(pack: Mapping[str, Any]) -> list[Finding]:
    """V-T8 to V-T11 of a pack that passed the schema stage."""
    caps = capabilities()
    pools: dict[str, Any] = {}
    for pool in pack["speech_pools"]:
        pools.setdefault(pool["speech_key"], pool)  # V-U1 reports a duplicate
    findings = [finding for trip in pack["trips"] for finding in trip_engine_findings(trip)]
    findings.extend(_default_pools(pack, pools, caps))
    findings.extend(_default_placeholders(pools, caps))
    for trip in pack["trips"]:
        findings.extend(_overrides(trip, pools, caps))
    return findings
