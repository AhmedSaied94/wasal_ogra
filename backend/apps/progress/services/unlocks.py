"""Unlock and completion rules (B03 research R6), as pure functions.

They read a pack's rules document (`apps.content.services.lookups.rules_document`) and a read-only
view of the player, and touch no database. Each rule is permissive where a mistake could only let a
player do something harmless, and strict where it protects value: a room with no items, or a line
with no regular trips, is never complete, so it never pays a reward.

M10 must show the same unlocks. If its design needs a different rule, change it here, tests first.

The phone has a port of these rules (`apps/mobile/lib/core/progress/domain/unlocks.dart`, M08) and
of their tests (`apps/mobile/test/core/progress/unlocks_test.dart`). When this file or its tests
change, change the port in the same PR.
"""

from __future__ import annotations

from collections.abc import Mapping, Set
from dataclasses import dataclass
from typing import Any

REGULAR = "regular"
STORY = "story"

Rules = Mapping[str, Any]


@dataclass(frozen=True)
class PlayerView:
    """What the rules read of a player: best stars by trip, and what they own as `(kind, sku_id)`
    (`vehicle`, `item`, `chapter`, ...)."""

    best_stars: Mapping[str, int]
    owned: Set[tuple[str, str]]


@dataclass(frozen=True)
class Completion:
    """A room or chapter that is complete and not yet rewarded."""

    kind: str  # "room" or "chapter"
    id: str
    bonat: int


def vehicle_owned(rules: Rules, view: PlayerView, vehicle_id: str) -> bool:
    vehicle = rules["vehicles"].get(vehicle_id)
    if vehicle is None:
        return False
    return bool(vehicle["starter"]) or ("vehicle", vehicle_id) in view.owned


def line_complete(rules: Rules, view: PlayerView, line_id: str) -> bool:
    """Every regular trip of the line has at least one star. A line without one never is."""
    line = rules["lines"].get(line_id)
    if line is None:
        return False
    regular = [t for t in line["trips"] if rules["trips"][t]["kind"] == REGULAR]
    return bool(regular) and all(view.best_stars.get(t, 0) >= 1 for t in regular)


def line_unlocked(rules: Rules, view: PlayerView, line_id: str) -> bool:
    line = rules["lines"].get(line_id)
    if line is None:
        return False
    unlock = line["unlock"]
    if unlock["kind"] == "start":
        return True
    if unlock["kind"] == "vehicle":
        return vehicle_owned(rules, view, unlock["vehicle_id"])
    if unlock["kind"] == "line_complete":
        return line_complete(rules, view, unlock["line_id"])
    return False


def trip_unlocked(rules: Rules, view: PlayerView, trip_id: str) -> bool:
    """A story trip needs only its chapter unlocked. Any other needs its line unlocked, its vehicle
    owned, and the regular trip before it in the line at one star or more (the first has none)."""
    trip = rules["trips"].get(trip_id)
    if trip is None:
        return False
    if trip["kind"] == STORY:
        chapter = _chapter_of_story_trip(rules, trip_id)
        if chapter is not None:
            return chapter_unlocked(rules, view, chapter)
    if not line_unlocked(rules, view, trip["line_id"]):
        return False
    if not vehicle_owned(rules, view, trip["vehicle_id"]):
        return False
    previous = _previous_regular(rules, trip["line_id"], trip_id)
    return previous is None or view.best_stars.get(previous, 0) >= 1


def chapter_unlocked(rules: Rules, view: PlayerView, chapter_id: str) -> bool:
    """The first chapter always; chapter n when chapter n-1 is complete."""
    order = _chapter_order(rules)
    if chapter_id not in order:
        return False
    index = order.index(chapter_id)
    return index == 0 or chapter_complete(rules, view, order[index - 1])


def chapter_complete(rules: Rules, view: PlayerView, chapter_id: str) -> bool:
    """Unlocked, and its goal met. Chapters therefore complete in order."""
    order = _chapter_order(rules)
    if chapter_id not in order:
        return False
    return all(_goal_met(rules, view, chapter) for chapter in order[: order.index(chapter_id) + 1])


def room_complete(rules: Rules, view: PlayerView, room_id: str) -> bool:
    """The player owns every item of the room. A room without items never is."""
    room = rules["rooms"].get(room_id)
    if room is None:
        return False
    items = room["items"]
    return bool(items) and all(("item", item) in view.owned for item in items)


def item_purchasable(rules: Rules, view: PlayerView, item_id: str) -> bool:
    """Its room's chapter is unlocked."""
    item = rules["items"].get(item_id)
    if item is None:
        return False
    room = rules["rooms"].get(item["room_id"])
    return room is not None and chapter_unlocked(rules, view, room["chapter_id"])


def newly_completed(
    rules: Rules, view: PlayerView, granted: Set[tuple[str, str]]
) -> list[Completion]:
    """Rooms, then chapters, each in `order`, that are complete and have no grant record
    (`("room", id)`, `("chapter", id)` in `granted`)."""
    rooms = sorted(rules["rooms"].items(), key=lambda kv: (kv[1]["order"], kv[0]))
    found = [
        Completion("room", room_id, int(room["completion_bonat"]))
        for room_id, room in rooms
        if ("room", room_id) not in granted and room_complete(rules, view, room_id)
    ]
    found += [
        Completion("chapter", chapter_id, int(rules["chapters"][chapter_id]["completion_bonat"]))
        for chapter_id in _chapter_order(rules)
        if ("chapter", chapter_id) not in granted and chapter_complete(rules, view, chapter_id)
    ]
    return found


def _goal_met(rules: Rules, view: PlayerView, chapter_id: str) -> bool:
    goal = rules["chapters"][chapter_id]["goal"]
    kind = goal["kind"]
    if kind == "complete_line":
        return line_complete(rules, view, goal["line_id"])
    if kind == "own_vehicle":
        return vehicle_owned(rules, view, goal["vehicle_id"])
    if kind == "purchase":
        return ("chapter", chapter_id) in view.owned
    if kind == "complete_room":
        return room_complete(rules, view, goal["room_id"])
    return False


def _chapter_order(rules: Rules) -> list[str]:
    chapters = rules["chapters"]
    return sorted(chapters, key=lambda c: (chapters[c]["order"], c))


def _chapter_of_story_trip(rules: Rules, trip_id: str) -> str | None:
    for chapter_id in _chapter_order(rules):
        if rules["chapters"][chapter_id].get("story_trip_id") == trip_id:
            return chapter_id
    return None


def _previous_regular(rules: Rules, line_id: str, trip_id: str) -> str | None:
    trips = rules["lines"][line_id]["trips"]
    if trip_id not in trips:
        return None
    earlier = trips[: trips.index(trip_id)]
    regular = [t for t in earlier if rules["trips"][t]["kind"] == REGULAR]
    return regular[-1] if regular else None


def current_chapter(rules: Rules, view: PlayerView) -> str | None:
    """Where the player is in the story (B03 research R16): the highest unlocked chapter that
    isn't complete, else the last complete one, else the first. None for a pack with none."""
    order = _chapter_order(rules)
    if not order:
        return None
    open_chapters = [
        c
        for c in order
        if chapter_unlocked(rules, view, c) and not chapter_complete(rules, view, c)
    ]
    if open_chapters:
        return open_chapters[-1]
    complete = [c for c in order if chapter_complete(rules, view, c)]
    return complete[-1] if complete else order[0]
