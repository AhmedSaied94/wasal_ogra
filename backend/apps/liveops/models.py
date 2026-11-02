"""The live-ops tables (B10 data-model.md).

Settings are one row per registry key; the history is append-only; products and offers are typed
catalog data with no price column anywhere.
"""

from __future__ import annotations

from typing import Any, ClassVar

from django.contrib.postgres.fields import ArrayField
from django.db import models
from django.db.models import Q

from apps.accounts.models import User
from apps.common.models import UUIDv7Model


class AppendOnlyError(RuntimeError):
    """An update or delete of an append-only row."""


class LiveSetting(UUIDv7Model):
    """One registry key's current value (research R2). Type, range and rules live in `registry`."""

    key = models.CharField(max_length=64, unique=True)
    # JSON null is the value of an unset optional setting (`maintenance_until`).
    value = models.JSONField(null=True, blank=True)
    unused = models.BooleanField(default=False)
    updated_by = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        permissions = (("switch_maintenance", "Can pause the server's writes"),)
        verbose_name = "live setting"

    def __str__(self) -> str:
        return self.key


class LiveopsChange(UUIDv7Model):
    """One append-only change of a setting, a product or an offer (research R14)."""

    class Target(models.TextChoices):
        SETTING = "setting"
        PRODUCT = "product"
        OFFER = "offer"

    class Source(models.TextChoices):
        ADMIN = "admin"
        COMMAND = "command"
        IMPORT = "import"
        RESET = "reset"

    target = models.CharField(max_length=8, choices=Target.choices)
    key = models.CharField(max_length=64)
    old = models.JSONField(null=True, blank=True)
    new = models.JSONField(null=True, blank=True)
    source = models.CharField(max_length=8, choices=Source.choices)
    actor = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.PROTECT, related_name="liveops_changes"
    )
    note = models.CharField(max_length=500, blank=True)
    at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes: ClassVar[list[models.Index]] = [
            models.Index(fields=("target", "key"), name="liveops_change_target_key")
        ]
        ordering = ("-at", "-id")

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            raise AppendOnlyError("liveops changes are append-only")
        super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        raise AppendOnlyError("liveops changes are append-only")

    def __str__(self) -> str:
        return f"{self.target} {self.key}"


class StoreProduct(UUIDv7Model):
    """One in-app product and what it grants (B10 research R11, data-model.md "StoreProduct").

    A price is never stored here: it comes from the store (FR-021).
    """

    class Kind(models.TextChoices):
        CONSUMABLE = "consumable"
        NON_CONSUMABLE = "non_consumable"
        SUBSCRIPTION = "subscription"

    product_id = models.CharField(max_length=48, unique=True)
    kind = models.CharField(max_length=16, choices=Kind.choices)
    platforms = ArrayField(models.CharField(max_length=8), default=list)
    bonat = models.PositiveIntegerField(default=0)
    bonus_bonat = models.PositiveIntegerField(default=0)
    entitlement = models.CharField(max_length=32, blank=True)
    best_value = models.BooleanField(default=False)
    display_order = models.SmallIntegerField(default=0)
    active = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "store product"
        constraints = (
            models.CheckConstraint(
                condition=~Q(kind="consumable") | (Q(bonat__gt=0) & Q(entitlement="")),
                name="product_consumable_grants",
            ),
            models.CheckConstraint(
                condition=~Q(kind="non_consumable")
                | (Q(bonat=0) & Q(bonus_bonat=0) & ~Q(entitlement="")),
                name="product_non_consumable_grants",
            ),
            models.CheckConstraint(condition=~Q(platforms=[]), name="product_platforms_not_empty"),
            models.UniqueConstraint(
                fields=("best_value",),
                condition=Q(active=True, best_value=True),
                name="product_one_best_value",
            ),
        )

    def __str__(self) -> str:
        return self.product_id


class Offer(UUIDv7Model):
    """One offer for one product, with its validated rules (B10 research R12, offers.md)."""

    class Kind(models.TextChoices):
        STARTER = "starter"
        SALE = "sale"
        SEASON_PASS = "season_pass"  # noqa: S105 - a kind, not a secret
        OTHER = "other"

    class Status(models.TextChoices):
        SCHEDULED = "scheduled"
        ACTIVE = "active"
        EXPIRED = "expired"

    offer_id = models.SlugField(max_length=48, unique=True)
    kind = models.CharField(max_length=16, choices=Kind.choices)
    product = models.ForeignKey(StoreProduct, on_delete=models.PROTECT, related_name="offers")
    starts_at = models.DateTimeField()
    ends_at = models.DateTimeField(null=True, blank=True)
    priority = models.SmallIntegerField(default=0)
    rules = models.JSONField(default=list, blank=True)
    # Informational: listing filters on the times, never on the status (FR-027).
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.SCHEDULED)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = (
            models.CheckConstraint(
                condition=Q(ends_at__isnull=True) | Q(ends_at__gt=models.F("starts_at")),
                name="offer_ends_after_start",
            ),
        )
        indexes: ClassVar[list[models.Index]] = [
            models.Index(fields=("status", "starts_at"), name="offer_status_start")
        ]

    def __str__(self) -> str:
        return self.offer_id


class RemoteConfigCheck(UUIDv7Model):
    """One run of the daily Remote Config drift check (B10 research R8)."""

    class Status(models.TextChoices):
        OK = "ok"
        DRIFT = "drift"
        UNREACHABLE = "unreachable"
        NOT_CONFIGURED = "not_configured"

    ran_at = models.DateTimeField()
    status = models.CharField(max_length=16, choices=Status.choices)
    template_version = models.CharField(max_length=32, blank=True)
    drift = models.JSONField(default=list, blank=True)

    class Meta:
        verbose_name = "Remote Config check"
        ordering = ("-ran_at", "-id")
        indexes: ClassVar[list[models.Index]] = [
            models.Index(fields=("ran_at",), name="remote_config_ran_at")
        ]

    def __str__(self) -> str:
        return f"{self.ran_at:%Y-%m-%d %H:%M} {self.status}"
