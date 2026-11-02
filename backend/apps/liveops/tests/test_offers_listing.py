"""The offer listing and the hourly expiry (B10 FR-025 to FR-028)."""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

import pytest
from django.db import IntegrityError, transaction
from django.utils import timezone
from django_celery_beat.models import PeriodicTask

from apps.accounts.models import Player
from apps.accounts.tests.factories import make_player
from apps.liveops import settings as live
from apps.liveops.models import Offer, StoreProduct
from apps.liveops.services import facts, offers
from apps.liveops.tasks import expire_offers

pytestmark = pytest.mark.django_db


def make_offer(
    *,
    offer_id: str | None = None,
    product_id: str = "bonat_pack_s",
    starts_at: Any = None,
    ends_at: Any = None,
    priority: int = 0,
    rules: list[dict[str, Any]] | None = None,
    status: str = "scheduled",
) -> Offer:
    offer = Offer.objects.create(
        offer_id=offer_id or f"offer_{uuid.uuid4().hex[:10]}",
        kind="sale",
        product=StoreProduct.objects.get(product_id=product_id),
        starts_at=starts_at or (timezone.now() - timedelta(days=1)),
        ends_at=ends_at,
        priority=priority,
        rules=rules or [],
        status=status,
    )
    live.refresh_offers()
    return offer


def listed(player: Player, platform: str = "android", now: Any = None) -> list[str]:
    return [offer.offer_id for offer in offers.eligible_offers(player, platform, now=now)]


def test_no_offer_is_seeded() -> None:
    assert not Offer.objects.exists()


def test_the_times_decide_not_the_status() -> None:
    player = make_player()
    now = timezone.now()
    future = make_offer(starts_at=now + timedelta(days=1))
    past = make_offer(starts_at=now - timedelta(days=2), ends_at=now - timedelta(days=1))
    open_ended = make_offer(starts_at=now - timedelta(days=1))
    assert future.offer_id not in listed(player)
    assert past.offer_id not in listed(player)  # gone before the job runs
    assert open_ended.offer_id in listed(player)


def test_the_product_must_be_active_on_the_platform() -> None:
    player = make_player()
    offer = make_offer()
    StoreProduct.objects.filter(product_id="bonat_pack_s").update(active=False)
    live.refresh_products()
    assert listed(player) == []
    StoreProduct.objects.filter(product_id="bonat_pack_s").update(active=True, platforms=["ios"])
    live.refresh_products()
    assert listed(player) == []
    assert listed(player, platform="ios") == [offer.offer_id]


def test_the_owner_of_a_non_consumable_never_sees_its_offer(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    offer = make_offer(product_id="remove_ads")
    player = make_player()
    assert listed(player) == [offer.offer_id]
    real = facts.for_player

    def owning(instance: Player) -> facts.PlayerFacts:
        found = real(instance)
        return facts.PlayerFacts(
            country=found.country,
            installed_at=found.installed_at,
            has_purchase=True,
            entitlements=frozenset({"remove_ads"}),
            chapters=found.chapters,
        )

    monkeypatch.setattr(facts, "for_player", owning)
    assert listed(player) == []


def test_the_order_is_priority_then_start() -> None:
    player = make_player()
    now = timezone.now()
    low = make_offer(priority=0, starts_at=now - timedelta(days=1))
    high = make_offer(priority=5, starts_at=now - timedelta(days=3))
    second = make_offer(priority=5, starts_at=now - timedelta(days=2))
    assert listed(player) == [high.offer_id, second.offer_id, low.offer_id]


def test_the_expiry_job_moves_the_states() -> None:
    now = timezone.now()
    starting = make_offer(starts_at=now - timedelta(minutes=1), status="scheduled")
    ending = make_offer(
        starts_at=now - timedelta(days=1), ends_at=now - timedelta(minutes=1), status="active"
    )
    fresh = make_offer(starts_at=now + timedelta(days=1), status="scheduled")
    result = expire_offers.apply().get()
    assert result == {"started": 1, "expired": 1}
    starting.refresh_from_db()
    ending.refresh_from_db()
    fresh.refresh_from_db()
    assert starting.status == Offer.Status.ACTIVE
    assert ending.status == Offer.Status.EXPIRED
    assert fresh.status == Offer.Status.SCHEDULED


def test_the_end_must_be_after_the_start() -> None:
    now = timezone.now()
    with pytest.raises(IntegrityError), transaction.atomic():
        Offer.objects.create(
            offer_id="bad_range",
            kind="sale",
            product=StoreProduct.objects.get(product_id="bonat_pack_s"),
            starts_at=now,
            ends_at=now,
            rules=[],
            status="scheduled",
        )


def test_the_hourly_schedule_exists() -> None:
    task = PeriodicTask.objects.get(name="liveops.expire_offers")
    assert task.task == "liveops.tasks.expire_offers"
