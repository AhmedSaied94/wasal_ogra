"""Stage 2, references: everything a pack names resolves inside the same pack.

The rule codes and texts are those of contracts/content-schemas.md "Rules beyond shape". The pack
has already passed the schema stage, so every field has its type. Findings name the entity and its
identifier, with a path inside that entity.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from typing import Any

from wassal_content.findings import Finding
from wassal_content.schemas import IDENTIFIER_FIELDS, PACK_ARRAYS

__all__ = ["BONAT_SKUS", "reference_findings", "trip_local_findings"]

STAGE = "references"

# Every BONAT SKU of glossary §3.3, which each pack prices exactly once (data-model CatalogPrice).
BONAT_SKUS: frozenset[tuple[str, str]] = frozenset(
    {
        ("booster", "change_bag"),
        ("booster", "wake_all"),
        ("booster", "ledger_peek"),
        ("booster", "traffic_jam"),
        ("fuel", "refuel_full"),
        ("revive", "revive"),
        ("fuel_unlimited", "fuel_unlimited_1h"),
    }
)
_DRIVER_ROWS = frozenset({"front", "A"})
_UNLOCK_FIELD = {"start": None, "vehicle": "vehicle_id", "line_complete": "line_id"}
_GOAL_FIELD = {
    "complete_line": "line_id",
    "own_vehicle": "vehicle_id",
    "complete_room": "room_id",
    "purchase": None,
}
# A panel line by this speaker is the panel's caption (M07 research R5), not a bubble.
NARRATOR = "narrator"

Entity = tuple[str, str]


def _error(code: str, entity: Entity, path: str, message: str) -> Finding:
    return Finding(
        path=path, code=code, message=message, stage=STAGE, entity=entity[0], id=entity[1]
    )


def price_entity(kind: str, sku: str) -> Entity:
    """How a catalog price is named in a report."""
    return "catalog_price", f"{kind}:{sku}"


@dataclass(frozen=True)
class _Index:
    """The pack's entities by identifier. The first of a duplicate wins; V-U1 reports the rest."""

    lines: Mapping[str, Any]
    vehicles: Mapping[str, Any]
    trips: Mapping[str, Any]
    chapters: Mapping[str, Any]
    rooms: Mapping[str, Any]
    items: Mapping[str, Any]
    pools: frozenset[str]
    prices: Counter[tuple[str, str]]


def _by_id(elements: list[Any], field: str) -> dict[str, Any]:
    found: dict[str, Any] = {}
    for element in elements:
        found.setdefault(element[field], element)
    return found


def _index(pack: Mapping[str, Any]) -> _Index:
    return _Index(
        lines=_by_id(pack["lines"], "line_id"),
        vehicles=_by_id(pack["vehicles"], "vehicle_id"),
        trips=_by_id(pack["trips"], "trip_id"),
        chapters=_by_id(pack["chapters"], "chapter_id"),
        rooms=_by_id(pack["rooms"], "room_id"),
        items=_by_id(pack["items"], "item_id"),
        pools=frozenset(pool["speech_key"] for pool in pack["speech_pools"]),
        prices=Counter((p["sku_kind"], p["sku_id"]) for p in pack["catalog"]["prices"]),
    )


def _duplicates(
    elements: list[Any], field: str, entity: Entity, base: str, code: str = "V-U1"
) -> Iterator[Finding]:
    seen: set[Any] = set()
    for index, element in enumerate(elements):
        value = element[field]
        if value in seen:
            yield _error(
                code,
                entity,
                f"{base}[{index}].{field}",
                f"{field} {value!r} appears more than once",
            )
        seen.add(value)


# Trips (V-T1 to V-T7)


def _trip_stations(trip: Any, entity: Entity, ix: _Index) -> Iterator[Finding]:
    line = ix.lines.get(trip["line_id"])
    if line is None:
        yield _error("V-T2", entity, "$.line_id", f"line {trip['line_id']!r} is not in this pack")
        return
    order = {station["station_id"]: n for n, station in enumerate(line["stations"])}
    last = -1
    for n, station in enumerate(trip["stations"]):
        station_id = station["station_id"]
        if station_id not in order:
            yield _error(
                "V-T2",
                entity,
                f"$.stations[{n}].station_id",
                f"{station_id!r} is not a station of {trip['line_id']}",
            )
        elif order[station_id] <= last:
            yield _error(
                "V-T2",
                entity,
                f"$.stations[{n}].station_id",
                f"{station_id!r} comes before the previous station on {trip['line_id']}",
            )
        else:
            last = order[station_id]
        if n and station["at_seconds"] <= trip["stations"][n - 1]["at_seconds"]:
            yield _error(
                "V-T2",
                entity,
                f"$.stations[{n}].at_seconds",
                "at_seconds must be later than the previous station's",
            )


def _seat_layout(seats: list[Any], entity: Entity) -> Iterator[Finding]:
    for n, seat in enumerate(seats):
        row, col = seat["seat_id"].split("_")
        expected = {"row": row, "col": col, "reachable_by_driver": row in _DRIVER_ROWS}
        for field, value in expected.items():
            if seat[field] != value:
                yield _error(
                    "V-T3",
                    entity,
                    f"$.seats[{n}].{field}",
                    f"{field} of {seat['seat_id']} must be {value!r}",
                )
    yield from _duplicates(seats, "seat_id", entity, "$.seats")


def _trip_seats(trip: Any, entity: Entity, ix: _Index) -> Iterator[Finding]:
    vehicle = ix.vehicles.get(trip["vehicle_id"])
    if vehicle is None:
        yield _error(
            "V-T3", entity, "$.vehicle_id", f"vehicle {trip['vehicle_id']!r} is not in this pack"
        )
    elif trip["seats"] != vehicle["seats"]:
        yield _error(
            "V-T3", entity, "$.seats", f"seats differ from {trip['vehicle_id']}'s seat layout"
        )
    yield from _seat_layout(trip["seats"], entity)


def _passengers(trip: Any, entity: Entity) -> Iterator[Finding]:
    seat_ids = {seat["seat_id"] for seat in trip["seats"]}
    stops = [station["station_id"] for station in trip["stations"]]
    for n, passenger in enumerate(trip["passengers"]):
        base = f"$.passengers[{n}]"
        if passenger["seat_id"] not in seat_ids:
            yield _error(
                "V-T4", entity, f"{base}.seat_id", f"{passenger['seat_id']!r} is not a seat here"
            )
        dest = passenger["dest_station_id"]
        if dest not in stops:
            yield _error(
                "V-T4", entity, f"{base}.dest_station_id", f"{dest!r} is not a station of this trip"
            )
        board = passenger.get("board_station_id")
        if board is not None and board not in stops:
            yield _error(
                "V-T4",
                entity,
                f"{base}.board_station_id",
                f"{board!r} is not a station of this trip",
            )
        elif board is not None and dest in stops and stops.index(board) >= stops.index(dest):
            yield _error(
                "V-T4",
                entity,
                f"{base}.board_station_id",
                f"{board!r} must come before the destination {dest!r}",
            )
    yield from _duplicates(trip["passengers"], "passenger_id", entity, "$.passengers")


def _speech_keys(trip: Any, entity: Entity, ix: _Index) -> Iterator[Finding]:
    for n, passenger in enumerate(trip["passengers"]):
        for slot, key in sorted(passenger.get("speech_keys", {}).items()):
            if key not in ix.pools:
                yield _error(
                    "V-T6",
                    entity,
                    f"$.passengers[{n}].speech_keys.{slot}",
                    f"no speech pool {key!r}",
                )


def _groups(trip: Any, entity: Entity) -> Iterator[Finding]:
    groups: dict[str, list[tuple[int, Any]]] = defaultdict(list)
    for n, passenger in enumerate(trip["passengers"]):
        has_id, has_size = "group_id" in passenger, "group_size" in passenger
        if has_id != has_size:
            missing = "group_size" if has_id else "group_id"
            yield _error(
                "V-T5",
                entity,
                f"$.passengers[{n}].{missing}",
                "group_id and group_size are set together",
            )
        elif has_id:
            groups[passenger["group_id"]].append((n, passenger))
    # A group may list fewer members than its size: backend §9.3 lists only the payer.
    for group_id, members in sorted(groups.items()):
        size = members[0][1]["group_size"]
        for n, passenger in members[1:]:
            if passenger["group_size"] != size:
                yield _error(
                    "V-T5",
                    entity,
                    f"$.passengers[{n}].group_size",
                    f"group {group_id} has size {size} on its first member",
                )
        if len(members) > size:
            yield _error(
                "V-T5",
                entity,
                f"$.passengers[{members[size][0]}].group_id",
                f"group {group_id} lists {len(members)} members, more than its size {size}",
            )


def _events(trip: Any, entity: Entity) -> Iterator[Finding]:
    passenger_ids = {passenger["passenger_id"] for passenger in trip["passengers"]}
    stops = {station["station_id"] for station in trip["stations"]}
    for n, event in enumerate(trip["events"]):
        for m, passenger_id in enumerate(event.get("passenger_ids", [])):
            if passenger_id not in passenger_ids:
                yield _error(
                    "V-T6",
                    entity,
                    f"$.events[{n}].passenger_ids[{m}]",
                    f"no passenger {passenger_id!r} in this trip",
                )
        station_id = event.get("station_id")
        if station_id is not None and station_id not in stops:
            yield _error(
                "V-T6",
                entity,
                f"$.events[{n}].station_id",
                f"{station_id!r} is not a station of this trip",
            )


def _trip_local(trip: Any, entity: Entity) -> Iterator[Finding]:
    if not trip["trip_id"].startswith(trip["line_id"] + "."):
        yield _error(
            "V-T1",
            entity,
            "$.trip_id",
            f"trip_id doesn't start with its line_id {trip['line_id']!r}",
        )
    yield from _passengers(trip, entity)
    yield from _groups(trip, entity)
    yield from _events(trip, entity)


def trip_local_findings(trip: Any) -> list[Finding]:
    """The reference rules a trip can break on its own, without a pack (V-T1, V-T4 to V-T6).

    A lone trip, such as a parity fixture's definition or a daily challenge, has no pack, so
    its line, vehicle and speech pools aren't checked. The trip has passed the schema.
    """
    return sorted(_trip_local(trip, ("trip", trip["trip_id"])))


def _trip(trip: Any, ix: _Index) -> Iterator[Finding]:
    entity: Entity = ("trip", trip["trip_id"])
    yield from _trip_local(trip, entity)
    yield from _trip_stations(trip, entity, ix)
    yield from _trip_seats(trip, entity, ix)
    yield from _speech_keys(trip, entity, ix)


def _trip_numbers(trips: list[Any]) -> Iterator[Finding]:
    seen: set[str] = set()
    for trip in trips:
        if trip["trip_id"] in seen:
            yield _error(
                "V-T7", ("trip", trip["trip_id"]), "$.trip_id", "trip_id appears more than once"
            )
        seen.add(trip["trip_id"])
    numbers: dict[str, set[int]] = defaultdict(set)
    for trip in trips:
        prefix, _, number = trip["trip_id"].rpartition(".")
        if prefix == trip["line_id"]:
            numbers[prefix].add(int(number))
    for line_id, found in sorted(numbers.items()):
        missing = sorted(set(range(1, max(found) + 1)) - found)
        if missing:
            listed = ", ".join(f"{n:02d}" for n in missing)
            yield _error(
                "V-T7",
                ("line", line_id),
                "$",
                f"trips are numbered from 01 with no gaps: missing {listed}",
            )


# Lines, chapters, rooms and items


def _line(line: Any, ix: _Index) -> Iterator[Finding]:
    entity: Entity = ("line", line["line_id"])
    unlock = line["unlock"]
    needed = _UNLOCK_FIELD[unlock["kind"]]
    for field in ("vehicle_id", "line_id"):
        if field in unlock and field != needed:
            yield _error(
                "V-L1", entity, f"$.unlock.{field}", f"unlock {unlock['kind']} doesn't use {field}"
            )
    if needed is not None and needed not in unlock:
        yield _error("V-L1", entity, "$.unlock", f"unlock {unlock['kind']} needs {needed}")
    elif needed == "vehicle_id" and unlock["vehicle_id"] not in ix.vehicles:
        yield _error(
            "V-L1", entity, "$.unlock.vehicle_id", f"{unlock['vehicle_id']!r} is not in this pack"
        )
    elif needed == "line_id" and unlock["line_id"] == line["line_id"]:
        yield _error("V-L1", entity, "$.unlock.line_id", "a line can't unlock itself")
    elif needed == "line_id" and unlock["line_id"] not in ix.lines:
        yield _error(
            "V-L1", entity, "$.unlock.line_id", f"{unlock['line_id']!r} is not in this pack"
        )
    band = line["difficulty_band"]
    if band["min"] > band["max"]:
        yield _error("V-L2", entity, "$.difficulty_band", "difficulty_band min is above max")
    yield from _duplicates(line["stations"], "station_id", entity, "$.stations", code="V-L2")


def _vehicle(vehicle: Any) -> Iterator[Finding]:
    yield from _seat_layout(vehicle["seats"], ("vehicle", vehicle["vehicle_id"]))


def _chapter(chapter: Any, ix: _Index) -> Iterator[Finding]:
    entity: Entity = ("chapter", chapter["chapter_id"])
    goal = chapter["goal"]
    needed = _GOAL_FIELD[goal["kind"]]
    targets = {"line_id": ix.lines, "vehicle_id": ix.vehicles, "room_id": ix.rooms}
    for field in targets:
        if field in goal and field != needed:
            yield _error(
                "V-C1", entity, f"$.goal.{field}", f"goal {goal['kind']} doesn't use {field}"
            )
    if needed is not None and needed not in goal:
        yield _error("V-C1", entity, "$.goal", f"goal {goal['kind']} needs {needed}")
    elif needed is not None and goal[needed] not in targets[needed]:
        yield _error("V-C1", entity, f"$.goal.{needed}", f"{goal[needed]!r} is not in this pack")
    elif needed is None and ix.prices[("chapter", chapter["chapter_id"])] == 0:
        yield _error(
            "V-C1",
            entity,
            "$.goal",
            f"a purchase goal needs the catalog price (chapter, {chapter['chapter_id']})",
        )
    story = chapter.get("story_trip_id")
    if story is not None and story not in ix.trips:
        yield _error("V-C2", entity, "$.story_trip_id", f"trip {story!r} is not in this pack")
    elif story is not None and ix.trips[story]["kind"] != "story":
        yield _error("V-C2", entity, "$.story_trip_id", f"trip {story!r} is not a story trip")
    yield from _narrators(chapter, entity)
    yield from _duplicates(chapter["scenes"], "scene_id", entity, "$.scenes")


def _narrators(chapter: Any, entity: Entity) -> Iterator[Finding]:
    """V-C5: a panel's `narrator` line is its caption, so it comes first, and once."""
    for n, scene in enumerate(chapter["scenes"]):
        for m, panel in enumerate(scene["panels"]):
            seen = False
            for k, line in enumerate(panel["lines"]):
                if line["speaker"] != NARRATOR:
                    continue
                if k:
                    yield _error(
                        "V-C5",
                        entity,
                        f"$.scenes[{n}].panels[{m}].lines[{k}].speaker",
                        "a panel has at most one narrator line"
                        if seen
                        else "a panel's narrator line comes first",
                    )
                seen = True


def _scene_plays(chapters: list[Any], ix: _Index) -> Iterator[Finding]:
    """V-C3 and V-C4: when the app plays a scene by itself (`plays`), across the pack.

    The first opening and the first scene of each trip, in chapter order, are the ones kept.
    """
    opening: str | None = None
    claimed: dict[str, str] = {}
    for chapter in sorted(chapters, key=lambda c: (c["order"], c["chapter_id"])):
        entity: Entity = ("chapter", chapter["chapter_id"])
        for n, scene in enumerate(chapter["scenes"]):
            plays = scene.get("plays")
            if plays is None:
                continue
            base, here = f"$.scenes[{n}].plays", f"{chapter['chapter_id']}/{scene['scene_id']}"
            trip_id = plays.get("trip_id")
            if plays["kind"] == "opening":
                if chapter["order"] != 1:
                    yield _error(
                        "V-C3",
                        entity,
                        f"{base}.kind",
                        "only the chapter of order 1 has an opening scene",
                    )
                if opening is not None:
                    yield _error(
                        "V-C3", entity, f"{base}.kind", f"the pack already opens with {opening}"
                    )
                else:
                    opening = here
                if trip_id is not None:
                    yield _error(
                        "V-C3", entity, f"{base}.trip_id", "an opening scene names no trip_id"
                    )
            elif trip_id is None:
                yield _error("V-C4", entity, base, "an after_trip scene needs trip_id")
            elif trip_id not in ix.trips:
                yield _error(
                    "V-C4", entity, f"{base}.trip_id", f"trip {trip_id!r} is not in this pack"
                )
            elif trip_id in claimed:
                yield _error(
                    "V-C4",
                    entity,
                    f"{base}.trip_id",
                    f"trip {trip_id!r} already plays {claimed[trip_id]}",
                )
            else:
                claimed[trip_id] = here


def _room(room: Any, ix: _Index) -> Iterator[Finding]:
    if room["chapter_id"] not in ix.chapters:
        yield _error(
            "V-R1",
            ("room", room["room_id"]),
            "$.chapter_id",
            f"chapter {room['chapter_id']!r} is not in this pack",
        )


def _item(item: Any, ix: _Index) -> Iterator[Finding]:
    entity: Entity = ("item", item["item_id"])
    if item["room_id"] not in ix.rooms:
        yield _error("V-R1", entity, "$.room_id", f"room {item['room_id']!r} is not in this pack")
    if not item["item_id"].startswith(item["room_id"] + "."):
        yield _error(
            "V-R1",
            entity,
            "$.item_id",
            f"item_id doesn't start with its room_id {item['room_id']!r}",
        )
    yield from _duplicates(item["variants"], "variant_id", entity, "$.variants", code="V-R1")


def _family_request(request: Any, ix: _Index) -> Iterator[Finding]:
    entity: Entity = ("family_request", request["request_id"])
    if request["room_id"] not in ix.rooms:
        yield _error(
            "V-R2", entity, "$.room_id", f"room {request['room_id']!r} is not in this pack"
        )
    item = ix.items.get(request["item_id"])
    if item is None:
        yield _error(
            "V-R2", entity, "$.item_id", f"item {request['item_id']!r} is not in this pack"
        )
        return
    if item["room_id"] != request["room_id"]:
        yield _error(
            "V-R2", entity, "$.item_id", f"{request['item_id']!r} is in room {item['room_id']!r}"
        )
    variant = request.get("variant_id")
    if variant is not None and variant not in {v["variant_id"] for v in item["variants"]}:
        yield _error(
            "V-R2", entity, "$.variant_id", f"{variant!r} is not a variant of {request['item_id']}"
        )


# The catalog, daily rewards and tasks


def _catalog(ix: _Index) -> Iterator[Finding]:
    sold: dict[tuple[str, str], Entity] = {}
    sold.update({("item", item_id): ("item", item_id) for item_id in ix.items})
    sold.update(
        {
            ("vehicle", vehicle_id): ("vehicle", vehicle_id)
            for vehicle_id, vehicle in ix.vehicles.items()
            if not vehicle["starter"]
        }
    )
    sold.update(
        {
            ("chapter", chapter_id): ("chapter", chapter_id)
            for chapter_id, chapter in ix.chapters.items()
            if chapter["goal"]["kind"] == "purchase"
        }
    )
    sold.update({key: price_entity(*key) for key in BONAT_SKUS})
    for key, entity in sorted(sold.items()):
        if ix.prices[key] == 0:
            yield _error("V-K1", entity, "$", f"{key[0]} {key[1]} has no catalog price")
    for key, count in sorted(ix.prices.items()):
        if key not in sold:
            yield _error(
                "V-K1",
                price_entity(*key),
                "$",
                f"nothing in this pack is sold as {key[0]} {key[1]}",
            )
        elif count > 1:
            yield _error("V-K1", price_entity(*key), "$", f"priced {count} times")


def _rewards(pack: Mapping[str, Any]) -> Iterator[Finding]:
    days = {day["day_index"] for day in pack["daily_rewards"]}
    for missing in sorted(set(range(1, 8)) - days):
        yield _error(
            "V-D1", ("pack", pack["pack_id"]), "$.daily_rewards", f"day {missing} is missing"
        )
    for day in pack["daily_rewards"]:
        if day["jenehat"] == 0 and day["bonat"] == 0:
            yield _error(
                "V-D1", ("daily_reward", str(day["day_index"])), "$", "the day grants nothing"
            )
    for task in pack["tasks"]:
        if task["reward_jenehat"] == 0 and task["reward_bonat"] == 0:
            yield _error("V-D1", ("task", task["task_id"]), "$", "the task grants nothing")


def _identifiers(pack: Mapping[str, Any]) -> Iterator[Finding]:
    # Trips are V-T7's, with their numbering.
    for array, part in PACK_ARRAYS.items():
        if part == "trip":
            continue
        field = IDENTIFIER_FIELDS[part]
        seen: set[Any] = set()
        for element in pack[array]:
            value = element[field]
            if value in seen:
                yield _error(
                    "V-U1", (part, str(value)), f"$.{field}", f"{field} {value!r} appears twice"
                )
            seen.add(value)


def reference_findings(pack: Mapping[str, Any]) -> list[Finding]:
    """Every reference finding of a pack that passed the schema stage."""
    ix = _index(pack)
    findings: list[Finding] = []
    for trip in pack["trips"]:
        findings.extend(_trip(trip, ix))
    findings.extend(_trip_numbers(pack["trips"]))
    for line in pack["lines"]:
        findings.extend(_line(line, ix))
    for vehicle in pack["vehicles"]:
        findings.extend(_vehicle(vehicle))
    for chapter in pack["chapters"]:
        findings.extend(_chapter(chapter, ix))
    findings.extend(_scene_plays(pack["chapters"], ix))
    for room in pack["rooms"]:
        findings.extend(_room(room, ix))
    for item in pack["items"]:
        findings.extend(_item(item, ix))
    for request in pack["family_requests"]:
        findings.extend(_family_request(request, ix))
    findings.extend(_catalog(ix))
    findings.extend(_rewards(pack))
    findings.extend(_identifiers(pack))
    return findings
