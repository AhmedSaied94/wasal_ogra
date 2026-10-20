"""Speech pools, the catalog, the daily reward and task templates (data-model.md)."""

from __future__ import annotations

from typing import Any, ClassVar

from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator, RegexValidator
from django.db import models
from django.db.models import Q
from wassal_content.models import Currency, SkuKind
from wassal_content.rules import JENEHAT_KINDS

from apps.content.models.base import PermanentModel, TimestampedModel, choices

SPEECH_KEY_PATTERN = r"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$"
DAYS = 7


class SpeechPool(PermanentModel):
    permanent_kind = "speech_key"
    identifier_lookups = ("speech_key",)

    speech_key = models.CharField(
        max_length=64,
        unique=True,
        validators=[
            RegexValidator(SPEECH_KEY_PATTERN, "Use dotted lowercase words: wants.change.")
        ],
    )
    author_notes = models.TextField(blank=True)

    class Meta:
        ordering: ClassVar[list[str]] = ["speech_key"]

    def __str__(self) -> str:
        return self.speech_key


class SpeechLine(TimestampedModel):
    """`save()` clears the review whenever either text changes (FR-017).

    Only `services.review.review_lines` sets a review. Usernames are text, not a foreign key, so
    the content tables restore without the staff table (R8).
    """

    pool = models.ForeignKey(SpeechPool, on_delete=models.CASCADE, related_name="lines")
    order = models.PositiveSmallIntegerField()
    text_ar_eg = models.TextField()
    text_ar = models.TextField(blank=True)
    reviewed_by = models.CharField(max_length=150, blank=True, editable=False)
    reviewed_at = models.DateTimeField(null=True, blank=True, editable=False)

    class Meta:
        ordering: ClassVar[list[str]] = ["pool", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(fields=["pool", "order"], name="content_speech_line_order"),
            models.CheckConstraint(
                condition=Q(reviewed_by="", reviewed_at=None)
                | (~Q(reviewed_by="") & ~Q(reviewed_at=None)),
                name="content_speech_line_review_complete",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.pool_id}#{self.order}"

    @property
    def is_reviewed(self) -> bool:
        return bool(self.reviewed_by)

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding and self.is_reviewed:
            stored = (
                SpeechLine._base_manager.filter(pk=self.pk)
                .values_list("text_ar_eg", "text_ar")
                .first()
            )
            if stored is not None and stored != (self.text_ar_eg, self.text_ar):
                self.reviewed_by, self.reviewed_at = "", None
                if kwargs.get("update_fields") is not None:
                    kwargs["update_fields"] = {
                        *kwargs["update_fields"],
                        "reviewed_by",
                        "reviewed_at",
                    }
        super().save(*args, **kwargs)


class CatalogPrice(TimestampedModel):
    """The currency follows the kind (V-M1): JENEHAT for items, vehicles and chapters."""

    sku_kind = models.CharField(max_length=16, choices=choices(SkuKind))
    sku_id = models.CharField(max_length=64)
    currency = models.CharField(max_length=8, choices=choices(Currency))
    amount = models.PositiveIntegerField(validators=[MinValueValidator(1)])

    class Meta:
        ordering: ClassVar[list[str]] = ["sku_kind", "sku_id"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(fields=["sku_kind", "sku_id"], name="content_price_per_sku"),
            models.CheckConstraint(condition=Q(amount__gte=1), name="content_price_amount"),
            models.CheckConstraint(
                condition=Q(sku_kind__in=sorted(JENEHAT_KINDS), currency=Currency.JENEHAT.value)
                | (~Q(sku_kind__in=sorted(JENEHAT_KINDS)) & Q(currency=Currency.BONAT.value)),
                name="content_price_currency_follows_kind",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.sku_kind}:{self.sku_id}"

    @staticmethod
    def currency_for(sku_kind: str) -> str:
        return Currency.JENEHAT.value if sku_kind in JENEHAT_KINDS else Currency.BONAT.value

    def clean(self) -> None:
        super().clean()
        if self.sku_kind and self.currency != self.currency_for(self.sku_kind):
            raise ValidationError(
                {"currency": f"A {self.sku_kind} is priced in {self.currency_for(self.sku_kind)}."}
            )


class DailyRewardDay(TimestampedModel):
    day_index = models.PositiveSmallIntegerField(
        unique=True, validators=[MinValueValidator(1), MaxValueValidator(DAYS)]
    )
    jenehat = models.PositiveIntegerField(default=0)
    bonat = models.PositiveIntegerField(default=0)

    class Meta:
        ordering: ClassVar[list[str]] = ["day_index"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.CheckConstraint(
                condition=Q(day_index__gte=1, day_index__lte=DAYS), name="content_daily_day_index"
            ),
            models.CheckConstraint(
                condition=Q(jenehat__gt=0) | Q(bonat__gt=0), name="content_daily_reward_positive"
            ),
        ]

    def __str__(self) -> str:
        return f"day {self.day_index}"


class TaskTemplate(PermanentModel):
    permanent_kind = "task"
    identifier_lookups = ("task_id",)

    task_id = models.CharField(
        max_length=45,
        unique=True,
        validators=[RegexValidator(r"^task_[a-z0-9_]{1,40}$", "Use task_ and 1-40 characters.")],
    )
    metric = models.CharField(
        max_length=41,
        validators=[
            RegexValidator(r"^[a-z][a-z0-9_]{1,40}$", "Use 2-41 lowercase letters, digits or _.")
        ],
    )
    target = models.PositiveIntegerField(validators=[MinValueValidator(1)])
    text_ar_eg = models.TextField()
    text_ar = models.TextField(blank=True)
    reward_jenehat = models.PositiveIntegerField(default=0)
    reward_bonat = models.PositiveIntegerField(default=0)
    active = models.BooleanField(default=True)

    class Meta:
        ordering: ClassVar[list[str]] = ["task_id"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.CheckConstraint(condition=Q(target__gte=1), name="content_task_target"),
            models.CheckConstraint(
                condition=Q(reward_jenehat__gt=0) | Q(reward_bonat__gt=0),
                name="content_task_reward_positive",
            ),
        ]

    def __str__(self) -> str:
        return self.task_id
