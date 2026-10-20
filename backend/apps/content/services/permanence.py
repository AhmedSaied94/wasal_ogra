"""Permanent identifiers (FR-016, data-model.md `PublishedIdentifier`).

Publishing on `source` records every identifier of the pack. From then on `PermanentModel.save()`
and the `pre_delete` receivers in `signals.py` refuse to rename or delete it.
"""

from __future__ import annotations

from collections.abc import Iterator, Mapping
from typing import Any

from apps.content.errors import PermanenceError
from apps.content.models import PermanentModel, PublishedIdentifier

Kind = PublishedIdentifier.Kind


def identifiers(pack: Mapping[str, Any]) -> Iterator[tuple[str, str]]:
    """Every `(kind, identifier)` of a pack, qualified as `PermanentModel` formats them."""
    for line in pack["lines"]:
        yield Kind.LINE, line["line_id"]
        for station in line["stations"]:
            yield Kind.STATION, f"{line['line_id']}/{station['station_id']}"
    for vehicle in pack["vehicles"]:
        yield Kind.VEHICLE, vehicle["vehicle_id"]
        for seat in vehicle["seats"]:
            yield Kind.SEAT, f"{vehicle['vehicle_id']}/{seat['seat_id']}"
    for trip in pack["trips"]:
        yield Kind.TRIP, trip["trip_id"]
    for chapter in pack["chapters"]:
        yield Kind.CHAPTER, chapter["chapter_id"]
        for scene in chapter["scenes"]:
            yield Kind.SCENE, f"{chapter['chapter_id']}/{scene['scene_id']}"
    for room in pack["rooms"]:
        yield Kind.ROOM, room["room_id"]
    for item in pack["items"]:
        yield Kind.ITEM, item["item_id"]
        for variant in item["variants"]:
            yield Kind.VARIANT, f"{item['item_id']}/{variant['variant_id']}"
    for request in pack["family_requests"]:
        yield Kind.REQUEST, request["request_id"]
    for pool in pack["speech_pools"]:
        yield Kind.SPEECH_KEY, pool["speech_key"]
    for task in pack["tasks"]:
        yield Kind.TASK, task["task_id"]


def record_published(pack: Mapping[str, Any], version: int) -> int:
    """Record the pack's identifiers. One already recorded keeps its first version."""
    rows = [
        PublishedIdentifier(kind=kind, identifier=identifier, first_version=version)
        for kind, identifier in identifiers(pack)
    ]
    return len(PublishedIdentifier.objects.bulk_create(rows, ignore_conflicts=True))


def published_version(kind: str, identifier: str) -> int | None:
    """The first published version that contained the identifier, or `None`."""
    return (
        PublishedIdentifier.objects.filter(kind=kind, identifier=identifier)
        .values_list("first_version", flat=True)
        .first()
    )


def refuse_rename(instance: PermanentModel) -> None:
    stored = instance.stored_identifier()
    if stored is None or stored == instance.permanent_identifier():
        return
    _refuse(instance.permanent_kind, stored, "renamed")


def refuse_delete(instance: PermanentModel) -> None:
    stored = instance.stored_identifier()
    if stored is not None:
        _refuse(instance.permanent_kind, stored, "deleted")


def _refuse(kind: str, identifier: str, action: str) -> None:
    version = published_version(kind, identifier)
    if version is not None:
        raise PermanenceError(kind, identifier, version, action)
