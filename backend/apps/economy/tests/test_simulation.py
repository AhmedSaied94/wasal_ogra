"""SC-006 and SC-004: honest play is never refused, and many phones at once keep the ledger
(B03 tasks.md T088).

The first test plays 30 game days on three phones whose clocks are off by minutes. Each phone
decides as M05 and M02 do, from the same rules over its own record on its own clock: it starts a
trip only with fuel to spare by its count, plays what its stars unlock, buys what it can afford,
watches ads within their caps, and takes the gifts it is offered. It syncs at irregular times,
sometimes after a session, sometimes days later. Every operation must be accepted, with no flag
beyond the soft ones, and the phone's JENEHAT must equal the server's.

The second sends 200 batches at once across 20 players, some with two phones and some batches sent
twice, and checks nothing is lost, doubled or negative.
"""

from __future__ import annotations

import random
import threading
import uuid
from collections.abc import Callable, Mapping
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import pytest
import time_machine
from django.db import connection
from django.utils import timezone

from apps.accounts.models import Player
from apps.accounts.services import players
from apps.accounts.tests.factories import CLIENT
from apps.common.client import ClientInfo
from apps.content.services import lookups
from apps.economy.models import Currency, Inventory, PlayerFlag, ProcessedOp
from apps.economy.services import bootstrap, fuel, settings
from apps.economy.services.fuel import FuelState
from apps.economy.services.gameday import game_date
from apps.economy.services.sync import BatchResult
from apps.economy.services.timeline import to_ms
from apps.economy.tests.helpers import (
    grant,
    ledger_sum,
    op,
    run,
    spend,
    trip_result,
    trip_start,
    txn_of,
    wallet_of,
)
from apps.progress.services import unlocks

pytestmark = pytest.mark.django_db

CAIRO = ZoneInfo("Africa/Cairo")
FIRST_DAY = datetime(2026, 9, 1, tzinfo=CAIRO)
DAYS = 30
SESSION_HOURS = (8, 13, 19)  # away from midnight, so a phone's game day is the server's
SKEWS_MS = (-240_000, 0, 120_000)  # one phone 4 minutes slow, one right, one 2 minutes fast
AWAY_DAYS = range(10, 19)  # phone 1 puts the game down for nine days
MARGIN = 2  # an honest phone starts a trip only with this many liters by its own count
SOFT_FLAGS = {"fuel_overdraft", "clock_clamped"}
MAX_BATCH = 100


@dataclass
class Phone:
    """An honest phone: M05's rules over its own record, on its own clock."""

    player: Player
    version: int
    skew_ms: int
    rng: random.Random
    shift: Callable[[float], None]
    fuel: FuelState
    stars: dict[str, int] = field(default_factory=dict)
    owned: dict[tuple[str, str], str] = field(default_factory=dict)  # -> variant
    claimed: set[str] = field(default_factory=set)
    local_jenehat: int = 0
    local_bonat: int = 0
    bags: int = 0
    refills: dict[date, int] = field(default_factory=dict)
    queue: list[dict[str, Any]] = field(default_factory=list)
    # A claim in the outbox: bootstrap still says claimable until it is synced, so the app
    # ignores that while it waits (handed to M06).
    comeback_pending: bool = False
    results: list[tuple[str, str]] = field(default_factory=list)  # (op_type, reason)
    base: int = 0

    def __post_init__(self) -> None:
        self.config = settings.current()
        self.rules: Mapping[str, Any] = lookups.rules(self.version) or {}
        self.bounds = lookups.trip_bounds(self.version)
        self.prices = lookups.catalog_prices(self.version)

    def now(self) -> datetime:
        return timezone.now() + timedelta(milliseconds=self.skew_ms)

    def view(self) -> unlocks.PlayerView:
        return unlocks.PlayerView(best_stars=dict(self.stars), owned=frozenset(self.owned))

    def tank(self) -> FuelState:
        regen = fuel.regen_ms_of(self.config.fuel_regen_minutes)
        return fuel.regenerate(
            self.fuel, to_ms(self.now()), max_liters=self.config.fuel_max, regen_ms=regen
        )

    def gift(self) -> None:
        regen = fuel.regen_ms_of(self.config.fuel_regen_minutes)
        self.fuel = fuel.gift(
            self.fuel, to_ms(self.now()), max_liters=self.config.fuel_max, regen_ms=regen
        )

    # -- a session -----------------------------------------------------------------------------

    def session(self, first: bool) -> None:
        launch = bootstrap.bootstrap(self.player, ClientInfo("1.0.0+1", "android"))
        if launch["comeback"]["claimable"] and not self.comeback_pending:
            self.comeback_pending = True
            self.gift()
            self.bags += 1
            self.queue.append(op("comeback_gift", {}, at=self.now()))
        if first:
            payload: dict[str, Any] = {
                "display_name": "Honest Driver",
                "settings": {"digits": "arabic"},
            }
            self.queue.append(op("settings_update", payload, at=self.now()))
            scene = {"chapter_id": "ch1_first_job", "scene_id": "the_stand"}
            payload = {**scene, "content_version": self.version}
            self.queue.append(op("story_progress", payload, at=self.now()))
        for _ in range(self.rng.randint(1, 4)):
            self.refill_if_low()
            if self.tank().liters < MARGIN:
                break
            self.play()
            if first and self.rng.random() < 0.5:
                first = False
                self.gift()
                self.queue.append(op("tutorial_gift", {}, at=self.now()))
            self.shift(self.rng.randint(30, 180))
        self.shop()

    def refill_if_low(self) -> None:
        t = self.now()
        tank = self.tank()
        day = game_date(t)
        if tank.liters > MARGIN or self.refills.get(day, 0) >= self.config.fuel_refill_daily_cap:
            return
        filled = fuel.fill_to_max(tank, to_ms(t), max_liters=self.config.fuel_max)
        if filled is not None:
            self.fuel = filled
            self.refills[day] = self.refills.get(day, 0) + 1
            self.queue.append(op("ad_reward", {"ad_placement": "fuel_refill"}, at=t))

    def next_trip(self) -> str:
        view = self.view()
        playable: list[str] = [
            t
            for t in self.rules["trips"]
            if t in self.bounds and unlocks.trip_unlocked(self.rules, view, t)
        ]
        fresh = [t for t in playable if self.stars.get(t, 0) < 3]
        return fresh[0] if fresh and self.rng.random() < 0.8 else self.rng.choice(playable)

    def play(self) -> None:
        trip = self.next_trip()
        bounds = self.bounds[trip]
        t = self.now()
        self.fuel = fuel.spend_one(self.tank(), to_ms(t), max_liters=self.config.fuel_max)
        start = trip_start(trip, self.version, at=t)
        self.queue.append(start)
        if self.bags and self.rng.random() < 0.5:
            self.bags -= 1
            self.queue.append(
                op("use_booster", {"booster_id": "change_bag", "ref": txn_of(start)}, at=self.now())
            )
        duration = int(bounds.last_station_at_s * 1000 * self.rng.uniform(1.0, 1.4))
        self.shift(duration / 1000)
        roll = self.rng.random()
        if roll < 0.1:
            if self.rng.random() < 0.5:
                revive = {"ad_placement": "trip_revive", "ref": txn_of(start)}
                self.queue.append(op("ad_reward", revive, at=self.now()))
            outcome: dict[str, Any] = {"outcome": "failed", "stars": 0, "earnings_jenehat": 0}
        else:
            stars = 3 if roll > 0.3 else self.rng.choice([1, 2])
            earnings = self.rng.randint(1, bounds.max_earnings_jenehat)
            outcome = {"outcome": "finished", "stars": stars, "earnings_jenehat": earnings}
            self.stars[trip] = max(self.stars.get(trip, 0), stars)
            self.local_jenehat += earnings
        self.queue.append(
            trip_result(start, trip, at=self.now(), rev=bounds.rev, duration_ms=duration, **outcome)
        )
        if outcome["earnings_jenehat"] and self.rng.random() < 0.3:
            double = {"ad_placement": "result_double", "ref": txn_of(start)}
            self.queue.append(op("ad_reward", double, at=self.now()))
            self.local_jenehat += outcome["earnings_jenehat"]

    def shop(self) -> None:
        """One purchase a session: the cheapest thing the phone may buy and can afford."""
        view = self.view()
        for (kind, sku), price in sorted(self.prices.items(), key=lambda p: (p[1].amount, p[0])):
            if price.currency != Currency.JENEHAT or price.amount > self.local_jenehat:
                continue
            if kind == "vehicle":
                if unlocks.vehicle_owned(self.rules, view, sku):
                    continue
            elif kind == "item":
                if (kind, sku) in self.owned or not unlocks.item_purchasable(self.rules, view, sku):
                    continue
            elif kind == "chapter":
                if (kind, sku) in self.owned or not unlocks.chapter_unlocked(self.rules, view, sku):
                    continue
            else:
                continue
            extra: dict[str, str] = {}
            if kind == "item":
                extra["variant"] = self.rng.choice(self.rules["items"][sku]["variants"])
            self.queue.append(spend(kind, sku, price.amount, self.version, at=self.now(), **extra))
            self.owned[(kind, sku)] = extra.get("variant", "")
            self.local_jenehat -= price.amount
            break
        self.claim_requests()
        if self.local_bonat >= 10 and self.rng.random() < 0.5:
            self.queue.append(spend("booster", "change_bag", 10, self.version, at=self.now()))
            self.local_bonat -= 10
            self.bags += 1

    def claim_requests(self) -> None:
        for request_id, request in self.rules["requests"].items():
            owned = self.owned.get(("item", request["item_id"]))
            if request_id in self.claimed or owned is None:
                continue
            if request["variant_id"] in ("", owned):
                self.claimed.add(request_id)
                payload = {"request_id": request_id, "content_version": self.version}
                self.queue.append(op("claim_request", payload, at=self.now()))

    # -- syncing -------------------------------------------------------------------------------

    def sync(self) -> None:
        while self.queue:
            envelopes, self.queue = self.queue[:MAX_BATCH], self.queue[MAX_BATCH:]
            result = run(self.player, *envelopes, base=self.base)
            self.base = result.state_version
            self.results += [
                (e["op_type"], r.outcome.reason)
                for e, r in zip(envelopes, result.results, strict=True)
                if r.outcome.status != "accepted"
            ]
            # BONAT is the server's to grant (rewards), so the phone takes the server's figure.
            self.local_bonat = result.wallet["bonat"]
        self.comeback_pending = False


def test_thirty_days_of_honest_play_are_never_refused(published_pack: int) -> None:
    with time_machine.travel(FIRST_DAY.replace(hour=7), tick=False) as traveller:
        phones = []
        for n, skew in enumerate(SKEWS_MS):
            issued, _ = players.create_or_return(uuid.uuid4(), "android", "ar-EG", client=CLIENT)
            player = Player.objects.get(pk=issued.player_id)
            run(player)  # the wallet: a full tank, now
            phones.append(
                Phone(
                    player=player,
                    version=published_pack,
                    skew_ms=skew,
                    rng=random.Random(n),  # noqa: S311 - a repeatable simulation
                    shift=traveller.shift,
                    fuel=FuelState(liters=5, counted_from_ms=to_ms(timezone.now())),
                )
            )
        for day in range(DAYS):
            for hour in SESSION_HOURS:
                traveller.move_to(FIRST_DAY + timedelta(days=day, hours=hour))
                for n, phone in enumerate(phones):
                    if n == 1 and day in AWAY_DAYS:
                        continue
                    phone.session(first=day == 0 and hour == SESSION_HOURS[0])
                    if phone.rng.random() < 0.4 or len(phone.queue) > 2 * MAX_BATCH:
                        phone.sync()
        for phone in phones:
            phone.sync()

    for phone in phones:
        assert phone.results == []
        wallet = wallet_of(phone.player)
        assert wallet.jenehat == phone.local_jenehat == ledger_sum(phone.player, Currency.JENEHAT)
        assert wallet.bonat == ledger_sum(phone.player, Currency.BONAT)
        kinds = set(PlayerFlag.objects.filter(player=phone.player).values_list("kind", flat=True))
        assert kinds <= SOFT_FLAGS
    assert ProcessedOp.objects.filter(op_type="comeback_gift", status="accepted").count() == 1
    assert ProcessedOp.objects.filter(op_type="trip_result").count() > 300


# -- many phones at once ---------------------------------------------------------------------------


@pytest.mark.django_db(transaction=True)
def test_two_hundred_batches_at_once_keep_every_wallet(published_pack: int) -> None:
    rng = random.Random(7)  # noqa: S311 - a repeatable simulation
    people = []
    for _ in range(20):
        issued, _ = players.create_or_return(uuid.uuid4(), "android", "ar-EG", client=CLIENT)
        player = Player.objects.get(pk=issued.player_id)
        grant(player, Currency.BONAT, 1_000)
        people.append(player)

    def batch_for(player: Player) -> list[dict[str, Any]]:
        start = trip_start("line_hay.01", published_pack)
        choices = [
            [start, trip_result(start, "line_hay.01", earnings_jenehat=rng.randint(1, 20))],
            [spend("booster", "change_bag", 10, published_pack)],
            [op("ad_reward", {"ad_placement": "fuel_refill"})],
            [spend("booster", "change_bag", 10, published_pack), start],
        ]
        return rng.choice(choices)

    calls: list[tuple[Player, list[dict[str, Any]]]] = []
    for player in people:
        for _ in range(9):  # two phones of a player send their batches at the same moments
            calls.append((player, batch_for(player)))
    while len(calls) < 200:  # retries: a batch sent again while the first is in flight
        calls.append(rng.choice(calls))
    rng.shuffle(calls)
    lock = threading.Lock()
    answers: dict[tuple[str, ...], list[list[Any]]] = {}

    def send(call: tuple[Player, list[dict[str, Any]]]) -> BatchResult:
        player, envelopes = call
        try:
            result = run(player, *envelopes)
            key = tuple(txn_of(e) for e in envelopes)
            with lock:
                answers.setdefault(key, []).append([r.outcome for r in result.results])
            return result
        finally:
            connection.close()

    with ThreadPoolExecutor(max_workers=16) as pool:
        results = list(pool.map(send, calls))
    assert len(results) == 200

    for outcomes in answers.values():  # the same batch always answers the same
        assert all(o == outcomes[0] for o in outcomes)
    sent = {txn_of(e) for _, envelopes in calls for e in envelopes}
    assert ProcessedOp.objects.count() == len(sent)
    for player in people:
        wallet = wallet_of(player)
        assert min(wallet.jenehat, wallet.bonat, wallet.fuel) >= 0
        assert wallet.jenehat == ledger_sum(player, Currency.JENEHAT)
        assert wallet.bonat == ledger_sum(player, Currency.BONAT)
        bought = ProcessedOp.objects.filter(
            player=player, op_type="spend_bonat", status="accepted"
        ).count()
        assert wallet.bonat == 1_000 - 10 * bought
        bags = Inventory.objects.filter(player=player, booster_id="change_bag").first()
        assert (bags.count if bags else 0) == bought
