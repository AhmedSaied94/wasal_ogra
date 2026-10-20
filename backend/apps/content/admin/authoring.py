"""Authoring pages (contracts/admin.md "Authoring pages").

Any active staff member can read. Changing needs the model permission and `CONTENT_ROLE=source`;
under `target` every authoring page is read-only for everyone (research R9).
"""

from __future__ import annotations

from typing import Any

from django import forms
from django.contrib import admin, messages
from django.contrib.admin.utils import NestedObjects
from django.core.exceptions import PermissionDenied
from django.db import models
from django.db.models import QuerySet
from django.http import HttpRequest

from apps.content.admin.common import TRIP_ID, is_staff, on_source
from apps.content.forms import (
    ContentForm,
    PermanenceFormSet,
    TripPassengerFormSet,
    TripStationFormSet,
    published_version,
)
from apps.content.models import (
    CatalogPrice,
    Chapter,
    DailyRewardDay,
    FamilyRequest,
    Item,
    ItemVariant,
    Line,
    PermanentModel,
    Room,
    Scene,
    SceneLine,
    Seat,
    SpeechLine,
    SpeechPool,
    Station,
    TaskTemplate,
    Trip,
    TripEvent,
    TripPassenger,
    TripStation,
    Vehicle,
)
from apps.content.services import review
from apps.content.widgets import arabic_widget, is_arabic_field


def permanence_problems(objs: Any) -> list[str]:
    """What a delete would remove that a published pack contains, cascades included."""
    collector = NestedObjects(using="default")
    collector.collect(objs)
    problems = []
    for instances in collector.data.values():
        for instance in instances:
            if not isinstance(instance, PermanentModel):
                continue
            version = published_version(instance)
            if version is not None:
                problems.append(
                    f"{instance.permanent_kind} {instance.stored_identifier()} is in published "
                    f"pack version {version}"
                )
    return sorted(problems)


class ContentAdminMixin:
    """Arabic widgets, reading for any staff member, writing only on `source`."""

    def formfield_for_dbfield(
        self, db_field: models.Field[Any, Any], request: HttpRequest, **kwargs: Any
    ) -> Any:
        if is_arabic_field(db_field.name):
            kwargs["widget"] = arabic_widget(db_field.name)
        return super().formfield_for_dbfield(db_field, request, **kwargs)  # type: ignore[misc]

    def has_module_permission(self, request: HttpRequest) -> bool:
        return is_staff(request)

    def has_view_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return is_staff(request)

    def has_add_permission(self, request: HttpRequest, *args: Any) -> bool:
        return on_source() and super().has_add_permission(request, *args)  # type: ignore[misc]

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return on_source() and super().has_change_permission(request, obj)  # type: ignore[misc]

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return on_source() and super().has_delete_permission(request, obj)  # type: ignore[misc]


class ContentModelAdmin(ContentAdminMixin, admin.ModelAdmin):  # type: ignore[type-arg]
    form = ContentForm

    def get_deleted_objects(self, objs: Any, request: HttpRequest) -> Any:
        """A delete that would remove a published identifier is refused, naming the version."""
        deleted, counts, perms_needed, protected = super().get_deleted_objects(objs, request)
        return deleted, counts, perms_needed, [*protected, *permanence_problems(objs)]


class ContentInline(ContentAdminMixin, admin.TabularInline):  # type: ignore[type-arg]
    form = ContentForm
    extra = 0
    formset = PermanenceFormSet


# -- lines and vehicles ---------------------------------------------------------------------------


class StationInline(ContentInline):
    model = Station
    fields = ("station_id", "name_ar_eg", "name_ar", "order")
    ordering = ("order",)


@admin.register(Line)
class LineAdmin(ContentModelAdmin):
    inlines = (StationInline,)
    list_display = ("line_id", "order", "unlock_kind", "difficulty_min", "difficulty_max")
    list_filter = ("unlock_kind",)
    search_fields = ("line_id", "stations__station_id")
    fields = (
        "line_id",
        "name_ar_eg",
        "name_ar",
        "order",
        "unlock_kind",
        "unlock_vehicle",
        "unlock_after_line",
        "difficulty_min",
        "difficulty_max",
    )


class SeatInline(ContentInline):
    model = Seat
    fields = ("seat_id",)


@admin.register(Vehicle)
class VehicleAdmin(ContentModelAdmin):
    inlines = (SeatInline,)
    list_display = ("vehicle_id", "order", "starter")
    fields = ("vehicle_id", "name_ar_eg", "name_ar", "starter", "order")


# -- trips ----------------------------------------------------------------------------------------


class TripStationInline(ContentInline):
    model = TripStation
    formset = TripStationFormSet
    fields = ("station", "at_seconds", "fare_piasters")


class TripPassengerInline(ContentInline):
    model = TripPassenger
    formset = TripPassengerFormSet
    fields = (
        "order",
        "passenger_id",
        "archetype",
        "skin",
        "seat",
        "board_station",
        "dest_station",
        "pays_at_seconds",
        "payment",
        "group_id",
        "group_size",
        "speech_keys",
    )
    ordering = ("order",)


class TripEventInline(ContentInline):
    model = TripEvent
    fields = (
        "order",
        "event_id",
        "at_seconds",
        "passenger_ids",
        "station_id",
        "amount_piasters",
        "seconds",
    )
    ordering = ("order",)


@admin.register(Trip)
class TripAdmin(ContentModelAdmin):
    inlines = (TripStationInline, TripPassengerInline, TripEventInline)
    list_display = ("trip_id", "kind", "vehicle", "rev", "max_earnings_jenehat")
    list_filter = ("line", "kind")
    list_select_related = ("line", "vehicle")
    search_fields = ("line__line_id",)
    readonly_fields = ("rev",)
    fieldsets = (
        (None, {"fields": ("line", "number", "vehicle", "kind", "seed", "rev")}),
        (
            "Rules",
            {
                "fields": (
                    "max_earnings_jenehat",
                    ("star_two", "star_three"),
                    "student_discount_pct",
                    "bag_fare_piasters",
                    "child_free_age",
                    "max_break_requests",
                )
            },
        ),
        (
            "Starting tray (count of each coin and note)",
            {
                "fields": (
                    ("tray_50", "tray_100", "tray_500", "tray_1000"),
                    ("tray_2000", "tray_5000", "tray_10000", "tray_20000"),
                )
            },
        ),
        ("Notes (never in a pack)", {"fields": ("author_notes",)}),
    )

    def get_search_results(
        self, request: HttpRequest, queryset: QuerySet[Trip], search_term: str
    ) -> tuple[QuerySet[Trip], bool]:
        match = TRIP_ID.match(search_term.strip())
        if match:
            return queryset.filter(line__line_id=match[1], number=int(match[2])), False
        return super().get_search_results(request, queryset, search_term)


# -- story ----------------------------------------------------------------------------------------


class SceneInline(ContentInline):
    model = Scene
    fields = ("scene_id", "order", "panel_art")
    show_change_link = True
    ordering = ("order",)


@admin.register(Chapter)
class ChapterAdmin(ContentModelAdmin):
    inlines = (SceneInline,)
    list_display = ("chapter_id", "order", "goal_kind", "completion_bonat")
    fields = (
        "chapter_id",
        "order",
        "title_ar_eg",
        "title_ar",
        "goal_kind",
        "goal_line",
        "goal_vehicle",
        "goal_room",
        "story_trip",
        "completion_bonat",
    )


class SceneLineInline(ContentInline):
    model = SceneLine
    fields = ("panel", "order", "speaker", "text_ar_eg", "text_ar")
    ordering = ("panel", "order")


@admin.register(Scene)
class SceneAdmin(ContentModelAdmin):
    inlines = (SceneLineInline,)
    list_display = ("scene_id", "chapter", "order")
    list_filter = ("chapter",)
    fields = ("chapter", "scene_id", "order", "panel_art")


@admin.register(Room)
class RoomAdmin(ContentModelAdmin):
    list_display = ("room_id", "order", "chapter", "completion_bonat")
    fields = ("room_id", "name_ar_eg", "name_ar", "chapter", "order", "completion_bonat")


class ItemVariantInline(ContentInline):
    model = ItemVariant
    fields = ("variant_id", "name_ar_eg", "name_ar", "art", "order")
    ordering = ("order",)
    max_num = 3


@admin.register(Item)
class ItemAdmin(ContentModelAdmin):
    inlines = (ItemVariantInline,)
    list_display = ("item_id", "room", "order")
    list_filter = ("room",)
    list_select_related = ("room",)
    fields = ("room", "slug", "name_ar_eg", "name_ar", "order")


class FamilyRequestForm(ContentForm):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        field = self.fields.get("variant")
        if isinstance(field, forms.ModelChoiceField):
            item_id = self.instance.item_id if self.instance.pk else None
            variants = ItemVariant.objects.all()
            field.queryset = variants.filter(item_id=item_id) if item_id else variants.none()


@admin.register(FamilyRequest)
class FamilyRequestAdmin(ContentModelAdmin):
    form = FamilyRequestForm
    list_display = ("request_id", "room", "item", "reward_bonat")
    fields = ("request_id", "room", "item", "variant", "text_ar_eg", "text_ar", "reward_bonat")


# -- speech and economy ---------------------------------------------------------------------------


class SpeechLineInline(ContentInline):
    model = SpeechLine
    fields = ("order", "text_ar_eg", "text_ar", "reviewed_by", "reviewed_at")
    readonly_fields = ("reviewed_by", "reviewed_at")
    ordering = ("order",)


class UnreviewedFilter(admin.SimpleListFilter):
    title = "review"
    parameter_name = "unreviewed"

    def lookups(self, request: HttpRequest, model_admin: Any) -> list[tuple[str, str]]:
        return [("yes", "Has unreviewed lines"), ("no", "Every line reviewed")]

    def queryset(self, request: HttpRequest, queryset: QuerySet[Any]) -> QuerySet[Any]:
        if self.value() == "yes":
            return queryset.filter(lines__reviewed_by="").distinct()
        if self.value() == "no":
            return queryset.exclude(lines__reviewed_by="")
        return queryset


class ReviewActionsMixin:
    def has_review_permission(self, request: HttpRequest) -> bool:
        return on_source() and request.user.has_perm("content.review_speech")

    def review(self, request: HttpRequest, lines: QuerySet[SpeechLine]) -> None:
        try:
            count = review.review_lines(lines, request.user)  # type: ignore[arg-type]
        except PermissionDenied as error:
            self.message_user(request, str(error), messages.ERROR)  # type: ignore[attr-defined]
            return
        self.message_user(request, f"Marked {count} line(s) reviewed.")  # type: ignore[attr-defined]


@admin.register(SpeechPool)
class SpeechPoolAdmin(ReviewActionsMixin, ContentModelAdmin):
    inlines = (SpeechLineInline,)
    list_display = ("speech_key",)
    list_filter = (UnreviewedFilter,)
    search_fields = ("speech_key",)
    fields = ("speech_key", "author_notes")
    actions = ("mark_reviewed",)

    @admin.action(description="Mark reviewed (every line)", permissions=["review"])
    def mark_reviewed(self, request: HttpRequest, queryset: QuerySet[SpeechPool]) -> None:
        self.review(request, SpeechLine.objects.filter(pool__in=queryset).order_by("pool", "order"))


@admin.register(SpeechLine)
class SpeechLineAdmin(ReviewActionsMixin, ContentModelAdmin):
    list_display = ("pool", "order", "text_ar_eg", "reviewed_by", "reviewed_at")
    list_filter = ("pool",)
    list_select_related = ("pool",)
    readonly_fields = ("reviewed_by", "reviewed_at")
    fields = ("pool", "order", "text_ar_eg", "text_ar", "reviewed_by", "reviewed_at")
    actions = ("mark_reviewed",)

    @admin.action(description="Mark reviewed", permissions=["review"])
    def mark_reviewed(self, request: HttpRequest, queryset: QuerySet[SpeechLine]) -> None:
        self.review(request, queryset.order_by("pool", "order"))


@admin.register(CatalogPrice)
class CatalogPriceAdmin(ContentModelAdmin):
    list_display = ("sku_kind", "sku_id", "currency", "amount")
    list_filter = ("sku_kind", "currency")
    search_fields = ("sku_id",)


@admin.register(DailyRewardDay)
class DailyRewardDayAdmin(ContentModelAdmin):
    list_display = ("day_index", "jenehat", "bonat")


@admin.register(TaskTemplate)
class TaskTemplateAdmin(ContentModelAdmin):
    list_display = ("task_id", "metric", "target", "active")
    list_filter = ("active",)
