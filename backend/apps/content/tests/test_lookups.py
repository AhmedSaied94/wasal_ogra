"""Lookups by pack version (tasks.md T080, FR-035, research R12)."""

from __future__ import annotations

from pathlib import Path

import pytest

from apps.accounts.models import User
from apps.content.models import CatalogPrice, PackPriceIndex, PackTripIndex, Trip
from apps.content.services import exporter, lookups
from apps.content.tests.test_build import built
from apps.content.tests.test_publish import published

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def _packs(packs_dir: Path) -> Path:
    return packs_dir


@pytest.fixture
def six(sample_reviewed: User, publisher: User) -> list[int]:
    """Six published versions. Each raises the first price by 1, so each version differs."""
    price = CatalogPrice.objects.order_by("sku_kind", "sku_id").first()
    assert price is not None
    amounts = []
    for step in range(6):
        CatalogPrice.objects.filter(pk=price.pk).update(amount=price.amount + step)
        published(built(sample_reviewed), publisher)
        amounts.append(price.amount + step)
    return amounts


def test_prices_come_from_each_of_the_last_five_versions(six: list[int]) -> None:
    price = CatalogPrice.objects.order_by("sku_kind", "sku_id").first()
    assert price is not None

    for version in range(2, 7):
        found = lookups.catalog_price(version, price.sku_kind, price.sku_id)
        assert found == lookups.Price(currency=price.currency, amount=six[version - 1])
    assert lookups.catalog_price(1, price.sku_kind, price.sku_id) is None  # retired
    assert lookups.catalog_price(6, price.sku_kind, "no_such_sku") is None


def test_trip_definitions_come_from_each_of_the_last_five_versions(six: list[int]) -> None:
    trip = Trip.objects.select_related("line").order_by("line__line_id", "number").first()
    assert trip is not None
    trip_id = trip.permanent_identifier()

    for version in range(2, 7):
        definition = lookups.trip_definition(version, trip_id)
        assert definition is not None
        assert definition["trip_id"] == trip_id
    assert lookups.trip_definition(1, trip_id) is None
    assert lookups.trip_definition(6, "line_hay.99") is None


def test_the_index_rows_equal_the_pack_file(sample_reviewed: User, publisher: User) -> None:
    stored = published(built(sample_reviewed), publisher)
    data = exporter.stored_pack(stored)

    trips = {
        row.trip_id: row for row in PackTripIndex.objects.filter(pack=stored).order_by("trip_id")
    }
    assert list(trips) == [trip["trip_id"] for trip in data["trips"]]
    for trip in data["trips"]:
        row = trips[trip["trip_id"]]
        assert row.definition == trip
        assert (row.version, row.rev) == (stored.version, trip["rev"])
        assert row.max_earnings_jenehat == trip["max_earnings_jenehat"]
        assert row.last_station_at_s == trip["stations"][-1]["at_seconds"]
    prices = {
        (row.sku_kind, row.sku_id): (row.currency, row.amount)
        for row in PackPriceIndex.objects.filter(pack=stored)
    }
    assert prices == {
        (p["sku_kind"], p["sku_id"]): (p["currency"], p["amount"])
        for p in data["catalog"]["prices"]
    }
