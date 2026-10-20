"""Chapters and their comic scenes, rooms, items and family requests (data-model.md)."""

from __future__ import annotations

from typing import Any, ClassVar

from django.contrib.postgres.fields import ArrayField
from django.contrib.postgres.validators import ArrayMaxLengthValidator, ArrayMinLengthValidator
from django.core.exceptions import ValidationError
from django.core.validators import MinValueValidator, RegexValidator
from django.db import models
from django.db.models import Q
from wassal_content.models import ChapterId, GoalKind, RoomId

from apps.content.models.base import PermanentModel, TimestampedModel, choices, slug_validator
from apps.content.models.lines import Line, Vehicle
from apps.content.models.trips import Trip

PANELS_MIN, PANELS_MAX = 3, 5
VARIANTS_MAX = 3


class Chapter(PermanentModel):
    permanent_kind = "chapter"
    identifier_lookups = ("chapter_id",)

    chapter_id = models.CharField(max_length=32, unique=True, choices=choices(ChapterId))
    order = models.PositiveSmallIntegerField(unique=True)
    title_ar_eg = models.TextField()
    title_ar = models.TextField(blank=True)
    goal_kind = models.CharField(max_length=16, choices=choices(GoalKind))
    goal_line = models.ForeignKey(
        Line, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    goal_vehicle = models.ForeignKey(
        Vehicle, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    goal_room = models.ForeignKey(
        "content.Room", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    story_trip = models.ForeignKey(
        Trip, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    completion_bonat = models.PositiveIntegerField(default=0)

    class Meta:
        ordering: ClassVar[list[str]] = ["order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.CheckConstraint(
                condition=(
                    Q(goal_kind="complete_line", goal_vehicle=None, goal_room=None)
                    & ~Q(goal_line=None)
                    | Q(goal_kind="own_vehicle", goal_line=None, goal_room=None)
                    & ~Q(goal_vehicle=None)
                    | Q(goal_kind="complete_room", goal_line=None, goal_vehicle=None)
                    & ~Q(goal_room=None)
                    | Q(goal_kind="purchase", goal_line=None, goal_vehicle=None, goal_room=None)
                ),
                name="content_chapter_goal_matches_kind",
            ),
        ]

    def __str__(self) -> str:
        return self.chapter_id

    GOAL_FIELDS: ClassVar[dict[str, str]] = {
        GoalKind.COMPLETE_LINE.value: "goal_line",
        GoalKind.OWN_VEHICLE.value: "goal_vehicle",
        GoalKind.COMPLETE_ROOM.value: "goal_room",
    }

    def clean(self) -> None:
        super().clean()
        errors: dict[str, str] = {}
        needed = self.GOAL_FIELDS.get(self.goal_kind)
        for name in self.GOAL_FIELDS.values():
            is_set = getattr(self, f"{name}_id") is not None
            if name == needed and not is_set:
                errors[name] = f"A {self.goal_kind} goal needs this."
            elif name != needed and is_set:
                errors[name] = f"A {self.goal_kind} goal doesn't use this."
        if self.story_trip is not None and self.story_trip.kind != "story":
            errors["story_trip"] = "Choose a story trip."
        if errors:
            raise ValidationError(errors)


class Scene(PermanentModel):
    permanent_kind = "scene"
    identifier_lookups = ("chapter__chapter_id", "scene_id")

    chapter = models.ForeignKey(Chapter, on_delete=models.CASCADE, related_name="scenes")
    scene_id = models.CharField(max_length=32, validators=[slug_validator])
    order = models.PositiveSmallIntegerField()
    panel_art = ArrayField(
        models.CharField(max_length=32, validators=[slug_validator]),
        size=PANELS_MAX,
        validators=[ArrayMinLengthValidator(PANELS_MIN), ArrayMaxLengthValidator(PANELS_MAX)],
    )

    class Meta:
        ordering: ClassVar[list[str]] = ["chapter", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(
                fields=["chapter", "scene_id"], name="content_scene_id_per_chapter"
            ),
            models.UniqueConstraint(
                fields=["chapter", "order"], name="content_scene_order_per_chapter"
            ),
            models.CheckConstraint(
                condition=Q(panel_art__len__gte=PANELS_MIN, panel_art__len__lte=PANELS_MAX),
                name="content_scene_panel_count",
            ),
        ]

    def __str__(self) -> str:
        return self.scene_id


class SceneLine(TimestampedModel):
    scene = models.ForeignKey(Scene, on_delete=models.CASCADE, related_name="lines")
    panel = models.PositiveSmallIntegerField(validators=[MinValueValidator(1)])
    order = models.PositiveSmallIntegerField()
    speaker = models.CharField(max_length=32, validators=[slug_validator])
    text_ar_eg = models.TextField()
    text_ar = models.TextField(blank=True)

    class Meta:
        ordering: ClassVar[list[str]] = ["scene", "panel", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(
                fields=["scene", "panel", "order"], name="content_scene_line_order_per_panel"
            ),
            models.CheckConstraint(condition=Q(panel__gte=1), name="content_scene_line_panel"),
        ]

    def __str__(self) -> str:
        return f"{self.speaker} ({self.panel})"

    def clean(self) -> None:
        super().clean()
        if self.scene_id and self.panel and self.panel > len(self.scene.panel_art):
            raise ValidationError({"panel": "The scene has fewer panels."})


class Room(PermanentModel):
    permanent_kind = "room"
    identifier_lookups = ("room_id",)

    room_id = models.CharField(max_length=32, unique=True, choices=choices(RoomId))
    name_ar_eg = models.TextField()
    name_ar = models.TextField(blank=True)
    chapter = models.ForeignKey(Chapter, on_delete=models.PROTECT, related_name="rooms")
    order = models.PositiveSmallIntegerField(unique=True)
    completion_bonat = models.PositiveIntegerField(default=0)

    class Meta:
        ordering: ClassVar[list[str]] = ["order"]

    def __str__(self) -> str:
        return self.room_id


class Item(PermanentModel):
    """`item_id` is `<room_id>.<slug>`, priced in JENEHAT in the catalog."""

    permanent_kind = "item"
    identifier_lookups = ("room__room_id", "slug")

    room = models.ForeignKey(Room, on_delete=models.PROTECT, related_name="items")
    slug = models.CharField(max_length=32, validators=[slug_validator])
    name_ar_eg = models.TextField()
    name_ar = models.TextField(blank=True)
    order = models.PositiveSmallIntegerField()

    class Meta:
        ordering: ClassVar[list[str]] = ["room", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(fields=["room", "slug"], name="content_item_slug_per_room"),
        ]

    @classmethod
    def format_identifier(cls, parts: tuple[Any, ...]) -> str:
        return ".".join(str(part) for part in parts)

    @property
    def item_id(self) -> str:
        return self.permanent_identifier()

    def __str__(self) -> str:
        return self.item_id


class ItemVariant(PermanentModel):
    permanent_kind = "variant"
    identifier_lookups = ("item__room__room_id", "item__slug", "variant_id")

    item = models.ForeignKey(Item, on_delete=models.CASCADE, related_name="variants")
    variant_id = models.CharField(max_length=32, validators=[slug_validator])
    name_ar_eg = models.TextField()
    name_ar = models.TextField(blank=True)
    art = models.CharField(max_length=32, validators=[slug_validator])
    order = models.PositiveSmallIntegerField()

    class Meta:
        ordering: ClassVar[list[str]] = ["item", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(
                fields=["item", "variant_id"], name="content_variant_id_per_item"
            ),
        ]

    @classmethod
    def format_identifier(cls, parts: tuple[Any, ...]) -> str:
        room_id, slug, variant_id = parts
        return f"{room_id}.{slug}/{variant_id}"

    def __str__(self) -> str:
        return self.variant_id

    def clean(self) -> None:
        super().clean()
        if self.item_id is None:
            return
        others = ItemVariant.objects.filter(item_id=self.item_id).exclude(pk=self.pk)
        if others.count() >= VARIANTS_MAX:
            raise ValidationError(f"An item has at most {VARIANTS_MAX} variants.")


class FamilyRequest(PermanentModel):
    permanent_kind = "request"
    identifier_lookups = ("request_id",)

    request_id = models.CharField(
        max_length=44,
        unique=True,
        validators=[RegexValidator(r"^req_[a-z0-9_]{1,40}$", "Use req_ and 1-40 characters.")],
    )
    room = models.ForeignKey(Room, on_delete=models.PROTECT, related_name="family_requests")
    item = models.ForeignKey(Item, on_delete=models.PROTECT, related_name="family_requests")
    variant = models.ForeignKey(
        ItemVariant, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    text_ar_eg = models.TextField()
    text_ar = models.TextField(blank=True)
    reward_bonat = models.PositiveIntegerField(validators=[MinValueValidator(1)])

    class Meta:
        ordering: ClassVar[list[str]] = ["request_id"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.CheckConstraint(condition=Q(reward_bonat__gte=1), name="content_request_reward"),
        ]

    def __str__(self) -> str:
        return self.request_id

    def clean(self) -> None:
        super().clean()
        if self.item_id and self.room_id and self.item.room_id != self.room_id:
            raise ValidationError({"item": "Choose an item of this room."})
        if self.variant is not None and self.item_id and self.variant.item_id != self.item_id:
            raise ValidationError({"variant": "Choose a variant of this item."})
