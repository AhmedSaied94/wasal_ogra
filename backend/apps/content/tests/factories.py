"""Small builders for content rows and packs. Field values are ASCII placeholders: real player
text lives in content files, never in code."""

from __future__ import annotations

import gzip
import hashlib
from typing import Any

from django.db import transaction

from apps.content.models import (
    Chapter,
    ContentChannel,
    ContentPack,
    Item,
    ItemVariant,
    Line,
    PublishedIdentifier,
    Room,
    Seat,
    SpeechLine,
    SpeechPool,
    Station,
    Trip,
    Vehicle,
)
from apps.content.models.packs import BuildState, Origin, Status


def line(line_id: str = "line_hay", order: int = 1, **fields: Any) -> Line:
    defaults = {
        "name_ar_eg": "name",
        "unlock_kind": "start",
        "difficulty_min": 0,
        "difficulty_max": 30,
    }
    return Line.objects.create(line_id=line_id, order=order, **{**defaults, **fields})


def station(of: Line, station_id: str = "kobri", order: int = 1) -> Station:
    return Station.objects.create(line=of, station_id=station_id, name_ar_eg="name", order=order)


def vehicle(vehicle_id: str = "micro_old", order: int = 1, **fields: Any) -> Vehicle:
    return Vehicle.objects.create(vehicle_id=vehicle_id, name_ar_eg="name", order=order, **fields)


def seat(of: Vehicle, seat_id: str = "A_l") -> Seat:
    return Seat.objects.create(vehicle=of, seat_id=seat_id)


def trip(on: Line, by: Vehicle, number: int = 1, **fields: Any) -> Trip:
    defaults = {
        "max_earnings_jenehat": 100,
        "star_two": "no_fights",
        "star_three": "no_fights_no_mistakes",
        "student_discount_pct": 50,
        "child_free_age": 6,
        "max_break_requests": 1,
    }
    return Trip.objects.create(line=on, vehicle=by, number=number, **{**defaults, **fields})


def chapter(chapter_id: str = "ch4_salon", order: int = 4) -> Chapter:
    return Chapter.objects.create(
        chapter_id=chapter_id, order=order, title_ar_eg="title", goal_kind="purchase"
    )


def room(room_id: str = "salon", order: int = 1) -> Room:
    return Room.objects.create(room_id=room_id, name_ar_eg="name", chapter=chapter(), order=order)


def item(of: Room, slug: str = "nish", order: int = 1) -> Item:
    return Item.objects.create(room=of, slug=slug, name_ar_eg="name", order=order)


def variant(of: Item, variant_id: str = "crystal", order: int = 1) -> ItemVariant:
    return ItemVariant.objects.create(
        item=of, variant_id=variant_id, name_ar_eg="name", art="nish_crystal", order=order
    )


def speech_line(speech_key: str = "wants.change", order: int = 1) -> SpeechLine:
    pool, _ = SpeechPool.objects.get_or_create(speech_key=speech_key)
    return SpeechLine.objects.create(pool=pool, order=order, text_ar_eg="text")


def published(kind: str, identifier: str, version: int = 3) -> PublishedIdentifier:
    return PublishedIdentifier.objects.create(
        kind=kind, identifier=identifier, first_version=version
    )


def gzip_bytes(version: int) -> bytes:
    return gzip.compress(f'{{"pack_id":"core","version":{version}}}'.encode(), mtime=0)


def sync_channel() -> ContentChannel:
    """Point the `core` channel at its highest published pack, as publish and promote do."""
    channel = ContentChannel.objects.get_or_create(pack_id="core")[0]
    published = ContentPack.objects.filter(pack_id="core", status=Status.PUBLISHED)
    channel.current = published.order_by("-version").first()
    channel.save()
    return channel


def pack(
    version: int, status: str = Status.DRAFT, *, current: bool = True, **fields: Any
) -> ContentPack:
    """A built pack moved through the allowed transitions up to `status`.

    With `current`, the channel then points at the highest published pack, so the deferred
    "one current pack" check that Django's test teardown runs passes.
    """
    with transaction.atomic():  # the "one current pack" check runs at commit
        return _pack(version, status, current=current, **fields)


def _pack(version: int, status: str, *, current: bool, **fields: Any) -> ContentPack:
    data = gzip_bytes(version)
    values: dict[str, Any] = {
        "pack_id": "core",
        "version": version,
        "origin": Origin.BUILT,
        "build_state": BuildState.FINISHED,
        "schema_version": "1.0",
        "min_client_version": "1.0.0",
        "canonical_sha256": "c" * 64,
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
        "file": data,
        "validation_report": {"outcome": "passed"},
    }
    built = ContentPack.objects.create(**{**values, **fields})
    for step in (Status.VALIDATED, Status.PUBLISHED, Status.RETIRED):
        if built.status == status:
            break
        built.status = step
        if step == Status.PUBLISHED:
            built.release_sha256 = "r" * 64
        built.save()
    if current and built.status != Status.DRAFT:
        sync_channel()
    return built


def promoted(version: int, *, current: bool = True) -> ContentPack:
    """A pack as production stores it after a promotion: published from the start."""
    data = gzip_bytes(version)
    with transaction.atomic():
        stored = ContentPack.objects.create(
            pack_id="core",
            version=version,
            origin=Origin.PROMOTED,
            status=Status.PUBLISHED,
            schema_version="1.0",
            min_client_version="1.0.0",
            sha256=hashlib.sha256(data).hexdigest(),
            release_sha256="r" * 64,
            size=len(data),
            file=data,
        )
        if current:
            sync_channel()
    return stored
