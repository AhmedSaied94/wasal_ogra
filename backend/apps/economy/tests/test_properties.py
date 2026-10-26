"""SC-002, FR-006, FR-013: random play, batched at random and partly sent twice, keeps the ledger.

A hypothesis state machine plays trips at a clock it moves, queues their operations as an offline
phone does, and sends them in batches of random size, sometimes twice. After every step: each
wallet balance equals the sum of its ledger, no balance is below 0, `state_version` never goes
back, and a batch sent again changes nothing and answers the same. US2 adds purchases, boosters
and ads, and the direction rule: no accepted operation the phone sends raises BONAT itself, and
none lowers BONAT while raising JENEHAT (operations.md). US6 adds the gifts, request claims, story
scenes and settings, and checks that every room, chapter and request reward is paid exactly once,
with its grant record.

300 examples in the normal run; `HYPOTHESIS_PROFILE=thorough` runs 10,000 (quickstart A1).
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, ClassVar

import pytest
import time_machine
from django.db import transaction
from hypothesis import settings as hypothesis_settings
from hypothesis import strategies as st
from hypothesis.stateful import (
    RuleBasedStateMachine,
    invariant,
    precondition,
    rule,
    run_state_machine_as_test,
)

from apps.accounts.models import Player
from apps.accounts.tests.factories import make_player
from apps.content.models import ContentPack, PackPriceIndex
from apps.economy.models import Currency, GrantRecord, LedgerEntry, ProcessedOp, Wallet
from apps.economy.services.sync import BatchResult
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

pytestmark = pytest.mark.django_db

T0 = datetime(2026, 10, 24, 6, 0, tzinfo=UTC)
TRIPS = ["line_hay.01", "line_hay.02", "line_hay.03", "line_gamaa.01", "line_hay.99"]
OUTCOMES = ["finished", "failed", "abandoned"]
MINUTES = [0, 1, 7, 20, 61, 300, 1440]
# (sku_kind, sku_id, catalog price, extra payload)
PURCHASES = [
    ("item", "salon.nish", 400, {"variant": "classic"}),
    ("item", "salon.nish", 400, {"variant": "crystal"}),
    ("item", "salon.sitara", 150, {"variant": "plain"}),
    ("vehicle", "micro_old", 1500, {}),
    ("chapter", "ch3_shabka", 900, {}),
    ("booster", "change_bag", 10, {}),
    ("booster", "wake_all", 8, {}),
    ("fuel", "refuel_full", 30, {}),
    ("fuel_unlimited", "fuel_unlimited_1h", 80, {}),
    ("cosmetic", "dice_mirror", 15, {}),
]
PLACEMENTS = ["result_double", "trip_revive", "traffic_jam", "fuel_refill", "morning_piggy"]
REQUESTS = ["req_nish_crystal", "req_none"]
SCENES = [("ch1_first_job", "the_stand"), ("ch2_her_father", "the_stand"), ("ch9_none", "x")]
NAMES = ["Hamada", "z", "admin", "١٢٣"]
REWARDS = (LedgerEntry.Reason.STORY_REWARD, LedgerEntry.Reason.REQUEST_REWARD)
REWARD_GRANTS = (GrantRecord.Kind.ROOM, GrantRecord.Kind.CHAPTER, GrantRecord.Kind.REQUEST)


class EconomyMachine(RuleBasedStateMachine):
    version: ClassVar[int]

    def __init__(self) -> None:
        super().__init__()
        self.atomic = transaction.atomic()
        self.atomic.__enter__()
        self.travel = time_machine.travel(T0, tick=False)
        self.clock = self.travel.start()
        self.player: Player = make_player()
        grant(self.player, Currency.JENEHAT, 3_000)
        grant(self.player, Currency.BONAT, 200)
        self.queue: list[dict[str, Any]] = []  # recorded, not yet sent
        self.sent: list[tuple[list[dict[str, Any]], BatchResult]] = []
        self.starts: list[dict[str, Any]] = []
        self.last_version = 0

    def teardown(self) -> None:
        self.travel.stop()
        transaction.set_rollback(True)
        self.atomic.__exit__(None, None, None)

    def at(self) -> datetime:
        return datetime.now(UTC)

    # -- recording ---------------------------------------------------------------------------------

    @rule(trip=st.sampled_from(TRIPS), mode=st.sampled_from(["fuel", "fuel", "unlimited"]))
    def start(self, trip: str, mode: str) -> None:
        envelope = trip_start(trip, self.version, mode=mode, at=self.at())
        self.queue.append(envelope)
        self.starts.append(envelope)

    @precondition(lambda self: self.starts)
    @rule(
        data=st.data(),
        outcome=st.sampled_from(OUTCOMES),
        stars=st.integers(-1, 4),
        earnings=st.integers(-1, 60),
        duration=st.sampled_from([1, 30_000, 60_000, 600_000]),
    )
    def result(
        self, data: st.DataObject, outcome: str, stars: int, earnings: int, duration: int
    ) -> None:
        start = data.draw(st.sampled_from(self.starts))
        trip_id = start["payload"]["trip_id"]
        self.queue.append(
            trip_result(
                start,
                trip_id,
                at=self.at(),
                outcome=outcome,
                stars=stars,
                earnings_jenehat=earnings,
                duration_ms=duration,
            )
        )

    @rule(purchase=st.sampled_from(PURCHASES), off=st.sampled_from([0, 0, 0, 1, -1]))
    def buy(self, purchase: tuple[str, str, int, dict[str, str]], off: int) -> None:
        kind, sku, price, extra = purchase
        self.queue.append(spend(kind, sku, price + off, self.version, at=self.at(), **extra))

    @precondition(lambda self: self.starts)
    @rule(data=st.data())
    def buy_revive(self, data: st.DataObject) -> None:
        start = data.draw(st.sampled_from(self.starts))
        payload = {"sku_kind": "revive", "sku_id": "revive", "price": 20}
        self.queue.append(
            op(
                "spend_bonat",
                {**payload, "content_version": self.version, "ref": txn_of(start)},
                at=self.at(),
            )
        )

    @precondition(lambda self: self.starts)
    @rule(data=st.data(), booster=st.sampled_from(["change_bag", "wake_all", "rocket"]))
    def use_booster(self, data: st.DataObject, booster: str) -> None:
        start = data.draw(st.sampled_from(self.starts))
        self.queue.append(
            op("use_booster", {"booster_id": booster, "ref": txn_of(start)}, at=self.at())
        )

    @precondition(lambda self: self.starts)
    @rule(data=st.data(), placement=st.sampled_from(PLACEMENTS))
    def watch_ad(self, data: st.DataObject, placement: str) -> None:
        payload: dict[str, Any] = {"ad_placement": placement}
        if placement != "fuel_refill":
            payload["ref"] = txn_of(data.draw(st.sampled_from(self.starts)))
        self.queue.append(op("ad_reward", payload, at=self.at()))

    @rule(kind=st.sampled_from(["tutorial_gift", "comeback_gift"]))
    def gift(self, kind: str) -> None:
        self.queue.append(op(kind, {}, at=self.at()))

    @rule()
    def come_back(self) -> None:
        """What a bootstrap after a long absence leaves on the wallet (research R13)."""
        Wallet.objects.filter(player=self.player).update(comeback_return_at=self.at())

    @rule(request=st.sampled_from(REQUESTS))
    def claim(self, request: str) -> None:
        payload = {"request_id": request, "content_version": self.version}
        self.queue.append(op("claim_request", payload, at=self.at()))

    @rule(scene=st.sampled_from(SCENES))
    def see(self, scene: tuple[str, str]) -> None:
        chapter, scene_id = scene
        payload = {"chapter_id": chapter, "scene_id": scene_id, "content_version": self.version}
        self.queue.append(op("story_progress", payload, at=self.at()))

    @rule(name=st.sampled_from(NAMES), digits=st.sampled_from(["arabic", "western", "roman"]))
    def rename(self, name: str, digits: str) -> None:
        payload = {"display_name": name, "settings": {"digits": digits}}
        self.queue.append(op("settings_update", payload, at=self.at()))

    @rule(minutes=st.sampled_from(MINUTES))
    def advance(self, minutes: int) -> None:
        self.clock.shift(minutes * 60)

    # -- sending -----------------------------------------------------------------------------------

    @precondition(lambda self: self.queue)
    @rule(size=st.integers(1, 30), twice=st.booleans())
    def send(self, size: int, twice: bool) -> None:
        envelopes, self.queue = self.queue[:size], self.queue[size:]
        result = run(self.player, *envelopes, base=self.last_version)
        assert result.state_version >= self.last_version
        self.last_version = result.state_version
        self.sent.append((envelopes, result))
        self.check_directions(result)
        if twice:
            self.repeat(envelopes, result)

    @precondition(lambda self: self.sent)
    @rule(data=st.data())
    def resend(self, data: st.DataObject) -> None:
        envelopes, result = data.draw(st.sampled_from(self.sent))
        self.repeat(envelopes, result)

    def repeat(self, envelopes: list[dict[str, Any]], first: BatchResult) -> None:
        before = self.totals()
        again = run(self.player, *envelopes, base=self.last_version)
        assert [r.outcome for r in again.results] == [r.outcome for r in first.results]
        assert again.state_version == self.last_version
        assert self.totals() == before

    def check_directions(self, result: BatchResult) -> None:
        """The direction rule, for each operation the batch accepted."""
        accepted = [r.client_txn_id for r in result.results if r.outcome.status == "accepted"]
        moves: dict[Any, dict[str, int]] = {}
        client_bonat: dict[Any, int] = {}
        for entry in LedgerEntry.objects.filter(player=self.player, op_id__in=accepted):
            total = moves.setdefault(entry.op_id, {Currency.JENEHAT: 0, Currency.BONAT: 0})
            total[entry.currency] += entry.delta
            if entry.currency == Currency.BONAT and entry.source == LedgerEntry.Source.CLIENT_OP:
                client_bonat[entry.op_id] = client_bonat.get(entry.op_id, 0) + entry.delta
        assert all(delta <= 0 for delta in client_bonat.values())
        for total in moves.values():
            assert not (total[Currency.BONAT] < 0 and total[Currency.JENEHAT] > 0)

    def totals(self) -> tuple[int, ...]:
        wallet = wallet_of(self.player)
        return (
            wallet.jenehat,
            wallet.bonat,
            wallet.fuel,
            wallet.state_version,
            LedgerEntry.objects.filter(player=self.player).count(),
            ProcessedOp.objects.filter(player=self.player).count(),
        )

    # -- invariants --------------------------------------------------------------------------------

    @invariant()
    def wallet_equals_ledger(self) -> None:
        if not self.sent:
            return
        wallet = wallet_of(self.player)
        assert wallet.jenehat == ledger_sum(self.player, Currency.JENEHAT)
        assert wallet.bonat == ledger_sum(self.player, Currency.BONAT)
        assert min(wallet.jenehat, wallet.bonat, wallet.fuel) >= 0
        assert wallet.state_version == self.last_version

    @invariant()
    def each_reward_is_paid_once(self) -> None:
        paid = LedgerEntry.objects.filter(player=self.player, reason__in=REWARDS)
        granted = GrantRecord.objects.filter(player=self.player, kind__in=REWARD_GRANTS)
        assert sorted(paid.values_list("ref_type", "ref_id")) == sorted(
            granted.values_list("kind", "key")
        )

    @invariant()
    def every_sent_operation_has_one_outcome(self) -> None:
        ids = {txn_of(e) for envelopes, _ in self.sent for e in envelopes}
        assert ProcessedOp.objects.filter(player=self.player).count() == len(ids)


def test_random_batches_keep_the_ledger(published_pack: int) -> None:
    PackPriceIndex.objects.create(
        pack=ContentPack.objects.get(version=published_pack),
        version=published_pack,
        sku_kind="cosmetic",
        sku_id="dice_mirror",
        currency="BONAT",
        amount=15,
    )
    EconomyMachine.version = published_pack
    run_state_machine_as_test(  # type: ignore[no-untyped-call]  # hypothesis leaves it untyped
        EconomyMachine, settings=hypothesis_settings(stateful_step_count=20)
    )
