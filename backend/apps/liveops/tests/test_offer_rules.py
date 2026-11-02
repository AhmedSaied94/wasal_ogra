"""The offer rule kinds: one player who meets each, one who doesn't (B10 contracts/offers.md)."""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

import pytest
from django.utils import timezone

from apps.accounts.models import Player
from apps.accounts.tests.factories import make_player
from apps.liveops import settings as live
from apps.liveops.models import Offer, StoreProduct
from apps.liveops.services import facts, offers

pytestmark = pytest.mark.django_db


def make_offer(rules: list[dict[str, Any]], product_id: str = "bonat_pack_s") -> Offer:
    offer = Offer.objects.create(
        offer_id=f"offer_{uuid.uuid4().hex[:10]}",
        kind="sale",
        product=StoreProduct.objects.get(product_id=product_id),
        starts_at=timezone.now() - timedelta(days=1),
        ends_at=None,
        priority=0,
        rules=rules,
        status="active",
    )
    live.refresh_offers()
    return offer


def listed(player: Player, now: Any = None) -> list[str]:
    return [
        offer.offer_id
        for offer in offers.eligible_offers(player, "android", now=now or timezone.now())
    ]


def test_country_in() -> None:
    offer = make_offer([{"rule": "country_in", "countries": ["EG"]}])
    egyptian = make_player(country="EG")
    saudi = make_player(country="SA")
    assert listed(egyptian) == [offer.offer_id]
    assert listed(saudi) == []


def test_a_blank_country_never_matches() -> None:
    make_offer([{"rule": "country_in", "countries": ["EG"]}])
    assert listed(make_player(country="")) == []


def test_days_since_install_counts_cairo_days() -> None:
    offer = make_offer([{"rule": "days_since_install", "min": 0, "max": 6}])
    today = make_player()
    week_ago = make_player()
    Player.objects.filter(pk=week_ago.pk).update(created_at=timezone.now() - timedelta(days=8))
    week_ago.refresh_from_db()
    assert listed(today) == [offer.offer_id]
    assert listed(week_ago) == []


def test_day_zero_is_the_install_day() -> None:
    make_offer([{"rule": "days_since_install", "min": 0, "max": 0}])
    assert listed(make_player()) != []


@pytest.fixture
def stubbed(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    state: dict[str, Any] = {"has_purchase": False, "entitlements": frozenset()}
    real = facts.for_player

    def for_player(player: Player) -> facts.PlayerFacts:
        found = real(player)
        return facts.PlayerFacts(
            country=found.country,
            installed_at=found.installed_at,
            has_purchase=state["has_purchase"],
            entitlements=state["entitlements"],
            chapters=found.chapters,
        )

    monkeypatch.setattr(facts, "for_player", for_player)
    return state


def test_payer(stubbed: dict[str, Any]) -> None:
    paying = make_offer([{"rule": "payer", "is": True}])
    player = make_player()
    assert listed(player) == []
    stubbed["has_purchase"] = True
    assert listed(player) == [paying.offer_id]


def test_lacks_payer_with_the_shipped_no_purchases_facts() -> None:
    offer = make_offer([{"rule": "payer", "is": False}])
    assert listed(make_player()) == [offer.offer_id]


def test_owns_product(stubbed: dict[str, Any]) -> None:
    offer = make_offer([{"rule": "owns_product", "product_id": "remove_ads"}], "remove_ads")
    player = make_player()
    assert listed(player) == []  # the shipped facts own nothing
    stubbed["entitlements"] = frozenset({"remove_ads"})
    # The offer is for a non-consumable the player owns, so it stays hidden whatever its rules.
    assert listed(player) == []
    assert offer.offer_id not in listed(player)


def test_lacks_product(stubbed: dict[str, Any]) -> None:
    offer = make_offer([{"rule": "lacks_product", "product_id": "remove_ads"}])
    player = make_player()
    assert listed(player) == [offer.offer_id]
    stubbed["entitlements"] = frozenset({"remove_ads"})
    assert listed(player) == []


def test_chapter_reached() -> None:
    from apps.progress.models import StoryState

    offer = make_offer(
        [
            {
                "rule": "chapter_reached",
                "chapter_id": "ch1_first_job",
                "status": "completed",
            }
        ]
    )
    player = make_player()
    assert listed(player) == []
    StoryState.objects.create(player=player, chapter_id="ch1_first_job", status="completed")
    assert listed(player) == [offer.offer_id]
    other = make_player()
    StoryState.objects.create(player=other, chapter_id="ch1_first_job", status="open")
    assert listed(other) == []


@pytest.mark.parametrize(
    ("rules", "text"),
    [
        ([{"rule": "vip"}], "Rule 1: 'vip' is not a known rule."),
        ([{"rule": "country_in"}], "Rule 1 (country_in): countries is required."),
        (
            [{"rule": "payer", "is": True, "extra": 1}],
            "Rule 1 (payer): extra is not a field of this rule.",
        ),
        ([{"rule": "payer", "is": "yes"}], "Rule 1 (payer): is must be true or false."),
        (
            [{"rule": "days_since_install", "min": 5, "max": 1}],
            "Rule 1 (days_since_install): use 0 <= min <= max <= 3650.",
        ),
        (
            [{"rule": "country_in", "countries": ["Egypt"]}],
            "Rule 1 (country_in): 'Egypt' must be an ISO 3166-1 alpha-2 code.",
        ),
    ],
)
def test_validation_names_the_position_and_the_rule(rules: list[dict[str, Any]], text: str) -> None:
    with pytest.raises(offers.OfferRefused) as refused:
        offers.validate_rules(rules)
    assert str(refused.value) == text


def test_validation_keeps_only_the_documented_fields() -> None:
    assert offers.validate_rules([{"rule": "payer", "is": False}]) == [
        {"rule": "payer", "is": False}
    ]


@pytest.mark.parametrize(
    ("rules", "text"),
    [
        ("not a list", "Rules must be a list."),
        (["not an object"], "Rule 1 must be an object."),
        (
            [{"rule": "days_since_install", "min": "0", "max": 6}],
            "Rule 1 (days_since_install): '0' must be a whole number.",
        ),
        (
            [{"rule": "country_in", "countries": []}],
            "Rule 1 (country_in): countries must be a non-empty list.",
        ),
        (
            [{"rule": "owns_product", "product_id": "bogus"}],
            "Rule 1 (owns_product): 'bogus' is not a known product.",
        ),
        (
            [{"rule": "chapter_reached", "chapter_id": "BAD ID", "status": "completed"}],
            "Rule 1 (chapter_reached): 'BAD ID' is not a chapter id.",
        ),
        (
            [{"rule": "chapter_reached", "chapter_id": "ch1_first_job", "status": "done"}],
            "Rule 1 (chapter_reached): status must be open or completed.",
        ),
    ],
)
def test_more_validation_cases(rules: Any, text: str) -> None:
    with pytest.raises(offers.OfferRefused) as refused:
        offers.validate_rules(rules)
    assert str(refused.value) == text


def test_an_unknown_rule_name_never_holds() -> None:
    found = facts.PlayerFacts(
        country="EG",
        installed_at=timezone.now(),
        has_purchase=False,
        entitlements=frozenset(),
        chapters={},
    )
    assert offers._holds({"rule": "vip"}, found, timezone.now()) is False


def test_owns_product_with_no_catalog_row_holds_nothing(stubbed: dict[str, Any]) -> None:
    make_offer([{"rule": "owns_product", "product_id": "season_pass_zzz"}])
    assert listed(make_player()) == []


def test_save_offer_creates_then_updates_with_one_change_each() -> None:
    from apps.accounts.models import User
    from apps.liveops.models import LiveopsChange

    actor = User.objects.create_user("ops", is_staff=True)
    starts = timezone.now() - timedelta(days=1)
    values: dict[str, Any] = {
        "kind": "sale",
        "product_id": "bonat_pack_s",
        "starts_at": starts,
        "ends_at": None,
        "priority": 1,
        "rules": [],
        "status": "active",
    }
    created = offers.save_offer("first_offer", actor=actor, note="new", **values)
    assert created.offer_id == "first_offer"
    changes = LiveopsChange.objects.filter(target=LiveopsChange.Target.OFFER).order_by("at")
    assert changes[0].old is None
    assert changes[0].new is not None
    assert changes[0].new["product_id"] == "bonat_pack_s"

    offers.save_offer("first_offer", actor=actor, **{**values, "priority": 2})
    latest = LiveopsChange.objects.filter(target=LiveopsChange.Target.OFFER).latest("at")
    assert latest.old is not None
    assert latest.new is not None
    assert (latest.old["priority"], latest.new["priority"]) == (1, 2)


@pytest.mark.parametrize(
    ("offer_id", "overrides", "text"),
    [
        ("ok_offer", {"kind": "mystery"}, "is not an offer kind"),
        ("ok_offer", {"status": "lost"}, "is not an offer status"),
        ("BAD ID", {}, "Use lowercase letters, digits and underscores"),
        ("ok_offer", {"product_id": "bogus"}, "is not a product"),
        (
            "ok_offer",
            {"ends_at": timezone.now() - timedelta(days=2)},
            "The end must be after the start.",
        ),
    ],
)
def test_save_offer_refuses_bad_input(offer_id: str, overrides: dict[str, Any], text: str) -> None:
    from apps.accounts.models import User

    actor = User.objects.create_user("ops", is_staff=True)
    values: dict[str, Any] = {
        "kind": "sale",
        "product_id": "bonat_pack_s",
        "starts_at": timezone.now() - timedelta(days=1),
        "ends_at": None,
        "priority": 1,
        "rules": [],
        "status": "active",
        **overrides,
    }
    with pytest.raises(offers.OfferRefused, match=text):
        offers.save_offer(offer_id, actor=actor, **values)
