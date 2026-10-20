"""Lookups by pack version for B02's sync validators (FR-035, research R12).

The index rows exist only for the last 5 published versions. Publishing or promoting a 6th
retires the oldest: its rows go, and its file and record stay.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from apps.content.models import ContentPack, PackPriceIndex, PackTripIndex
from apps.content.models.packs import Status

KEEP = 5


@dataclass(frozen=True)
class Price:
    currency: str
    amount: int


def index_pack(pack: ContentPack, data: Mapping[str, Any]) -> None:
    """Write the pack's trip and price rows, from the pack exactly as published."""
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


def retire_beyond_five(pack_id: str) -> list[ContentPack]:
    """Retire every published pack older than the newest 5, inside the caller's transaction."""
    published = ContentPack.objects.select_for_update().filter(
        pack_id=pack_id, status=Status.PUBLISHED
    )
    retired = list(published.order_by("-version")[KEEP:])
    for pack in retired:
        pack.status = Status.RETIRED
        pack.save(update_fields=["status", "updated_at"])
        PackTripIndex.objects.filter(pack=pack).delete()
        PackPriceIndex.objects.filter(pack=pack).delete()
    return retired


def catalog_price(version: int, sku_kind: str, sku_id: str) -> Price | None:
    """The price in that pack, or None when the version isn't one of the last 5."""
    row = (
        PackPriceIndex.objects.filter(version=version, sku_kind=sku_kind, sku_id=sku_id)
        .values_list("currency", "amount")
        .first()
    )
    return None if row is None else Price(currency=row[0], amount=row[1])


def trip_definition(version: int, trip_id: str) -> dict[str, Any] | None:
    """The trip exactly as that pack has it, or None when the version isn't one of the last 5."""
    definition = (
        PackTripIndex.objects.filter(version=version, trip_id=trip_id)
        .values_list("definition", flat=True)
        .first()
    )
    return None if definition is None else dict(definition)
