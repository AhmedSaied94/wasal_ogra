"""The economy tables (B03 data-model.md "economy").

Every amount is an integer. `Wallet.jenehat` and `Wallet.bonat` change only through
`apps.economy.services.ledger`, which appends a `LedgerEntry` for each change (research R4); a test
scans the code for any other writer. Ledger entries and wallet adjustments are append-only.
"""

from __future__ import annotations

from typing import Any, ClassVar

from django.db import models
from django.db.models import Q

from apps.accounts.models import Player, User
from apps.common.models import UUIDv7Model


class AppendOnlyError(RuntimeError):
    """An update or delete of an append-only row. B09's anonymization will have its own path."""


class AppendOnlyQuerySet(models.QuerySet[Any]):
    def update(self, **kwargs: Any) -> int:
        raise AppendOnlyError(f"{self.model._meta.label} is append-only")

    def delete(self) -> tuple[int, dict[str, int]]:
        raise AppendOnlyError(f"{self.model._meta.label} is append-only")


class Currency(models.TextChoices):
    JENEHAT = "JENEHAT"
    BONAT = "BONAT"


class Wallet(models.Model):
    """One row per player, and the row every batch locks (research R5)."""

    player = models.OneToOneField(
        Player, primary_key=True, on_delete=models.PROTECT, related_name="wallet"
    )
    jenehat = models.PositiveBigIntegerField(default=0)
    bonat = models.PositiveBigIntegerField(default=0)
    fuel = models.PositiveSmallIntegerField()
    # M05's `countedFrom`: when the current countdown started, or when the tank last became full.
    fuel_updated_at = models.DateTimeField()
    fuel_unlimited_until = models.DateTimeField(null=True, blank=True)
    # The effective time of the last operation applied (research R7).
    timeline_at = models.DateTimeField()
    state_version = models.PositiveIntegerField(default=0)
    last_active_at = models.DateTimeField()
    session_started_at = models.DateTimeField()
    # A return the player may claim the comeback gift for (research R13).
    comeback_return_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        permissions = (("adjust_wallet", "Can adjust a player's balance"),)
        constraints = (
            models.CheckConstraint(condition=Q(jenehat__gte=0), name="wallet_jenehat_not_negative"),
            models.CheckConstraint(condition=Q(bonat__gte=0), name="wallet_bonat_not_negative"),
            models.CheckConstraint(condition=Q(fuel__gte=0), name="wallet_fuel_not_negative"),
        )

    def __str__(self) -> str:
        return f"wallet {self.player_id}"


class LedgerEntry(UUIDv7Model):
    """One signed change of one currency. Append-only (FR-005, FR-007)."""

    class Reason(models.TextChoices):
        # Backend §7.2, plus the two this feature grants (FR-008).
        TRIP_EARNINGS = "trip_earnings"
        AD_RESULT_DOUBLE = "ad_result_double"
        AD_FUEL_REFILL = "ad_fuel_refill"
        ITEM_PURCHASE = "item_purchase"
        VEHICLE_PURCHASE = "vehicle_purchase"
        CHAPTER_PURCHASE = "chapter_purchase"
        UPGRADE_PURCHASE = "upgrade_purchase"
        COSMETIC_PURCHASE = "cosmetic_purchase"
        BOOSTER_PURCHASE = "booster_purchase"
        FUEL_PURCHASE = "fuel_purchase"
        FUEL_UNLIMITED_PURCHASE = "fuel_unlimited_purchase"
        REVIVE_PURCHASE = "revive_purchase"
        IAP_GRANT = "iap_grant"
        SSV_GRANT = "ssv_grant"
        DAILY_REWARD = "daily_reward"
        TASK_REWARD = "task_reward"
        CHALLENGE_REWARD = "challenge_reward"
        SUBSCRIBER_GRANT = "subscriber_grant"
        SEASON_REWARD = "season_reward"
        REFERRAL_REWARD = "referral_reward"
        REFUND_REVERSAL = "refund_reversal"
        ADMIN_ADJUSTMENT = "admin_adjustment"
        REQUEST_REWARD = "request_reward"
        STORY_REWARD = "story_reward"

    class Source(models.TextChoices):
        CLIENT_OP = "client_op"
        PURCHASE = "purchase"
        SSV = "ssv"
        SYSTEM = "system"
        ADMIN = "admin"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="ledger_entries")
    currency = models.CharField(max_length=8, choices=Currency.choices)
    delta = models.BigIntegerField()
    balance_after = models.PositiveBigIntegerField()
    reason = models.CharField(max_length=32, choices=Reason.choices)
    ref_type = models.CharField(max_length=16, blank=True)
    ref_id = models.CharField(max_length=80, blank=True)
    # The operation's `client_txn_id`. Not a foreign key: processed operations are pruned, the
    # ledger is kept (plan, post-design re-check).
    op_id = models.UUIDField(null=True, blank=True)
    source = models.CharField(max_length=16, choices=Source.choices)
    created_at = models.DateTimeField(auto_now_add=True)

    objects: ClassVar[AppendOnlyQuerySet] = AppendOnlyQuerySet.as_manager()  # type: ignore[assignment]

    class Meta:
        verbose_name_plural = "ledger entries"
        indexes = (
            models.Index(fields=("player", "created_at"), name="ledger_by_player_time"),
            models.Index(fields=("player", "currency"), name="ledger_by_player_currency"),
        )
        constraints = (models.CheckConstraint(condition=~Q(delta=0), name="ledger_delta_not_zero"),)

    def __str__(self) -> str:
        return f"{self.currency} {self.delta:+d} {self.reason}"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            raise AppendOnlyError("the ledger is append-only")
        super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        raise AppendOnlyError("the ledger is append-only")


class ProcessedOp(UUIDv7Model):
    """The stored outcome of one `client_txn_id`, which makes a repeat harmless (FR-013)."""

    class Status(models.TextChoices):
        ACCEPTED = "accepted"
        REJECTED = "rejected"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="processed_ops")
    client_txn_id = models.UUIDField()
    op_type = models.CharField(max_length=40)
    payload_hash = models.CharField(max_length=64)
    status = models.CharField(max_length=8, choices=Status.choices)
    reason = models.CharField(max_length=40, blank=True)
    # Small: grants and amounts, never the wallet (research R11).
    result = models.JSONField(default=dict, blank=True)
    processed_at = models.DateTimeField()

    class Meta:
        indexes = (models.Index(fields=("processed_at",), name="processed_op_prune"),)
        constraints = (
            models.UniqueConstraint(fields=("player", "client_txn_id"), name="processed_op_once"),
        )

    def __str__(self) -> str:
        return f"{self.op_type} {self.status}"


class Inventory(UUIDv7Model):
    class Booster(models.TextChoices):
        CHANGE_BAG = "change_bag"
        WAKE_ALL = "wake_all"
        LEDGER_PEEK = "ledger_peek"
        TRAFFIC_JAM = "traffic_jam"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="inventory")
    booster_id = models.CharField(max_length=16, choices=Booster.choices)
    count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "inventory"
        constraints = (
            models.UniqueConstraint(fields=("player", "booster_id"), name="inventory_once"),
        )

    def __str__(self) -> str:
        return f"{self.booster_id} x {self.count}"


class PlayerFlag(UUIDv7Model):
    """A soft anomaly, accepted and noted (FR-040). One row per kind, player and game day."""

    class Kind(models.TextChoices):
        FUEL_OVERDRAFT = "fuel_overdraft"
        FAST_THREE_STAR = "fast_three_star"
        TRIP_RATE = "trip_rate"
        TXN_PAYLOAD_MISMATCH = "txn_payload_mismatch"
        CLOCK_CLAMPED = "clock_clamped"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="flags")
    kind = models.CharField(max_length=24, choices=Kind.choices)
    game_date = models.DateField()
    # Ids and numbers only, with `count` (research R8).
    details = models.JSONField(default=dict, blank=True)
    reviewed_by = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    resolution = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = (
            models.Index(
                fields=("reviewed_at",), condition=Q(reviewed_at__isnull=True), name="flag_open"
            ),
        )
        constraints = (
            models.UniqueConstraint(fields=("player", "kind", "game_date"), name="flag_once_a_day"),
        )

    def __str__(self) -> str:
        return f"{self.kind} {self.game_date}"


class DayCounter(UUIDv7Model):
    """Per player and game day counts behind the daily caps. Pruned after 40 days."""

    class Kind(models.TextChoices):
        OVERDRAFT = "overdraft"
        FUEL_REFILL_AD = "fuel_refill_ad"
        TRIPS_STARTED = "trips_started"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="day_counters")
    game_date = models.DateField()
    kind = models.CharField(max_length=16, choices=Kind.choices)
    count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = (
            models.UniqueConstraint(
                fields=("player", "game_date", "kind"), name="day_counter_once"
            ),
        )

    def __str__(self) -> str:
        return f"{self.kind} {self.game_date}: {self.count}"


class GrantRecord(UUIDv7Model):
    """A one-time grant a player had, so none is granted twice (FR-024-FR-028)."""

    class Kind(models.TextChoices):
        TUTORIAL = "tutorial"
        COMEBACK = "comeback"
        REQUEST = "request"
        ROOM = "room"
        CHAPTER = "chapter"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="grants")
    kind = models.CharField(max_length=16, choices=Kind.choices)
    # "" for the tutorial; the return time (ISO, UTC) for a comeback; else the content id.
    key = models.CharField(max_length=80, blank=True)
    op_id = models.UUIDField(null=True, blank=True)
    granted_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = (
            models.Index(fields=("player", "kind", "granted_at"), name="grant_by_kind_time"),
        )
        constraints = (
            models.UniqueConstraint(fields=("player", "kind", "key"), name="grant_once"),
        )

    def __str__(self) -> str:
        return f"{self.kind} {self.key}".strip()


class WalletAdjustment(UUIDv7Model):
    """A staff adjustment: the audit record of backend §13 (research R19). Append-only."""

    actor = models.ForeignKey(User, on_delete=models.PROTECT, related_name="+")
    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="adjustments")
    currency = models.CharField(max_length=8, choices=Currency.choices)
    delta = models.BigIntegerField()
    reason = models.CharField(max_length=200)
    ledger_entry = models.ForeignKey(LedgerEntry, on_delete=models.PROTECT, related_name="+")
    at = models.DateTimeField()

    objects: ClassVar[AppendOnlyQuerySet] = AppendOnlyQuerySet.as_manager()  # type: ignore[assignment]

    class Meta:
        default_permissions = ("view",)

    def __str__(self) -> str:
        return f"{self.currency} {self.delta:+d} by {self.actor_id}"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            raise AppendOnlyError("wallet adjustments are append-only")
        super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        raise AppendOnlyError("wallet adjustments are append-only")
