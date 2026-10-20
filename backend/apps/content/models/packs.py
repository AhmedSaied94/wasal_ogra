"""Packs and their records (data-model.md "Packs and their records", FR-020, FR-024-FR-039a)."""

from __future__ import annotations

from typing import Any, ClassVar

from django.core.validators import MinValueValidator, RegexValidator
from django.db import models
from django.db.models import Q
from django.utils import timezone

from apps.common.models import UUIDv7Model
from apps.content.errors import ImmutableError
from apps.content.models.base import TimestampedModel

CLIENT_VERSION_PATTERN = r"^[0-9]+\.[0-9]+\.[0-9]+$"


class Origin(models.TextChoices):
    BUILT = "built"
    PROMOTED = "promoted"


class Status(models.TextChoices):
    DRAFT = "draft"
    VALIDATED = "validated"
    PUBLISHED = "published"
    RETIRED = "retired"


class BuildState(models.TextChoices):
    QUEUED = "queued"
    RUNNING = "running"
    FINISHED = "finished"
    FAILED = "failed"


# data-model.md "State transitions". Any other status change is refused.
TRANSITIONS: dict[str, frozenset[str]] = {
    Status.DRAFT: frozenset({Status.DRAFT, Status.VALIDATED}),
    Status.VALIDATED: frozenset({Status.VALIDATED, Status.PUBLISHED}),
    Status.PUBLISHED: frozenset({Status.PUBLISHED, Status.RETIRED}),
    Status.RETIRED: frozenset({Status.RETIRED}),
}
STORED = frozenset({Status.PUBLISHED, Status.RETIRED})
# What a validated pack is: its content, file and report never change after validation.
FROZEN_ONCE_VALIDATED = (
    "pack_id",
    "version",
    "origin",
    "schema_version",
    "snapshot_at",
    "canonical_sha256",
    "sha256",
    "size",
    "file",
    "validation_report",
)
# Once published, only the minimum app version may change, plus the columns that move with status.
MUTABLE_ONCE_PUBLISHED = frozenset({"status", "min_client_version", "updated_at"})


class ContentChannel(TimestampedModel):
    """One row per `pack_id` (only `core` in the MVP, FR-034).

    Migration 0002 adds the database check: `current` is the highest published pack of the channel,
    and with nothing published it is empty.
    """

    pack_id = models.CharField(max_length=32, unique=True)
    last_assigned_version = models.PositiveIntegerField(default=0)
    # The highest `pack.json` version imported from `content/source` (research R7, input B).
    imported_version = models.PositiveIntegerField(default=0)
    current = models.ForeignKey(
        "content.ContentPack", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )

    def __str__(self) -> str:
        return self.pack_id


class ContentPack(TimestampedModel):
    pack_id = models.CharField(max_length=32)
    # Empty only while a build waits for its number (research R7: assigned when the build runs).
    version = models.PositiveIntegerField(null=True, blank=True, validators=[MinValueValidator(1)])
    origin = models.CharField(max_length=16, choices=Origin.choices)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.DRAFT)
    build_state = models.CharField(max_length=16, choices=BuildState.choices, blank=True)
    schema_version = models.CharField(max_length=16)
    snapshot_at = models.DateTimeField(null=True, blank=True)
    canonical_sha256 = models.CharField(max_length=64, blank=True)
    sha256 = models.CharField(max_length=64, blank=True)
    release_sha256 = models.CharField(max_length=64, blank=True)
    # The release record's bytes, kept so `content_files sync` can rewrite a lost file exactly.
    release_file = models.BinaryField(default=bytes, blank=True)
    size = models.PositiveIntegerField(default=0)
    file = models.BinaryField(default=bytes)
    validation_report = models.JSONField(default=dict, blank=True)
    min_client_version = models.CharField(
        max_length=32, validators=[RegexValidator(CLIENT_VERSION_PATTERN, "Use 1.2.3.")]
    )
    rollback_of = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    built_by = models.CharField(max_length=150, blank=True)
    built_at = models.DateTimeField(null=True, blank=True)
    published_by = models.CharField(max_length=150, blank=True)
    published_at = models.DateTimeField(null=True, blank=True)
    promoted_by = models.CharField(max_length=150, blank=True)
    promoted_at = models.DateTimeField(null=True, blank=True)
    failure_reason = models.TextField(blank=True)

    class Meta:
        ordering: ClassVar[list[str]] = ["pack_id", "-version"]
        permissions = (
            ("build_pack", "Can build a draft pack"),
            ("publish_pack", "Can publish a validated pack"),
            ("rollback_pack", "Can roll back to an earlier pack"),
            ("promote_pack", "Can promote a staging pack to production"),
            ("change_min_client_version", "Can change a pack's minimum app version"),
            ("import_content", "Can import content"),
            ("export_content", "Can export the current content"),
            ("review_speech", "Can review speech lines"),
        )
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(
                fields=["pack_id", "version"], name="content_pack_version_once"
            ),
            models.CheckConstraint(
                condition=Q(version__gte=1), name="content_pack_version_positive"
            ),
            models.CheckConstraint(
                condition=Q(origin=Origin.BUILT, build_state__in=BuildState.values)
                | Q(origin=Origin.PROMOTED, build_state=""),
                name="content_pack_build_state_for_built_packs",
            ),
            models.CheckConstraint(
                condition=~Q(status=Status.DRAFT) | Q(release_sha256=""),
                name="content_pack_draft_has_no_release",
            ),
            models.CheckConstraint(
                condition=~Q(status__in=sorted(STORED)) | ~Q(release_sha256=""),
                name="content_pack_stored_has_release",
            ),
            models.CheckConstraint(
                condition=Q(min_client_version__regex=CLIENT_VERSION_PATTERN),
                name="content_pack_min_client_version_pattern",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.pack_id}-{self.version or 'unnumbered'}"

    def save(self, *args: Any, **kwargs: Any) -> None:
        stored = None
        if not self._state.adding:
            stored = ContentPack._base_manager.filter(pk=self.pk).first()
        if stored is None:
            self._check_new()
        else:
            self._check_change(stored)
        super().save(*args, **kwargs)

    def _check_new(self) -> None:
        expected = Status.DRAFT if self.origin == Origin.BUILT else Status.PUBLISHED
        if self.status != expected:
            raise ImmutableError(f"a {self.origin} pack starts as {expected}, not {self.status}")

    def _check_change(self, stored: ContentPack) -> None:
        if self.status not in TRANSITIONS[stored.status]:
            raise ImmutableError(f"{self} can't go from {stored.status} to {self.status}")
        validating = self.status == Status.VALIDATED and stored.status == Status.DRAFT
        if validating and self.build_state != BuildState.FINISHED:
            raise ImmutableError(f"{self} can be validated only after its build finished")
        if stored.status == Status.DRAFT:
            return
        changed = {
            field.name
            for field in self._meta.concrete_fields
            if _value(self, field.attname) != _value(stored, field.attname)
        }
        frozen = changed & set(FROZEN_ONCE_VALIDATED)
        if stored.status in STORED:
            frozen |= changed - MUTABLE_ONCE_PUBLISHED
        if frozen:
            names = ", ".join(sorted(frozen))
            raise ImmutableError(f"{self} is {stored.status}, so {names} can't change")


def _value(instance: models.Model, attname: str) -> Any:
    value = getattr(instance, attname)
    return bytes(value) if isinstance(value, memoryview) else value


class PublishedIdentifier(UUIDv7Model):
    """An identifier some published pack contained, which is then permanent (FR-016).

    Stations, seats, scenes and variants are qualified: `line_hay/kobri`, `micro_old/A_l`,
    `ch1_first_job/intro`, `salon.nish/crystal`.
    """

    class Kind(models.TextChoices):
        LINE = "line"
        STATION = "station"
        VEHICLE = "vehicle"
        SEAT = "seat"
        TRIP = "trip"
        CHAPTER = "chapter"
        SCENE = "scene"
        ROOM = "room"
        ITEM = "item"
        VARIANT = "variant"
        REQUEST = "request"
        SPEECH_KEY = "speech_key"
        TASK = "task"

    kind = models.CharField(max_length=16, choices=Kind.choices)
    identifier = models.CharField(max_length=100)
    first_version = models.PositiveIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering: ClassVar[list[str]] = ["kind", "identifier"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(fields=["kind", "identifier"], name="content_identifier_once"),
        ]

    def __str__(self) -> str:
        return f"{self.kind} {self.identifier}"


class PackTripIndex(UUIDv7Model):
    """A trip of one of the last 5 published packs, for B02's lookups (FR-035, R12)."""

    pack = models.ForeignKey(ContentPack, on_delete=models.CASCADE, related_name="trip_index")
    version = models.PositiveIntegerField()
    trip_id = models.CharField(max_length=40)
    rev = models.PositiveIntegerField()
    definition = models.JSONField()
    max_earnings_jenehat = models.PositiveIntegerField()
    last_station_at_s = models.PositiveIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(fields=["version", "trip_id"], name="content_trip_index_key"),
        ]


class PackPriceIndex(UUIDv7Model):
    """A catalog price of one of the last 5 published packs (FR-035, R12)."""

    pack = models.ForeignKey(ContentPack, on_delete=models.CASCADE, related_name="price_index")
    version = models.PositiveIntegerField()
    sku_kind = models.CharField(max_length=16)
    sku_id = models.CharField(max_length=64)
    currency = models.CharField(max_length=8)
    amount = models.PositiveIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(
                fields=["version", "sku_kind", "sku_id"], name="content_price_index_key"
            ),
        ]


class ContentAuditRecord(UUIDv7Model):
    """Append-only (FR-038): `save()` refuses updates, and deletes are always refused."""

    class Action(models.TextChoices):
        PUBLISH = "publish"
        PROMOTE = "promote"
        ROLLBACK = "rollback"
        MIN_CLIENT_VERSION_CHANGE = "min_client_version_change"

    class Outcome(models.TextChoices):
        SUCCEEDED = "succeeded"
        FAILED = "failed"

    action = models.CharField(max_length=32, choices=Action.choices)
    outcome = models.CharField(max_length=16, choices=Outcome.choices)
    actor = models.CharField(max_length=150)
    at = models.DateTimeField(default=timezone.now)
    pack_id = models.CharField(max_length=32, blank=True)
    version = models.PositiveIntegerField(null=True, blank=True)
    sha256 = models.CharField(max_length=64, blank=True)
    details = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering: ClassVar[list[str]] = ["-at"]
        default_permissions = ("view",)

    def __str__(self) -> str:
        return f"{self.action} {self.pack_id}-{self.version} {self.outcome}"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            raise ImmutableError("the content audit log is append-only")
        super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        raise ImmutableError("the content audit log is append-only")
