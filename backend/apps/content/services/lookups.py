"""Lookups by pack version for B03's sync validators (FR-035, research R12; B03 research R2).

The index rows exist only for the last `CONTENT_INDEX_KEEP` published versions (B04 kept 5).
Publishing or promoting one more retires the oldest: its rows go, and its file and record stay.
A version is supported for sync while it is indexed and is either the current one or was
published within `SYNC_CONTENT_MAX_AGE_DAYS`.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from django.conf import settings
from django.utils import timezone

from apps.content.models import (
    ContentChannel,
    ContentPack,
    PackPriceIndex,
    PackRulesIndex,
    PackTripIndex,
)
from apps.content.models.packs import STORED, Status
from apps.content.services.versioning import PACK_ID

# What `supported` answers (B03 contracts/operations.md "Reasons").
SUPPORTED = "supported"
UNKNOWN = "unknown"  # no published pack ever had that number: `unknown_content_version`
UNSUPPORTED = "unsupported"  # retired from the index, or too old: `content_version_unsupported`


@dataclass(frozen=True)
class Price:
    currency: str
    amount: int


@dataclass(frozen=True)
class TripBounds:
    """What a trip start copies from the pack: the bounds its result is checked against."""

    rev: int
    max_earnings_jenehat: int
    last_station_at_s: int


def index_pack(pack: ContentPack, data: Mapping[str, Any]) -> None:
    """Write the pack's trip, price and rules rows, from the pack exactly as published."""
    version = int(data["version"])
    PackTripIndex.objects.bulk_create(
        PackTripIndex(
            pack=pack,
            version=version,
            trip_id=trip["trip_id"],
            rev=trip["rev"],
            definition=trip,
            max_earnings_jenehat=trip["max_earnings_jenehat"],
            last_station_at_s=trip["stations"][-1]["at_seconds"],
        )
        for trip in data["trips"]
    )
    PackPriceIndex.objects.bulk_create(
        PackPriceIndex(
            pack=pack,
            version=version,
            sku_kind=price["sku_kind"],
            sku_id=price["sku_id"],
            currency=price["currency"],
            amount=price["amount"],
        )
        for price in data["catalog"]["prices"]
    )
    PackRulesIndex.objects.create(pack=pack, version=version, rules=rules_document(data))


@dataclass(frozen=True)
class Rebuilt:
    """What `rebuild_index` wrote for one version, and what it holds now."""

    version: int
    trips_written: int
    prices_written: int
    rules_written: bool
    trips: int
    prices: int


def rebuild_index(now: datetime | None = None) -> list[Rebuilt]:
    """Write the missing index rows of every published pack inside the support window, from its
    stored file (B03 research R2, quickstart B1). Packs indexed before B03 have no rules row.
    Idempotent: a second run writes nothing."""
    at = now or timezone.now()
    window = timedelta(days=settings.SYNC_CONTENT_MAX_AGE_DAYS)
    current = current_version()
    packs = ContentPack.objects.filter(pack_id=PACK_ID, status=Status.PUBLISHED).order_by("version")
    results = []
    for pack in packs:
        published = pack.published_at or pack.promoted_at
        if pack.version != current and (published is None or at - published > window):
            continue
        results.append(_rebuild_one(pack))
    return results


def _rebuild_one(pack: ContentPack) -> Rebuilt:
    from apps.content.services.exporter import stored_pack  # the exporter imports the models

    data = stored_pack(pack)
    version = int(data["version"])
    have_trips = set(PackTripIndex.objects.filter(pack=pack).values_list("trip_id", flat=True))
    trips = [
        PackTripIndex(
            pack=pack,
            version=version,
            trip_id=trip["trip_id"],
            rev=trip["rev"],
            definition=trip,
            max_earnings_jenehat=trip["max_earnings_jenehat"],
            last_station_at_s=trip["stations"][-1]["at_seconds"],
        )
        for trip in data["trips"]
        if trip["trip_id"] not in have_trips
    ]
    have_prices = set(PackPriceIndex.objects.filter(pack=pack).values_list("sku_kind", "sku_id"))
    prices = [
        PackPriceIndex(
            pack=pack,
            version=version,
            sku_kind=price["sku_kind"],
            sku_id=price["sku_id"],
            currency=price["currency"],
            amount=price["amount"],
        )
        for price in data["catalog"]["prices"]
        if (price["sku_kind"], price["sku_id"]) not in have_prices
    ]
    PackTripIndex.objects.bulk_create(trips)
    PackPriceIndex.objects.bulk_create(prices)
    _, rules_written = PackRulesIndex.objects.get_or_create(
        version=version, defaults={"pack": pack, "rules": rules_document(data)}
    )
    return Rebuilt(
        version=version,
        trips_written=len(trips),
        prices_written=len(prices),
        rules_written=rules_written,
        trips=len(have_trips) + len(trips),
        prices=len(have_prices) + len(prices),
    )


def rules_document(data: Mapping[str, Any]) -> dict[str, Any]:
    """The rules document of a pack (B03 data-model.md "PackRulesIndex"). Closed: written here and
    read by `progress.services.unlocks` and the operation handlers."""
    trips = sorted(data["trips"], key=_trip_order)
    return {
        "lines": {
            line["line_id"]: {
                "order": line["order"],
                "unlock": dict(line["unlock"]),
                "trips": [t["trip_id"] for t in trips if t["line_id"] == line["line_id"]],
            }
            for line in data["lines"]
        },
        "trips": {
            t["trip_id"]: {
                "line_id": t["line_id"],
                "kind": t["kind"],
                "vehicle_id": t["vehicle_id"],
            }
            for t in trips
        },
        "vehicles": {v["vehicle_id"]: {"starter": v["starter"]} for v in data["vehicles"]},
        "chapters": {
            c["chapter_id"]: {
                "order": c["order"],
                "goal": dict(c["goal"]),
                "completion_bonat": c["completion_bonat"],
                "story_trip_id": c.get("story_trip_id", ""),
                "scenes": [scene["scene_id"] for scene in c["scenes"]],
            }
            for c in data["chapters"]
        },
        "rooms": {
            r["room_id"]: {
                "order": r["order"],
                "chapter_id": r["chapter_id"],
                "completion_bonat": r["completion_bonat"],
                "items": [
                    i["item_id"]
                    for i in sorted(
                        data["items"], key=lambda item: (item["order"], item["item_id"])
                    )
                    if i["room_id"] == r["room_id"]
                ],
            }
            for r in data["rooms"]
        },
        "items": {
            i["item_id"]: {
                "room_id": i["room_id"],
                "variants": [v["variant_id"] for v in i["variants"]],
            }
            for i in data["items"]
        },
        "requests": {
            r["request_id"]: {
                "item_id": r["item_id"],
                "variant_id": r.get("variant_id", ""),
                "reward_bonat": r["reward_bonat"],
            }
            for r in data["family_requests"]
        },
    }


def _trip_order(trip: Mapping[str, Any]) -> tuple[str, int, str]:
    """`line_hay.02` before `line_hay.10`: a trip id is `<line_id>.<nn>` (glossary §3.6)."""
    line, _, number = str(trip["trip_id"]).rpartition(".")
    return (line, int(number) if number.isdigit() else 0, number)


def retire_beyond_keep(pack_id: str) -> list[ContentPack]:
    """Retire every published pack older than the newest `CONTENT_INDEX_KEEP`, inside the
    caller's transaction."""
    published = ContentPack.objects.select_for_update().filter(
        pack_id=pack_id, status=Status.PUBLISHED
    )
    retired = list(published.order_by("-version")[settings.CONTENT_INDEX_KEEP :])
    for pack in retired:
        pack.status = Status.RETIRED
        pack.save(update_fields=["status", "updated_at"])
        PackTripIndex.objects.filter(pack=pack).delete()
        PackPriceIndex.objects.filter(pack=pack).delete()
        PackRulesIndex.objects.filter(pack=pack).delete()
    return retired


def catalog_price(version: int, sku_kind: str, sku_id: str) -> Price | None:
    """The price in that pack, or None when the version isn't indexed."""
    row = (
        PackPriceIndex.objects.filter(version=version, sku_kind=sku_kind, sku_id=sku_id)
        .values_list("currency", "amount")
        .first()
    )
    return None if row is None else Price(currency=row[0], amount=row[1])


def catalog_prices(version: int) -> dict[tuple[str, str], Price]:
    """Every price of that pack by `(sku_kind, sku_id)`, in one query."""
    rows = PackPriceIndex.objects.filter(version=version).values_list(
        "sku_kind", "sku_id", "currency", "amount"
    )
    return {(kind, sku): Price(currency, amount) for kind, sku, currency, amount in rows}


def trip_definition(version: int, trip_id: str) -> dict[str, Any] | None:
    """The trip exactly as that pack has it, or None when the version isn't indexed."""
    definition = (
        PackTripIndex.objects.filter(version=version, trip_id=trip_id)
        .values_list("definition", flat=True)
        .first()
    )
    return None if definition is None else dict(definition)


def trip_bounds(version: int) -> dict[str, TripBounds]:
    """Every trip of that pack's bounds by `trip_id`, in one query (without the definitions)."""
    rows = PackTripIndex.objects.filter(version=version).values_list(
        "trip_id", "rev", "max_earnings_jenehat", "last_station_at_s"
    )
    return {trip_id: TripBounds(rev, earnings, last) for trip_id, rev, earnings, last in rows}


def rules(version: int) -> dict[str, Any] | None:
    """The rules document of that pack, or None when the version isn't indexed."""
    document = (
        PackRulesIndex.objects.filter(version=version).values_list("rules", flat=True).first()
    )
    return None if document is None else dict(document)


def supported(version: int, *, now: datetime | None = None) -> str:
    """`SUPPORTED`, `UNKNOWN` (never published) or `UNSUPPORTED` (retired from the index, older
    than `SYNC_CONTENT_MAX_AGE_DAYS`, or indexed before B03 and not rebuilt)."""
    pack = (
        ContentPack.objects.filter(pack_id=PACK_ID, version=version, status__in=sorted(STORED))
        .values("published_at", "promoted_at")
        .first()
    )
    if pack is None:
        return UNKNOWN
    if not PackRulesIndex.objects.filter(version=version).exists():
        return UNSUPPORTED
    current = (
        ContentChannel.objects.filter(pack_id=PACK_ID)
        .values_list("current__version", flat=True)
        .first()
    )
    if current == version:
        return SUPPORTED
    published = pack["published_at"] or pack["promoted_at"]
    window = timedelta(days=settings.SYNC_CONTENT_MAX_AGE_DAYS)
    if published is not None and (now or timezone.now()) - published <= window:
        return SUPPORTED
    return UNSUPPORTED


def current_version() -> int | None:
    """The current published version of the `core` pack, as the manifest names it."""
    version: int | None = (
        ContentChannel.objects.filter(pack_id=PACK_ID)
        .values_list("current__version", flat=True)
        .first()
    )
    return version
