"""The ad rewards (B07 data-model.md).

One `AdReward` per validly signed AdMob callback, written once with its outcome. Only `shown_at` is
set afterwards, and only rows that granted nothing are ever deleted. A granted row backs one or two
`LedgerEntry` rows (`ref_type = "ad_reward"`, `ref_id = id`); the ledger is the record of value.

Imports only `accounts` and `common`: `economy` imports this module (B07 plan, boundaries).
"""

from __future__ import annotations

from typing import Any

from django.db import models
from django.db.models import Q

from apps.common.models import UUIDv7Model

# The one field written after a row exists (`ad_reward_seen`).
MUTABLE = frozenset({"shown_at"})


class RewardRecordLocked(RuntimeError):
    """A programming error: a reward's record is written once, and a grant is never deleted."""


class AdRewardQuerySet(models.QuerySet["AdReward"]):
    def update(self, **kwargs: Any) -> int:
        if set(kwargs) - MUTABLE:
            raise RewardRecordLocked("an ad reward changes only shown_at")
        return super().update(**kwargs)

    def delete(self) -> tuple[int, dict[str, int]]:
        if self.filter(outcome=AdReward.Outcome.GRANTED).exists():
            raise RewardRecordLocked("a granted ad reward is never deleted")
        return super().delete()


class AdReward(UUIDv7Model):
    class Outcome(models.TextChoices):
        GRANTED = "granted"
        DUPLICATE_REFERENCE = "duplicate_reference"
        CAP_REACHED = "cap_reached"
        NOT_SERVER_PLACEMENT = "not_server_placement"
        MALFORMED = "malformed"
        EXPIRED = "expired"
        UNATTRIBUTED = "unattributed"

    transaction_id = models.CharField(max_length=128)
    player = models.ForeignKey(
        "accounts.Player",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="ad_rewards",
    )
    placement = models.CharField(max_length=32, blank=True)
    nonce = models.UUIDField(null=True, blank=True)
    custom_data = models.CharField(max_length=512, blank=True)
    ad_network = models.CharField(max_length=32, blank=True)
    ad_unit = models.CharField(max_length=64, blank=True)
    reward_amount = models.IntegerField()
    reward_item = models.CharField(max_length=64, blank=True)
    key_id = models.BigIntegerField()
    callback_at = models.DateTimeField(null=True, blank=True)
    outcome = models.CharField(max_length=24, choices=Outcome.choices)
    jenehat = models.PositiveIntegerField(default=0)
    bonat = models.PositiveIntegerField(default=0)
    game_date = models.DateField()
    created_at = models.DateTimeField()
    shown_at = models.DateTimeField(null=True, blank=True)

    objects = AdRewardQuerySet.as_manager()

    class Meta:
        constraints = (
            models.UniqueConstraint(fields=["transaction_id"], name="ad_reward_transaction_once"),
            models.UniqueConstraint(
                fields=["nonce"], condition=Q(nonce__isnull=False), name="ad_reward_nonce_once"
            ),
            models.CheckConstraint(
                condition=Q(outcome="granted") | Q(jenehat=0, bonat=0),
                name="ad_reward_amounts_only_when_granted",
            ),
            models.CheckConstraint(
                condition=~Q(outcome="granted") | Q(player__isnull=False),
                name="ad_reward_granted_has_player",
            ),
            models.CheckConstraint(
                condition=Q(shown_at__isnull=True) | Q(outcome="granted"),
                name="ad_reward_shown_only_when_granted",
            ),
        )
        indexes = (
            models.Index(
                fields=["player", "placement", "game_date"],
                condition=Q(outcome="granted"),
                name="ad_reward_daily_cap",
            ),
            models.Index(
                fields=["player", "created_at"],
                condition=Q(outcome="granted", shown_at__isnull=True),
                name="ad_reward_unseen",
            ),
            models.Index(
                fields=["created_at"], condition=~Q(outcome="granted"), name="ad_reward_prune"
            ),
        )

    def __str__(self) -> str:
        return f"{self.outcome} {self.created_at:%Y-%m-%d %H:%M}"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            stored: dict[str, Any] | None = type(self).objects.filter(pk=self.pk).values().first()  # type: ignore[assignment]
            if stored is not None:
                changed = {
                    f.attname
                    for f in self._meta.concrete_fields
                    if getattr(self, f.attname) != stored[f.attname]
                }
                if changed - MUTABLE:
                    raise RewardRecordLocked("an ad reward changes only shown_at")
        super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        if self.outcome == self.Outcome.GRANTED:
            raise RewardRecordLocked("a granted ad reward is never deleted")
        return super().delete(*args, **kwargs)
