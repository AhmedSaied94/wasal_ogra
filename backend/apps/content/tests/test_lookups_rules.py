"""The rules document, the support window and the kept versions (B03 tasks.md T013, research R2)."""

from __future__ import annotations

from datetime import timedelta
from io import StringIO
from pathlib import Path

import pytest
import time_machine
from django.core.management import call_command
from django.utils import timezone
from pytest_django import Settings

from apps.accounts.models import User
from apps.content.models import ContentPack, PackPriceIndex, PackRulesIndex, PackTripIndex
from apps.content.services import exporter, lookups
from apps.content.tests.test_build import built
from apps.content.tests.test_publish import published

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def _packs(packs_dir: Path) -> Path:
    return packs_dir


def test_index_pack_writes_one_rules_row_equal_to_the_pack(
    sample_reviewed: User, publisher: User
) -> None:
    stored = published(built(sample_reviewed), publisher)
    data = exporter.stored_pack(stored)

    [row] = PackRulesIndex.objects.filter(pack=stored)
    assert row.version == stored.version
    assert row.rules == lookups.rules_document(data)
    assert lookups.rules(stored.version or 0) == row.rules
    rules = row.rules
    assert rules["lines"]["line_hay"] == {
        "order": 1,
        "unlock": {"kind": "start"},
        "trips": ["line_hay.01", "line_hay.02", "line_hay.03"],
    }
    assert rules["lines"]["line_gamaa"]["unlock"] == {"kind": "vehicle", "vehicle_id": "micro_old"}
    assert rules["trips"]["line_hay.03"] == {
        "line_id": "line_hay",
        "kind": "story",
        "vehicle_id": "tuktuk",
    }
    assert rules["vehicles"] == {"tuktuk": {"starter": True}, "micro_old": {"starter": False}}
    assert rules["chapters"]["ch1_first_job"] == {
        "order": 1,
        "goal": {"kind": "complete_line", "line_id": "line_hay"},
        "completion_bonat": 5,
        "story_trip_id": "line_hay.03",
        "scenes": ["opening", "the_stand"],
    }
    assert rules["chapters"]["ch3_shabka"]["story_trip_id"] == ""
    assert rules["rooms"]["salon"] == {
        "order": 1,
        "chapter_id": "ch4_salon",
        "completion_bonat": 20,
        "items": ["salon.nish", "salon.sitara"],
    }
    assert rules["items"]["salon.nish"] == {
        "room_id": "salon",
        "variants": ["classic", "crystal", "modern"],
    }
    assert rules["requests"] == {
        "req_nish_crystal": {"item_id": "salon.nish", "variant_id": "crystal", "reward_bonat": 5}
    }
    # Every trip of every line is listed once, in the trip index too.
    listed = [t for line in rules["lines"].values() for t in line["trips"]]
    assert sorted(listed) == sorted(rules["trips"]) == sorted(t["trip_id"] for t in data["trips"])


def test_rules_and_bounds_are_none_or_empty_for_an_unindexed_version(db: None) -> None:
    assert lookups.rules(99) is None
    assert lookups.trip_bounds(99) == {}
    assert lookups.catalog_prices(99) == {}


def test_trip_bounds_and_prices_come_from_the_index(sample_reviewed: User, publisher: User) -> None:
    stored = published(built(sample_reviewed), publisher)
    version = stored.version or 0
    bounds = lookups.trip_bounds(version)
    row = PackTripIndex.objects.get(version=version, trip_id="line_hay.01")
    assert bounds["line_hay.01"] == lookups.TripBounds(
        row.rev, row.max_earnings_jenehat, row.last_station_at_s
    )
    prices = lookups.catalog_prices(version)
    assert prices[("item", "salon.nish")] == lookups.Price("JENEHAT", 400)
    assert len(prices) == PackPriceIndex.objects.filter(version=version).count()


def test_supported_distinguishes_unknown_unsupported_and_supported(
    sample_reviewed: User, publisher: User, settings: Settings
) -> None:
    settings.SYNC_CONTENT_MAX_AGE_DAYS = 45
    first = published(built(sample_reviewed), publisher)
    assert lookups.supported(first.version or 0) == lookups.SUPPORTED  # the current one
    assert lookups.supported(99) == lookups.UNKNOWN  # never published

    later = timezone.now() + timedelta(days=60)
    with time_machine.travel(later, tick=False):
        second = published(built(sample_reviewed), publisher)
        # The first is older than the window and no longer current.
        assert lookups.supported(first.version or 0) == lookups.UNSUPPORTED
        assert lookups.supported(second.version or 0) == lookups.SUPPORTED
    with time_machine.travel(later + timedelta(days=46), tick=False):
        # The current version stays supported, however old.
        assert lookups.supported(second.version or 0) == lookups.SUPPORTED
    with time_machine.travel(later + timedelta(days=10), tick=False):
        third = published(built(sample_reviewed), publisher)
        # Not current, but published within the window.
        assert lookups.supported(second.version or 0) == lookups.SUPPORTED
        assert lookups.current_version() == third.version


def test_a_version_without_rules_rows_is_unsupported(
    sample_reviewed: User, publisher: User
) -> None:
    stored = published(built(sample_reviewed), publisher)
    PackRulesIndex.objects.filter(pack=stored).delete()  # as packs indexed before B03
    assert lookups.supported(stored.version or 0) == lookups.UNSUPPORTED


def test_the_kept_versions_follow_the_setting(
    sample_reviewed: User, publisher: User, settings: Settings
) -> None:
    settings.CONTENT_INDEX_KEEP = 10
    for _ in range(6):
        published(built(sample_reviewed), publisher)
    assert sorted(set(PackRulesIndex.objects.values_list("version", flat=True))) == [
        1,
        2,
        3,
        4,
        5,
        6,
    ]

    settings.CONTENT_INDEX_KEEP = 5
    published(built(sample_reviewed), publisher)
    kept = [3, 4, 5, 6, 7]
    assert sorted(set(PackRulesIndex.objects.values_list("version", flat=True))) == kept
    assert sorted(set(PackTripIndex.objects.values_list("version", flat=True))) == kept
    assert sorted(set(PackPriceIndex.objects.values_list("version", flat=True))) == kept
    assert lookups.supported(1) == lookups.UNSUPPORTED


def test_content_index_rebuild_writes_the_missing_rows_once(
    sample_reviewed: User, publisher: User
) -> None:
    packs = [published(built(sample_reviewed), publisher) for _ in range(2)]
    PackRulesIndex.objects.all().delete()
    PackTripIndex.objects.filter(pack=packs[0]).delete()
    expected_trips = PackTripIndex.objects.filter(pack=packs[1]).count()

    out = StringIO()
    call_command("content_index", "--rebuild", stdout=out)
    text = out.getvalue()
    assert "version 1:" in text
    assert "version 2:" in text
    assert PackRulesIndex.objects.count() == 2
    assert PackTripIndex.objects.filter(pack=packs[0]).count() == expected_trips
    for pack in packs:
        data = exporter.stored_pack(pack)
        assert PackRulesIndex.objects.get(pack=pack).rules == lookups.rules_document(data)

    before = {
        model.__name__: sorted(model.objects.values_list("id", flat=True))
        for model in (PackRulesIndex, PackTripIndex, PackPriceIndex)
    }
    call_command("content_index", "--rebuild", stdout=StringIO())
    after = {
        model.__name__: sorted(model.objects.values_list("id", flat=True))
        for model in (PackRulesIndex, PackTripIndex, PackPriceIndex)
    }
    assert after == before


def test_content_index_rebuild_skips_versions_outside_the_window(
    sample_reviewed: User, publisher: User, settings: Settings
) -> None:
    settings.SYNC_CONTENT_MAX_AGE_DAYS = 45
    old = published(built(sample_reviewed), publisher)
    with time_machine.travel(timezone.now() + timedelta(days=60), tick=False):
        published(built(sample_reviewed), publisher)
        PackRulesIndex.objects.all().delete()
        out = StringIO()
        call_command("content_index", "--rebuild", stdout=out)
    assert not PackRulesIndex.objects.filter(pack=old).exists()
    assert PackRulesIndex.objects.count() == 1
    assert "version 1" not in out.getvalue()


def test_content_index_needs_rebuild(db: None) -> None:
    from django.core.management import CommandError

    with pytest.raises(CommandError, match="--rebuild"):
        call_command("content_index", stdout=StringIO())
    assert ContentPack.objects.count() == 0
