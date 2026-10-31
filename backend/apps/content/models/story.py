"""Chapters and their comic scenes, rooms, items and family requests (data-model.md)."""

from __future__ import annotations

from typing import Any, ClassVar

from django.contrib.postgres.fields import ArrayField
from django.contrib.postgres.validators import ArrayMaxLengthValidator, ArrayMinLengthValidator
from django.core.exceptions import ValidationError
from django.core.validators import MinValueValidator, RegexValidator
from django.db import models
from django.db.models import Q
from wassal_content.models import ChapterId, GoalKind, RoomId, ScenePlaysKind, StoryCharacter

from apps.content.models.base import PermanentModel, TimestampedModel, choices, slug_validator
from apps.content.models.lines import Line, Vehicle
from apps.content.models.trips import Trip

PANELS_MIN, PANELS_MAX = 3, 5
VARIANTS_MAX = 3
AFTER_TRIP = ScenePlaysKind.AFTER_TRIP.value
RIDERS_MAX = 2
# The room's design space, which an item's slot fits inside (M10, V-R3).
ROOM_WIDTH, ROOM_HEIGHT = 358, 300


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
    # M10's presentation fields (contracts/content-fields.md "B04"). Blank is absent: the schema's
    # optional fields, and `goal_art` names a drawing the app ships.
    goal_art = models.CharField(max_length=48, blank=True, default="", db_default="")
    goal_line_speaker = models.CharField(
        max_length=32, blank=True, default="", db_default="", choices=choices(StoryCharacter)
    )
    goal_line_ar_eg = models.TextField(blank=True, default="", db_default="")
    goal_line_ar = models.TextField(blank=True, default="", db_default="")
    ready_line_ar_eg = models.TextField(blank=True, default="", db_default="")
    ready_line_ar = models.TextField(blank=True, default="", db_default="")
    tagline_ar_eg = models.TextField(blank=True, default="", db_default="")
    tagline_ar = models.TextField(blank=True, default="", db_default="")
    story_title_ar_eg = models.TextField(blank=True, default="", db_default="")
    story_title_ar = models.TextField(blank=True, default="", db_default="")
    story_condition_ar_eg = models.TextField(blank=True, default="", db_default="")
    story_condition_ar = models.TextField(blank=True, default="", db_default="")
    story_fail_reason_ar_eg = models.TextField(blank=True, default="", db_default="")
    story_fail_reason_ar = models.TextField(blank=True, default="", db_default="")

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
            # The goal card's line is a character's, with text, or neither (M10).
            models.CheckConstraint(
                condition=Q(goal_line_speaker="", goal_line_ar_eg="")
                | ~Q(goal_line_speaker="") & ~Q(goal_line_ar_eg=""),
                name="content_chapter_goal_line_speaker",
            ),
            # The story trip's own fields only exist on a chapter that has a story trip (V-C6).
            models.CheckConstraint(
                condition=Q(
                    story_title_ar_eg="", story_condition_ar_eg="", story_fail_reason_ar_eg=""
                )
                | Q(story_trip__isnull=False),
                name="content_chapter_story_fields_need_trip",
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
        if self.goal_line_speaker == "" and self.goal_line_ar_eg:
            errors["goal_line_speaker"] = "A line's text needs its speaker."
        if self.goal_line_speaker and not self.goal_line_ar_eg:
            errors["goal_line_ar_eg"] = "A speaker needs the line's text."
        if self.story_trip is None and (self.story_title_ar_eg or self.story_condition_ar_eg):
            errors["story_trip"] = "The story's fields need a story trip."
        # FR-056: the title is what presents a story trip, so a condition, a fail reason or a
        # rider without one is a half-written chapter the pack must not lose (R1-6).
        riders = self.pk is not None and self.riders.exists()
        if not self.story_title_ar_eg and (
            self.story_condition_ar_eg or self.story_fail_reason_ar_eg or riders
        ):
            errors["story_title_ar_eg"] = "The story trip's fields need its title."
        if errors:
            raise ValidationError(errors)


class StoryRider(TimestampedModel):
    """A story character riding in a seat the trip leaves empty (M10, V-C7).

    The chapter's `story_trip_info.riders`, in order. The trip definition is untouched, so no rule,
    fixture or parity change.
    """

    chapter = models.ForeignKey(Chapter, on_delete=models.CASCADE, related_name="riders")
    order = models.PositiveSmallIntegerField(validators=[MinValueValidator(1)])
    character = models.CharField(max_length=32, choices=choices(StoryCharacter))
    seat_id = models.CharField(
        max_length=8,
        validators=[
            RegexValidator(r"^(front|[A-D])_[rml]$", "Use a row and a column, for example A_l.")
        ],
    )
    comment_short_change = models.CharField(max_length=64, blank=True, default="", db_default="")
    comment_false_accusation = models.CharField(
        max_length=64, blank=True, default="", db_default=""
    )
    comment_fight = models.CharField(max_length=64, blank=True, default="", db_default="")
    comment_missed_stop = models.CharField(max_length=64, blank=True, default="", db_default="")
    comment_impatient = models.CharField(max_length=64, blank=True, default="", db_default="")

    class Meta:
        ordering: ClassVar[list[str]] = ["chapter", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(fields=["chapter", "order"], name="content_rider_order"),
            models.UniqueConstraint(fields=["chapter", "seat_id"], name="content_rider_seat"),
            models.CheckConstraint(
                condition=Q(order__gte=1, order__lte=RIDERS_MAX),
                name="content_rider_order_range",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.chapter_id}/{self.order}"

    def clean(self) -> None:
        super().clean()
        if self.chapter_id and self.order and self.order > RIDERS_MAX:
            raise ValidationError({"order": f"A story trip has at most {RIDERS_MAX} riders."})


class Scene(PermanentModel):
    permanent_kind = "scene"
    identifier_lookups = ("chapter__chapter_id", "scene_id")

    chapter = models.ForeignKey(Chapter, on_delete=models.CASCADE, related_name="scenes")
    scene_id = models.CharField(max_length=32, validators=[slug_validator])
    order = models.PositiveSmallIntegerField()
    # M10: the scene's name in the timeline and the album. Blank on a row from before the change.
    title_ar_eg = models.TextField(blank=True, default="", db_default="")
    title_ar = models.TextField(blank=True, default="", db_default="")
    panel_art = ArrayField(
        models.CharField(max_length=32, validators=[slug_validator]),
        size=PANELS_MAX,
        validators=[ArrayMinLengthValidator(PANELS_MIN), ArrayMaxLengthValidator(PANELS_MAX)],
    )
    # When the app plays the scene by itself (the pack's `plays`, M07); blank: M10's rules. The
    # database default keeps the previous release's inserts working (expand/contract).
    plays_kind = models.CharField(
        max_length=16, choices=choices(ScenePlaysKind), blank=True, default="", db_default=""
    )
    plays_trip = models.ForeignKey(
        Trip, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
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
            # A trip is named exactly when the scene plays after it.
            models.CheckConstraint(
                condition=Q(plays_kind=AFTER_TRIP, plays_trip__isnull=False)
                | ~Q(plays_kind=AFTER_TRIP) & Q(plays_trip__isnull=True),
                name="content_scene_plays_trip",
            ),
        ]

    def __str__(self) -> str:
        return self.scene_id

    def clean(self) -> None:
        super().clean()
        if self.plays_kind == AFTER_TRIP and self.plays_trip_id is None:
            raise ValidationError({"plays_trip": "An after_trip scene needs its trip."})
        if self.plays_kind != AFTER_TRIP and self.plays_trip_id is not None:
            raise ValidationError({"plays_trip": "Only an after_trip scene names a trip."})


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
    # M10: the room's drawing (blank: the app's fallback) and the line when it's finished.
    art = models.CharField(max_length=48, blank=True, default="", db_default="")
    done_line_ar_eg = models.TextField(blank=True, default="", db_default="")
    done_line_ar = models.TextField(blank=True, default="", db_default="")

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
    # M10: where the piece sits in the room's drawing, in its 358 x 300 design space, and
    # سلمى's line.
    slot_x = models.PositiveSmallIntegerField(default=0, db_default=0)
    slot_y = models.PositiveSmallIntegerField(default=0, db_default=0)
    slot_w = models.PositiveSmallIntegerField(default=0, db_default=0)
    slot_h = models.PositiveSmallIntegerField(default=0, db_default=0)
    comment_ar_eg = models.TextField(blank=True, default="", db_default="")
    comment_ar = models.TextField(blank=True, default="", db_default="")

    class Meta:
        ordering: ClassVar[list[str]] = ["room", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(fields=["room", "slug"], name="content_item_slug_per_room"),
            # V-R3: the piece fits inside the room. `0` is a slot not authored yet: the columns
            # are expand-only (existing rows take the default), so the constraint lets it pass and
            # the build's V-R3 refuses a pack that leaves a piece without a slot.
            models.CheckConstraint(
                condition=(Q(slot_w=0) | Q(slot_w__gte=24))
                & (Q(slot_h=0) | Q(slot_h__gte=24))
                & Q(slot_x__gte=0)
                & Q(slot_y__gte=0),
                name="content_item_slot_minimum",
            ),
            models.CheckConstraint(
                condition=Q(slot_w__lte=ROOM_WIDTH, slot_h__lte=ROOM_HEIGHT)
                & Q(slot_x__lte=ROOM_WIDTH - 24)
                & Q(slot_y__lte=ROOM_HEIGHT - 24),
                name="content_item_slot_bounds",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        if self.slot_x + self.slot_w > ROOM_WIDTH:
            raise ValidationError({"slot_w": f"x + w must be at most {ROOM_WIDTH}."})
        if self.slot_y + self.slot_h > ROOM_HEIGHT:
            raise ValidationError({"slot_h": f"y + h must be at most {ROOM_HEIGHT}."})

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
    # M10: the style's line in the piece sheet, when it has one.
    comment_ar_eg = models.TextField(blank=True, default="", db_default="")
    comment_ar = models.TextField(blank=True, default="", db_default="")

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
    # M10: who asks for it, from the design's characters.
    character = models.CharField(
        max_length=32, blank=True, default="", db_default="", choices=choices(StoryCharacter)
    )

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
