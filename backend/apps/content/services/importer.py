"""Import a `content/source` layout (contracts/content-source.md "Import rules", FR-015).

The import is all or nothing. Every file is checked against its schema, the assembled pack runs
through stages 1-3, and only then is anything written, in one transaction. A permanence conflict,
a protected reference or a clashing order refuses the whole import with a report naming the file.
"""

from __future__ import annotations

import io
import stat
import zipfile
import zlib
from collections import defaultdict
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field, replace
from pathlib import Path, PurePosixPath
from typing import Any

from django.contrib.admin.models import ADDITION, CHANGE, LogEntry
from django.db import IntegrityError, models, transaction
from django.db.models import F, ProtectedError
from wassal_content.findings import Finding
from wassal_content.source import SourceTree, assemble_pack, read_files, read_layout
from wassal_content.validate import validate_pack

from apps.accounts.models import User
from apps.content.errors import PermanenceError
from apps.content.models import (
    CatalogPrice,
    Chapter,
    ContentChannel,
    DailyRewardDay,
    FamilyRequest,
    Item,
    ItemVariant,
    Line,
    Room,
    Scene,
    SceneLine,
    Seat,
    SpeechLine,
    SpeechPool,
    Station,
    TaskTemplate,
    Trip,
    TripEvent,
    TripPassenger,
    TripStation,
    Vehicle,
)
from apps.content.services import permissions, snapshot

MiB = 1024 * 1024
MAX_UPLOAD = 4 * MiB
MAX_ENTRIES = 2000
MAX_TOTAL = 8 * MiB
MAX_ENTRY = 1 * MiB
# Orders are unique per parent. Moving the stored ones out of the way first lets an import swap
# them. Content orders are small, so this stays inside a smallint.
ORDER_OFFSET = 10_000
IMPORT_MESSAGE = "Imported from a content/source layout."


class ImportRefused(Exception):
    """The import changed nothing. `findings` name each file, path and problem."""

    def __init__(self, findings: list[Finding]) -> None:
        self.findings = findings
        super().__init__(f"the import was refused with {len(findings)} problem(s)")


@dataclass
class ImportResult:
    added: list[str] = field(default_factory=list)
    changed: list[str] = field(default_factory=list)
    unchanged: int = 0


# -- entry points ----------------------------------------------------------------------------------


def import_zip(data: bytes, actor: User | None) -> ImportResult:
    """Import an uploaded zip, after its size, entry and path checks."""
    user = _require(actor)
    tree, findings = read_files(read_zip(data))
    if findings:
        raise ImportRefused(findings)
    return _apply_tree(tree, user)


def import_dir(path: Path, actor: User | None) -> ImportResult:
    """Import a layout directory, as `content_import` does."""
    user = _require(actor)
    tree, findings = read_layout(path)
    if findings:
        raise ImportRefused(findings)
    return _apply_tree(tree, user)


def _require(actor: User | None) -> User:
    user = permissions.require(actor, "content.import_content")
    permissions.require_role(permissions.SOURCE)
    return user


# -- the zip ---------------------------------------------------------------------------------------


def _zip_problem(message: str, entry: str = "") -> ImportRefused:
    return ImportRefused([Finding(path="$", code="V-ZP", message=message, file=entry or None)])


def read_zip(data: bytes) -> dict[str, bytes]:
    """The zip's files by relative path, refusing anything outside the import limits."""
    if len(data) > MAX_UPLOAD:
        raise _zip_problem(f"the upload is over {MAX_UPLOAD // MiB} MiB")
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        raise _zip_problem("the upload is not a zip file") from None
    with archive:
        entries = archive.infolist()
        if len(entries) > MAX_ENTRIES:
            raise _zip_problem(f"the zip has more than {MAX_ENTRIES} entries")
        if sum(entry.file_size for entry in entries) > MAX_TOTAL:
            raise _zip_problem(f"the zip holds more than {MAX_TOTAL // MiB} MiB uncompressed")
        files: dict[str, bytes] = {}
        total = 0
        for entry in entries:
            name = _entry_name(entry)
            if name is None:
                continue
            if entry.file_size > MAX_ENTRY:
                raise _zip_problem(f"the entry is over {MAX_ENTRY // MiB} MiB", entry.filename)
            if name in files:
                raise _zip_problem("the zip has two entries with this name", entry.filename)
            try:
                with archive.open(entry) as handle:
                    content = handle.read(MAX_ENTRY + 1)
            except (zipfile.BadZipFile, zlib.error, EOFError, NotImplementedError, RuntimeError):
                # Corrupt data, an encrypted entry or a compression method zipfile lacks.
                raise _zip_problem("the entry can't be read", entry.filename) from None
            total += len(content)
            if len(content) > MAX_ENTRY or total > MAX_TOTAL:
                raise _zip_problem("the entry is larger than the zip says", entry.filename)
            files[name] = content
    return _strip_wrapper(files)


def _entry_name(entry: zipfile.ZipInfo) -> str | None:
    """The entry's layout path, `None` for a directory entry, or a refusal."""
    name = entry.filename
    mode = entry.external_attr >> 16
    if "\\" in name:
        raise _zip_problem("backslashes are not allowed in paths", name)
    if name.startswith("/") or PurePosixPath(name).is_absolute():
        raise _zip_problem("absolute paths are not allowed", name)
    if any(part == ".." for part in PurePosixPath(name).parts):
        raise _zip_problem("'..' is not allowed in paths", name)
    if stat.S_ISLNK(mode):
        raise _zip_problem("symlinks are not allowed", name)
    if entry.is_dir():
        return None
    return name


def _strip_wrapper(files: dict[str, bytes]) -> dict[str, bytes]:
    """Accept a zip of the layout's folder: `sample/pack.json` and so on."""
    if "pack.json" in files or not files:
        return files
    tops = {PurePosixPath(name).parts[0] for name in files}
    if len(tops) != 1 or not all(len(PurePosixPath(name).parts) > 1 for name in files):
        return files
    (top,) = tops
    return {name.removeprefix(f"{top}/"): content for name, content in files.items()}


# -- validation ------------------------------------------------------------------------------------


def layout_file(entity: str, identifier: str) -> str:
    """The layout file holding a finding's record, so the report can name it."""
    folders = {
        "line": "lines",
        "vehicle": "vehicles",
        "chapter": "chapters",
        "room": "rooms",
        "item": "items",
        "family_request": "family_requests",
        "speech_pool": "speech",
    }
    if entity in folders:
        return f"{folders[entity]}/{identifier}.json"
    if entity == "trip":
        return f"trips/{identifier.rsplit('.', 1)[0]}/{identifier}.json"
    return {
        "catalog_price": "catalog.json",
        "daily_reward": "daily_rewards.json",
        "task": "tasks.json",
    }.get(entity, "pack.json")


def _apply_tree(tree: SourceTree, actor: User) -> ImportResult:
    if tree.meta is None:
        raise ImportRefused([Finding(path="$", code="V-LY", message="the layout is empty")])
    # An export of unpublished content says version 0, which no pack has (as validate-source).
    pack = assemble_pack(tree, max(int(tree.meta["version"]), 1))
    report = validate_pack(pack, file_size=None)
    if report.errors:
        raise ImportRefused(
            [replace(f, file=f.file or layout_file(f.entity, f.id)) for f in report.errors]
        )
    try:
        with transaction.atomic():
            result = _Applier(pack, actor).run()
            channel = ContentChannel.objects.select_for_update().get_or_create(pack_id="core")[0]
            if int(tree.meta["version"]) > channel.imported_version:
                channel.imported_version = int(tree.meta["version"])
                channel.save(update_fields=["imported_version", "updated_at"])
    except PermanenceError as error:
        raise ImportRefused([Finding(path="$", code="V-PM", message=error.messages[0])]) from None
    except ProtectedError as error:
        names = ", ".join(sorted({str(obj) for obj in error.protected_objects})[:5])
        message = f"the import would delete rows still in use by {names}"
        raise ImportRefused([Finding(path="$", code="V-PR", message=message)]) from None
    except IntegrityError as error:
        message = f"the import clashes with content it leaves alone: {_constraint(error)}"
        raise ImportRefused([Finding(path="$", code="V-DB", message=message)]) from None
    return result


def _constraint(error: IntegrityError) -> str:
    diag = getattr(error.__cause__, "diag", None)
    return str(getattr(diag, "constraint_name", None) or "a database constraint")


# -- applying --------------------------------------------------------------------------------------


def _text(value: Mapping[str, str]) -> tuple[str, str]:
    return value["ar-EG"], value.get("ar", "")


def _bump(queryset: models.QuerySet[Any]) -> None:
    queryset.update(order=F("order") + ORDER_OFFSET)


class _Applier:
    """Writes one validated pack. Unchanged entities are left untouched, reviews included."""

    def __init__(self, pack: Mapping[str, Any], actor: User) -> None:
        self.pack = pack
        self.actor = actor
        self.result = ImportResult()
        self.logged: dict[int, list[models.Model]] = defaultdict(list)
        self.lines: dict[str, Line] = {line.line_id: line for line in snapshot.lines()}
        self.vehicles: dict[str, Vehicle] = {v.vehicle_id: v for v in snapshot.vehicles()}
        self.rooms: dict[str, Room] = {room.room_id: room for room in snapshot.rooms()}
        self.chapters: dict[str, Chapter] = {c.chapter_id: c for c in snapshot.chapters()}
        self.items: dict[str, Item] = {item.item_id: item for item in snapshot.items()}
        self.trips: dict[str, Trip] = {trip.trip_id: trip for trip in snapshot.trips()}
        self.dropped: list[models.Model] = []
        self.pending_unlocks: list[tuple[Line, Mapping[str, Any]]] = []
        self.pending_goals: list[tuple[Chapter, Mapping[str, Any]]] = []
        self.pending_plays: list[tuple[Scene, Mapping[str, Any] | None]] = []

    def run(self) -> ImportResult:
        self.each(
            "vehicles", self.vehicles, snapshot.vehicle_part, self.vehicle, unique_order=Vehicle
        )
        self.each("lines", self.lines, snapshot.line_part, self.line, unique_order=Line)
        self.each(
            "chapters", self.chapters, snapshot.chapter_part, self.chapter, unique_order=Chapter
        )
        self.each("rooms", self.rooms, snapshot.room_part, self.room, unique_order=Room)
        self.each("items", self.items, snapshot.item_part, self.item)
        self.each("trips", self.trips, snapshot.trip_part, self.trip)
        for line, part in self.pending_unlocks:
            self.unlock(line, part)
        for chapter, part in self.pending_goals:
            self.goal(chapter, part)
        for scene, plays in self.pending_plays:
            self.plays(scene, plays)
        requests = {r.request_id: r for r in snapshot.requests()}
        self.each("family_requests", requests, snapshot.request_part, self.request)
        pools = {pool.speech_key: pool for pool in snapshot.pools()}
        self.each("speech_pools", pools, snapshot.pool_part, self.pool)
        prices = {(p.sku_kind, p.sku_id): p for p in CatalogPrice.objects.all()}
        self.each_keyed(
            self.pack["catalog"]["prices"],
            lambda p: (p["sku_kind"], p["sku_id"]),
            prices,
            snapshot.price_part,
            self.price,
        )
        days = {day.day_index: day for day in DailyRewardDay.objects.all()}
        self.each_keyed(
            self.pack["daily_rewards"], lambda d: d["day_index"], days, snapshot.day_part, self.day
        )
        tasks = {task.task_id: task for task in TaskTemplate.objects.all()}
        self.each_keyed(
            self.pack["tasks"], lambda t: t["task_id"], tasks, self.task_part, self.task
        )
        for row in reversed(self.dropped):
            row.delete()
        self.log()
        return self.result

    # -- bookkeeping ---------------------------------------------------------------------------

    def each(
        self,
        array: str,
        stored: Mapping[str, Any],
        serialize: Callable[[Any], dict[str, Any]],
        write: Callable[[Any, Mapping[str, Any]], Any],
        *,
        unique_order: type[models.Model] | None = None,
    ) -> None:
        key_field = {
            "lines": "line_id",
            "vehicles": "vehicle_id",
            "trips": "trip_id",
            "chapters": "chapter_id",
            "rooms": "room_id",
            "items": "item_id",
            "family_requests": "request_id",
            "speech_pools": "speech_key",
        }[array]
        self.each_keyed(
            self.pack[array],
            lambda e: e[key_field],
            stored,
            serialize,
            write,
            unique_order=unique_order,
        )

    def each_keyed(
        self,
        elements: Iterable[Mapping[str, Any]],
        key: Callable[[Mapping[str, Any]], Any],
        stored: Mapping[Any, Any],
        serialize: Callable[[Any], dict[str, Any] | None],
        write: Callable[[Any, Mapping[str, Any]], Any],
        *,
        unique_order: type[models.Model] | None = None,
    ) -> None:
        changes = []
        for element in elements:
            existing = stored.get(key(element))
            if existing is not None and serialize(existing) == element:
                self.result.unchanged += 1
            else:
                changes.append((existing, element))
        if unique_order is not None:
            # Out of the way first, so two rows can swap orders.
            _bump(unique_order._default_manager.filter(pk__in=[e.pk for e, _ in changes if e]))
        for existing, element in changes:
            obj = write(existing, element)
            label = f"{type(obj)._meta.model_name} {key(element)}"
            if existing is None:
                self.result.added.append(label)
                self.logged[ADDITION].append(obj)
            else:
                self.result.changed.append(label)
                self.logged[CHANGE].append(obj)

    def log(self) -> None:
        for flag, objects in self.logged.items():
            by_model: dict[type[models.Model], list[models.Model]] = defaultdict(list)
            for obj in objects:
                by_model[type(obj)].append(obj)
            for group in by_model.values():
                LogEntry.objects.log_actions(
                    user_id=self.actor.pk,
                    queryset=group,
                    action_flag=flag,
                    change_message=IMPORT_MESSAGE,
                )

    def task_part(self, task: TaskTemplate) -> dict[str, Any] | None:
        # An inactive template isn't in packs, so importing it makes it active again.
        return snapshot.task_part(task) if task.active else None

    # -- writers -------------------------------------------------------------------------------

    def vehicle(self, vehicle: Vehicle | None, part: Mapping[str, Any]) -> Vehicle:
        name_ar_eg, name_ar = _text(part["name"])
        vehicle = vehicle or Vehicle(vehicle_id=part["vehicle_id"])
        vehicle.name_ar_eg, vehicle.name_ar = name_ar_eg, name_ar
        vehicle.starter, vehicle.order = part["starter"], part["order"]
        vehicle.save()
        stored = {seat.seat_id: seat for seat in Seat.objects.filter(vehicle=vehicle)}
        wanted = {seat["seat_id"] for seat in part["seats"]}
        for seat_id in sorted(wanted - set(stored)):
            Seat.objects.create(vehicle=vehicle, seat_id=seat_id)
        self.dropped += [stored[seat_id] for seat_id in sorted(set(stored) - wanted)]
        self.vehicles[vehicle.vehicle_id] = vehicle
        return vehicle

    def line(self, line: Line | None, part: Mapping[str, Any]) -> Line:
        line = line or Line(line_id=part["line_id"], unlock_kind="start")
        line.name_ar_eg, line.name_ar = _text(part["name"])
        line.order = part["order"]
        line.difficulty_min = part["difficulty_band"]["min"]
        line.difficulty_max = part["difficulty_band"]["max"]
        line.save()
        stored = {station.station_id: station for station in Station.objects.filter(line=line)}
        _bump(Station.objects.filter(line=line))
        for order, station_part in enumerate(part["stations"], start=1):
            station = stored.get(station_part["station_id"]) or Station(
                line=line, station_id=station_part["station_id"]
            )
            station.name_ar_eg, station.name_ar = _text(station_part["name"])
            station.order = order
            station.save()
        wanted = {station["station_id"] for station in part["stations"]}
        self.dropped += [stored[sid] for sid in sorted(set(stored) - wanted)]
        self.lines[line.line_id] = line
        self.pending_unlocks.append((line, part["unlock"]))
        return line

    def unlock(self, line: Line, unlock: Mapping[str, Any]) -> None:
        line.unlock_kind = unlock["kind"]
        line.unlock_vehicle = (
            self.vehicles[unlock["vehicle_id"]] if "vehicle_id" in unlock else None
        )
        line.unlock_after_line = self.lines[unlock["line_id"]] if "line_id" in unlock else None
        line.save()

    def chapter(self, chapter: Chapter | None, part: Mapping[str, Any]) -> Chapter:
        chapter = chapter or Chapter(chapter_id=part["chapter_id"], goal_kind="purchase")
        chapter.order = part["order"]
        chapter.title_ar_eg, chapter.title_ar = _text(part["title"])
        chapter.completion_bonat = part["completion_bonat"]
        chapter.save()
        stored = {scene.scene_id: scene for scene in Scene.objects.filter(chapter=chapter)}
        _bump(Scene.objects.filter(chapter=chapter))
        for order, scene_part in enumerate(part["scenes"], start=1):
            scene = stored.get(scene_part["scene_id"]) or Scene(
                chapter=chapter, scene_id=scene_part["scene_id"]
            )
            scene.order = order
            scene.panel_art = [panel["art"] for panel in scene_part["panels"]]
            scene.save()
            # After the trips: an after_trip scene may name a trip this import adds.
            self.pending_plays.append((scene, scene_part.get("plays")))
            SceneLine.objects.filter(scene=scene).delete()
            SceneLine.objects.bulk_create(
                SceneLine(
                    scene=scene,
                    panel=number,
                    order=position,
                    speaker=line["speaker"],
                    text_ar_eg=_text(line["text"])[0],
                    text_ar=_text(line["text"])[1],
                )
                for number, panel in enumerate(scene_part["panels"], start=1)
                for position, line in enumerate(panel["lines"], start=1)
            )
        wanted = {scene["scene_id"] for scene in part["scenes"]}
        self.dropped += [stored[sid] for sid in sorted(set(stored) - wanted)]
        self.chapters[chapter.chapter_id] = chapter
        self.pending_goals.append((chapter, part))
        return chapter

    def goal(self, chapter: Chapter, part: Mapping[str, Any]) -> None:
        goal = part["goal"]
        chapter.goal_kind = goal["kind"]
        chapter.goal_line = self.lines[goal["line_id"]] if "line_id" in goal else None
        chapter.goal_vehicle = self.vehicles[goal["vehicle_id"]] if "vehicle_id" in goal else None
        chapter.goal_room = self.rooms[goal["room_id"]] if "room_id" in goal else None
        story = part.get("story_trip_id")
        chapter.story_trip = self.trips[story] if story else None
        chapter.save()

    def plays(self, scene: Scene, plays: Mapping[str, Any] | None) -> None:
        """When the scene plays by itself, its trip resolved like `story_trip_id`."""
        trip_id = (plays or {}).get("trip_id")
        scene.plays_kind = (plays or {}).get("kind", "")
        scene.plays_trip = self.trips[trip_id] if trip_id else None
        scene.save(update_fields=["plays_kind", "plays_trip", "updated_at"])

    def room(self, room: Room | None, part: Mapping[str, Any]) -> Room:
        room = room or Room(room_id=part["room_id"])
        room.name_ar_eg, room.name_ar = _text(part["name"])
        room.order = part["order"]
        room.chapter = self.chapters[part["chapter_id"]]
        room.completion_bonat = part["completion_bonat"]
        room.save()
        self.rooms[room.room_id] = room
        return room

    def item(self, item: Item | None, part: Mapping[str, Any]) -> Item:
        if item is None:
            slug = part["item_id"].removeprefix(f"{part['room_id']}.")
            item = Item(room=self.rooms[part["room_id"]], slug=slug)
        item.name_ar_eg, item.name_ar = _text(part["name"])
        item.order = part["order"]
        item.save()
        stored = {v.variant_id: v for v in ItemVariant.objects.filter(item=item)}
        for order, variant_part in enumerate(part["variants"], start=1):
            variant = stored.get(variant_part["variant_id"]) or ItemVariant(
                item=item, variant_id=variant_part["variant_id"]
            )
            variant.name_ar_eg, variant.name_ar = _text(variant_part["name"])
            variant.art, variant.order = variant_part["art"], order
            variant.save()
        wanted = {variant["variant_id"] for variant in part["variants"]}
        self.dropped += [stored[vid] for vid in sorted(set(stored) - wanted)]
        self.items[item.item_id] = item
        return item

    def trip(self, trip: Trip | None, part: Mapping[str, Any]) -> Trip:
        line = self.lines[part["line_id"]]
        if trip is None:
            trip = Trip(line=line, number=int(part["trip_id"].rsplit(".", 1)[1]))
        rules, stars = part["rules"], part["star_rules"]
        trip.vehicle = self.vehicles[part["vehicle_id"]]
        trip.kind, trip.seed, trip.rev = part["kind"], part["seed"], part["rev"]
        trip.max_earnings_jenehat = part["max_earnings_jenehat"]
        trip.star_two, trip.star_three = stars["two"], stars["three"]
        trip.student_discount_pct = rules["student_discount_pct"]
        trip.bag_fare_piasters = rules["bag_fare_piasters"]
        trip.child_free_age = rules["child_free_age"]
        trip.max_break_requests = rules["max_break_requests"]
        trip.no_fights_required = rules["no_fights_required"]
        for key in snapshot.DENOMINATIONS:
            setattr(trip, f"tray_{key}", part["initial_tray"].get(key, 0))
        trip.save()
        stations = {s.station_id: s for s in Station.objects.filter(line=line)}
        seats = {s.seat_id: s for s in Seat.objects.filter(vehicle=trip.vehicle)}
        TripStation.objects.filter(trip=trip).delete()
        TripPassenger.objects.filter(trip=trip).delete()
        TripEvent.objects.filter(trip=trip).delete()
        TripStation.objects.bulk_create(
            TripStation(
                trip=trip,
                station=stations[stop["station_id"]],
                at_seconds=stop["at_seconds"],
                fare_piasters=stop["fare_piasters"],
            )
            for stop in part["stations"]
        )
        TripPassenger.objects.bulk_create(
            TripPassenger(
                trip=trip,
                order=order,
                passenger_id=p["passenger_id"],
                archetype=p["archetype"],
                skin=p["skin"],
                seat=seats[p["seat_id"]],
                board_station=stations[p["board_station_id"]] if "board_station_id" in p else None,
                dest_station=stations[p["dest_station_id"]],
                pays_at_seconds=p.get("pays_at_seconds"),
                payment=list(p["payment"]),
                group_id=p.get("group_id", ""),
                group_size=p.get("group_size"),
                speech_keys=dict(p["speech_keys"]) if "speech_keys" in p else None,
            )
            for order, p in enumerate(part["passengers"], start=1)
        )
        TripEvent.objects.bulk_create(
            TripEvent(
                trip=trip,
                order=order,
                event_id=e["event_id"],
                at_seconds=e["at_seconds"],
                passenger_ids=list(e.get("passenger_ids", [])),
                station_id=e.get("station_id", ""),
                amount_piasters=e.get("amount_piasters"),
                seconds=e.get("seconds"),
            )
            for order, e in enumerate(part["events"], start=1)
        )
        self.trips[part["trip_id"]] = trip
        return trip

    def request(self, request: FamilyRequest | None, part: Mapping[str, Any]) -> FamilyRequest:
        request = request or FamilyRequest(request_id=part["request_id"])
        request.room = self.rooms[part["room_id"]]
        request.item = self.items[part["item_id"]]
        variant = part.get("variant_id")
        request.variant = (
            ItemVariant.objects.get(item=request.item, variant_id=variant) if variant else None
        )
        request.text_ar_eg, request.text_ar = _text(part["text"])
        request.reward_bonat = part["reward_bonat"]
        request.save()
        return request

    def pool(self, pool: SpeechPool | None, part: Mapping[str, Any]) -> SpeechPool:
        pool = pool or SpeechPool.objects.create(speech_key=part["speech_key"])
        # A line whose text is unchanged keeps its review (FR-017).
        reviews: dict[tuple[str, str], list[tuple[str, Any]]] = defaultdict(list)
        for line in SpeechLine.objects.filter(pool=pool).order_by("order"):
            if line.is_reviewed:
                reviews[(line.text_ar_eg, line.text_ar)].append(
                    (line.reviewed_by, line.reviewed_at)
                )
        SpeechLine.objects.filter(pool=pool).delete()
        new_lines = []
        for order, line_part in enumerate(part["lines"], start=1):
            texts = _text(line_part["text"])
            reviewed_by, reviewed_at = reviews[texts].pop(0) if reviews[texts] else ("", None)
            new_lines.append(
                SpeechLine(
                    pool=pool,
                    order=order,
                    text_ar_eg=texts[0],
                    text_ar=texts[1],
                    reviewed_by=reviewed_by,
                    reviewed_at=reviewed_at,
                )
            )
        SpeechLine.objects.bulk_create(new_lines)
        return pool

    def price(self, price: CatalogPrice | None, part: Mapping[str, Any]) -> CatalogPrice:
        price = price or CatalogPrice(sku_kind=part["sku_kind"], sku_id=part["sku_id"])
        price.currency, price.amount = part["currency"], part["amount"]
        price.save()
        return price

    def day(self, day: DailyRewardDay | None, part: Mapping[str, Any]) -> DailyRewardDay:
        day = day or DailyRewardDay(day_index=part["day_index"])
        day.jenehat, day.bonat = part["jenehat"], part["bonat"]
        day.save()
        return day

    def task(self, task: TaskTemplate | None, part: Mapping[str, Any]) -> TaskTemplate:
        task = task or TaskTemplate(task_id=part["task_id"])
        task.metric, task.target = part["metric"], part["target"]
        task.text_ar_eg, task.text_ar = _text(part["text"])
        task.reward_jenehat, task.reward_bonat = part["reward_jenehat"], part["reward_bonat"]
        task.active = True
        task.save()
        return task
