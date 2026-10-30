"""The authored content as pack parts (data-model.md, contracts/content-source.md).

`snapshot()` reads every authoring table in one `REPEATABLE READ` transaction, so a build sees one
consistent state even while authors keep editing (US3-7). The parts it returns are what the
`content/source` reader gives for the same content, so `wassal_content.source.assemble_pack` turns
either into the same `Pack`. The `entity` serializers are reused by the importer to tell which
objects an import changed.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from django.db import connection, transaction
from django.utils import timezone
from wassal_content.models import DenominationKey
from wassal_content.source import SourceTree

from apps.content.models import (
    CatalogPrice,
    Chapter,
    DailyRewardDay,
    FamilyRequest,
    Item,
    Line,
    Room,
    Seat,
    SpeechPool,
    TaskTemplate,
    Trip,
    Vehicle,
)

PACK_ID = "core"
ROWS = ("front", "A", "B", "C", "D")
COLUMNS = ("r", "m", "l")
DRIVER_ROWS = frozenset({"front", "A"})
DENOMINATIONS = tuple(key.value for key in DenominationKey)


@dataclass
class Snapshot:
    """The parts of the current content, when they were read, and the unreviewed speech lines."""

    tree: SourceTree
    snapshot_at: datetime
    unreviewed: list[tuple[str, int]] = field(default_factory=list)  # (speech_key, line index)


def text(main: str, other: str) -> dict[str, str]:
    """A `LocalizedText`. An empty `ar` is left out."""
    return {"ar-EG": main, "ar": other} if other else {"ar-EG": main}


def seat_sort_key(seat_id: str) -> tuple[int, int]:
    row, col = seat_id.split("_")
    return ROWS.index(row), COLUMNS.index(col)


def seat_layout(seats: Iterable[Seat]) -> list[dict[str, Any]]:
    """A vehicle's seats in row and column order, with row, column and reach derived."""
    layout = []
    for seat_id in sorted((seat.seat_id for seat in seats), key=seat_sort_key):
        row, col = seat_id.split("_")
        layout.append(
            {"seat_id": seat_id, "row": row, "col": col, "reachable_by_driver": row in DRIVER_ROWS}
        )
    return layout


# -- one entity each -------------------------------------------------------------------------------


def line_part(line: Line) -> dict[str, Any]:
    unlock: dict[str, Any] = {"kind": line.unlock_kind}
    if line.unlock_vehicle is not None:
        unlock["vehicle_id"] = line.unlock_vehicle.vehicle_id
    if line.unlock_after_line is not None:
        unlock["line_id"] = line.unlock_after_line.line_id
    return {
        "line_id": line.line_id,
        "name": text(line.name_ar_eg, line.name_ar),
        "order": line.order,
        "stations": [
            {"station_id": station.station_id, "name": text(station.name_ar_eg, station.name_ar)}
            for station in sorted(line.stations.all(), key=lambda s: s.order)
        ],
        "unlock": unlock,
        "difficulty_band": {"min": line.difficulty_min, "max": line.difficulty_max},
        "whats_new": text(line.whats_new_ar_eg, line.whats_new_ar),
        "display_fare_piasters": line.display_fare_piasters,
    }


def vehicle_part(vehicle: Vehicle) -> dict[str, Any]:
    return {
        "vehicle_id": vehicle.vehicle_id,
        "name": text(vehicle.name_ar_eg, vehicle.name_ar),
        "short_name": text(vehicle.short_name_ar_eg, vehicle.short_name_ar),
        "order": vehicle.order,
        "starter": vehicle.starter,
        "seats": seat_layout(vehicle.seats.all()),
    }


def trip_part(trip: Trip) -> dict[str, Any]:
    tray = {key: getattr(trip, f"tray_{key}") for key in DENOMINATIONS}
    return {
        "trip_id": trip.trip_id,
        "rev": trip.rev,
        "kind": trip.kind,
        "line_id": trip.line.line_id,
        "vehicle_id": trip.vehicle.vehicle_id,
        "seed": trip.seed,
        "seats": seat_layout(trip.vehicle.seats.all()),
        "stations": [
            {
                "station_id": stop.station.station_id,
                "at_seconds": stop.at_seconds,
                "fare_piasters": stop.fare_piasters,
            }
            for stop in sorted(trip.trip_stations.all(), key=lambda s: s.at_seconds)
        ],
        "initial_tray": {key: count for key, count in tray.items() if count},
        "rules": {
            "student_discount_pct": trip.student_discount_pct,
            "bag_fare_piasters": trip.bag_fare_piasters,
            "child_free_age": trip.child_free_age,
            "max_break_requests": trip.max_break_requests,
            "no_fights_required": trip.no_fights_required,
        },
        "passengers": [
            passenger_part(p) for p in sorted(trip.passengers.all(), key=lambda p: p.order)
        ],
        "events": [event_part(e) for e in sorted(trip.events.all(), key=lambda e: e.order)],
        "star_rules": {"two": trip.star_two, "three": trip.star_three},
        "max_earnings_jenehat": trip.max_earnings_jenehat,
    }


def passenger_part(passenger: Any) -> dict[str, Any]:
    part: dict[str, Any] = {
        "passenger_id": passenger.passenger_id,
        "archetype": passenger.archetype,
        "skin": passenger.skin,
        "seat_id": passenger.seat.seat_id,
        "dest_station_id": passenger.dest_station.station_id,
        "payment": list(passenger.payment),
    }
    if passenger.board_station is not None:
        part["board_station_id"] = passenger.board_station.station_id
    if passenger.pays_at_seconds is not None:
        part["pays_at_seconds"] = passenger.pays_at_seconds
    if passenger.group_id:
        part["group_id"] = passenger.group_id
        part["group_size"] = passenger.group_size
    if passenger.speech_keys is not None:
        part["speech_keys"] = dict(passenger.speech_keys)
    return part


def event_part(event: Any) -> dict[str, Any]:
    part: dict[str, Any] = {"event_id": event.event_id, "at_seconds": event.at_seconds}
    if event.passenger_ids:
        part["passenger_ids"] = list(event.passenger_ids)
    if event.station_id:
        part["station_id"] = event.station_id
    if event.amount_piasters is not None:
        part["amount_piasters"] = event.amount_piasters
    if event.seconds is not None:
        part["seconds"] = event.seconds
    return part


def chapter_part(chapter: Chapter) -> dict[str, Any]:
    goal: dict[str, Any] = {"kind": chapter.goal_kind}
    if chapter.goal_line is not None:
        goal["line_id"] = chapter.goal_line.line_id
    if chapter.goal_vehicle is not None:
        goal["vehicle_id"] = chapter.goal_vehicle.vehicle_id
    if chapter.goal_room is not None:
        goal["room_id"] = chapter.goal_room.room_id
    part: dict[str, Any] = {
        "chapter_id": chapter.chapter_id,
        "order": chapter.order,
        "title": text(chapter.title_ar_eg, chapter.title_ar),
        "goal": goal,
        "completion_bonat": chapter.completion_bonat,
        "scenes": [scene_part(s) for s in sorted(chapter.scenes.all(), key=lambda s: s.order)],
    }
    if chapter.story_trip is not None:
        part["story_trip_id"] = chapter.story_trip.trip_id
    # M10's fields, written only when set, so a pack without them round-trips unchanged.
    if chapter.goal_art:
        part["goal_art"] = chapter.goal_art
    if chapter.goal_line_speaker:
        part["goal_line"] = {
            "speaker": chapter.goal_line_speaker,
            "text": text(chapter.goal_line_ar_eg, chapter.goal_line_ar),
        }
    if chapter.ready_line_ar_eg:
        part["ready_line"] = text(chapter.ready_line_ar_eg, chapter.ready_line_ar)
    if chapter.tagline_ar_eg:
        part["tagline"] = text(chapter.tagline_ar_eg, chapter.tagline_ar)
    riders = sorted(chapter.riders.all(), key=lambda r: r.order)
    # A story trip the author left half-written is emitted as it is, so the schema refuses the
    # shape: dropping its riders or its condition would publish a pack missing them (R1-6).
    if (
        chapter.story_title_ar_eg
        or chapter.story_condition_ar_eg
        or chapter.story_fail_reason_ar_eg
        or riders
    ):
        info: dict[str, Any] = {
            "title": text(chapter.story_title_ar_eg, chapter.story_title_ar),
            "riders": [rider_part(rider) for rider in riders],
        }
        if chapter.story_condition_ar_eg:
            info["condition"] = text(chapter.story_condition_ar_eg, chapter.story_condition_ar)
        if chapter.story_fail_reason_ar_eg:
            info["fail_reason"] = text(
                chapter.story_fail_reason_ar_eg, chapter.story_fail_reason_ar
            )
        part["story_trip_info"] = info
    return part


def rider_part(rider: Any) -> dict[str, Any]:
    part: dict[str, Any] = {"character": rider.character, "seat": rider.seat_id}
    comments = {
        "short_change": rider.comment_short_change,
        "false_accusation": rider.comment_false_accusation,
        "fight": rider.comment_fight,
        "missed_stop": rider.comment_missed_stop,
        "impatient": rider.comment_impatient,
    }
    written = {slot: key for slot, key in comments.items() if key}
    if written:
        part["comments"] = written
    return part


def scene_part(scene: Any) -> dict[str, Any]:
    lines = sorted(scene.lines.all(), key=lambda line: (line.panel, line.order))
    part: dict[str, Any] = {
        "scene_id": scene.scene_id,
        "title": text(scene.title_ar_eg, scene.title_ar),
        "panels": [
            {
                "art": art,
                "lines": [
                    {"speaker": line.speaker, "text": text(line.text_ar_eg, line.text_ar)}
                    for line in lines
                    if line.panel == number
                ],
            }
            for number, art in enumerate(scene.panel_art, start=1)
        ],
    }
    if scene.plays_kind:
        plays: dict[str, Any] = {"kind": scene.plays_kind}
        if scene.plays_trip is not None:
            plays["trip_id"] = scene.plays_trip.trip_id
        part["plays"] = plays
    return part


def room_part(room: Room) -> dict[str, Any]:
    part: dict[str, Any] = {
        "room_id": room.room_id,
        "name": text(room.name_ar_eg, room.name_ar),
        "order": room.order,
        "chapter_id": room.chapter.chapter_id,
        "completion_bonat": room.completion_bonat,
    }
    if room.art:
        part["art"] = room.art
    if room.done_line_ar_eg:
        part["done_line"] = text(room.done_line_ar_eg, room.done_line_ar)
    return part


def item_part(item: Item) -> dict[str, Any]:
    part: dict[str, Any] = {
        "item_id": item.item_id,
        "room_id": item.room.room_id,
        "name": text(item.name_ar_eg, item.name_ar),
        "order": item.order,
        "slot": {"x": item.slot_x, "y": item.slot_y, "w": item.slot_w, "h": item.slot_h},
        "variants": [],
    }
    if item.comment_ar_eg:
        part["comment"] = text(item.comment_ar_eg, item.comment_ar)
    for variant in sorted(item.variants.all(), key=lambda v: v.order):
        variant_part: dict[str, Any] = {
            "variant_id": variant.variant_id,
            "name": text(variant.name_ar_eg, variant.name_ar),
            "art": variant.art,
        }
        if variant.comment_ar_eg:
            variant_part["comment"] = text(variant.comment_ar_eg, variant.comment_ar)
        part["variants"].append(variant_part)
    return part


def request_part(request: FamilyRequest) -> dict[str, Any]:
    part: dict[str, Any] = {
        "request_id": request.request_id,
        "room_id": request.room.room_id,
        "item_id": request.item.item_id,
        "character": request.character,
        "text": text(request.text_ar_eg, request.text_ar),
        "reward_bonat": request.reward_bonat,
    }
    if request.variant is not None:
        part["variant_id"] = request.variant.variant_id
    return part


def pool_part(pool: SpeechPool) -> dict[str, Any]:
    return {
        "speech_key": pool.speech_key,
        "lines": [
            {"text": text(line.text_ar_eg, line.text_ar)}
            for line in sorted(pool.lines.all(), key=lambda line: line.order)
        ],
    }


def price_part(price: CatalogPrice) -> dict[str, Any]:
    return {
        "sku_kind": price.sku_kind,
        "sku_id": price.sku_id,
        "currency": price.currency,
        "amount": price.amount,
    }


def day_part(day: DailyRewardDay) -> dict[str, Any]:
    return {"day_index": day.day_index, "jenehat": day.jenehat, "bonat": day.bonat}


def task_part(task: TaskTemplate) -> dict[str, Any]:
    return {
        "task_id": task.task_id,
        "metric": task.metric,
        "target": task.target,
        "text": text(task.text_ar_eg, task.text_ar),
        "reward_jenehat": task.reward_jenehat,
        "reward_bonat": task.reward_bonat,
    }


# -- querysets with what the serializers traverse -------------------------------------------------


def lines() -> Any:
    return Line.objects.select_related("unlock_vehicle", "unlock_after_line").prefetch_related(
        "stations"
    )


def vehicles() -> Any:
    return Vehicle.objects.prefetch_related("seats")


def trips() -> Any:
    return Trip.objects.select_related("line", "vehicle").prefetch_related(
        "vehicle__seats",
        "trip_stations__station",
        "passengers__seat",
        "passengers__board_station",
        "passengers__dest_station",
        "events",
    )


def chapters() -> Any:
    return Chapter.objects.select_related(
        "goal_line", "goal_vehicle", "goal_room", "story_trip__line"
    ).prefetch_related("scenes__lines", "scenes__plays_trip__line", "riders")


def rooms() -> Any:
    return Room.objects.select_related("chapter")


def items() -> Any:
    return Item.objects.select_related("room").prefetch_related("variants")


def requests() -> Any:
    return FamilyRequest.objects.select_related("room", "item__room", "variant")


def pools() -> Any:
    return SpeechPool.objects.prefetch_related("lines")


# -- the whole content ----------------------------------------------------------------------------


def snapshot(schema_version: str) -> Snapshot:
    """Every authored part, read in one consistent transaction."""
    outermost = not connection.in_atomic_block
    with transaction.atomic():
        if outermost:
            # Only a transaction's first statement can set its isolation level. Inside a caller's
            # transaction (a test, say) the reads already share that transaction's snapshot.
            with connection.cursor() as cursor:
                cursor.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
        return _read(schema_version)


def _read(schema_version: str) -> Snapshot:
    snapshot_at = timezone.now()
    tree = SourceTree(meta={"pack_id": PACK_ID, "schema_version": schema_version, "version": 0})
    tree.parts["lines"] = [line_part(line) for line in lines()]
    tree.parts["vehicles"] = [vehicle_part(vehicle) for vehicle in vehicles()]
    tree.parts["trips"] = [trip_part(trip) for trip in trips()]
    tree.parts["chapters"] = [chapter_part(chapter) for chapter in chapters()]
    tree.parts["rooms"] = [room_part(room) for room in rooms()]
    tree.parts["items"] = [item_part(item) for item in items()]
    tree.parts["family_requests"] = [request_part(request) for request in requests()]
    unreviewed: list[tuple[str, int]] = []
    pool_parts = []
    for pool in pools():
        pool_parts.append(pool_part(pool))
        for index, line in enumerate(sorted(pool.lines.all(), key=lambda line: line.order)):
            if not line.is_reviewed:
                unreviewed.append((pool.speech_key, index))
    tree.parts["speech_pools"] = pool_parts
    tree.parts["daily_rewards"] = [day_part(day) for day in DailyRewardDay.objects.all()]
    tree.parts["tasks"] = [task_part(task) for task in TaskTemplate.objects.filter(active=True)]
    tree.catalog = {"prices": [price_part(price) for price in CatalogPrice.objects.all()]}
    return Snapshot(tree=tree, snapshot_at=snapshot_at, unreviewed=sorted(unreviewed))
