"""The economy's own admin pages (contracts/admin.md): flags and their review, and read-only
lists of the ledger and the adjustments. The player page's blocks are in `player_page`.

Nothing here edits a balance or a ledger row; a mistake is corrected by an adjustment.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

from django import forms
from django.contrib import admin, messages
from django.contrib.admin import helpers
from django.contrib.admin.views.main import ChangeList
from django.db.models import QuerySet
from django.http import HttpRequest, HttpResponse
from django.template.response import TemplateResponse
from django.utils import timezone

from apps.economy.models import LedgerEntry, PlayerFlag, WalletAdjustment


class ReadOnlyAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False


@admin.register(LedgerEntry)
class LedgerEntryAdmin(ReadOnlyAdmin):
    list_display = (
        "created_at",
        "player",
        "currency",
        "delta",
        "balance_after",
        "reason",
        "source",
        "ref_type",
        "ref_id",
    )
    list_filter = ("currency", "reason", "source")
    list_select_related = ("player",)
    search_fields = ("=player__id",)
    search_help_text = "An exact player_id (the full UUID)."
    ordering = ("-created_at", "-id")


@admin.register(WalletAdjustment)
class WalletAdjustmentAdmin(ReadOnlyAdmin):
    list_display = ("at", "player", "currency", "delta", "reason", "actor")
    list_filter = ("currency",)
    list_select_related = ("player", "actor")
    search_fields = ("=player__id",)
    search_help_text = "An exact player_id (the full UUID)."
    ordering = ("-at",)


class ReviewedFilter(admin.SimpleListFilter):
    """Open flags by default: the list is a queue."""

    title = "reviewed"
    parameter_name = "reviewed"

    def lookups(self, request: HttpRequest, model_admin: Any) -> list[tuple[str, str]]:
        return [("no", "No"), ("yes", "Yes"), ("all", "All")]

    def queryset(self, request: HttpRequest, queryset: QuerySet[Any]) -> QuerySet[Any]:
        value = self.value() or "no"
        if value == "no":
            return queryset.filter(reviewed_at__isnull=True)
        if value == "yes":
            return queryset.filter(reviewed_at__isnull=False)
        return queryset

    def choices(self, changelist: ChangeList) -> Iterator[Any]:
        value = self.value() or "no"
        for lookup, title in self.lookup_choices:
            yield {
                "selected": value == lookup,
                "query_string": changelist.get_query_string({self.parameter_name: lookup}),
                "display": title,
            }


class ReviewForm(forms.Form):
    resolution = forms.CharField(
        max_length=200,
        widget=forms.Textarea(attrs={"rows": 3, "maxlength": 200}),
        help_text="What you found and decided. Kept with the flag.",
    )


@admin.register(PlayerFlag)
class PlayerFlagAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("player", "kind", "game_date", "count", "reviewed", "reviewed_by")
    list_filter = ("kind", ReviewedFilter, "game_date")
    list_select_related = ("player", "reviewed_by")
    search_fields = ("=player__id",)
    search_help_text = "An exact player_id (the full UUID)."
    ordering = ("-game_date", "kind")
    actions = ("mark_reviewed",)
    fields = (
        "player",
        "kind",
        "game_date",
        "details",
        "reviewed_by",
        "reviewed_at",
        "resolution",
        "created_at",
    )
    readonly_fields = fields

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        # Only the review action changes a flag; a flag's own page is read-only.
        return obj is None and super().has_change_permission(request)

    @admin.display(description="count")
    def count(self, flag: PlayerFlag) -> int:
        return int(flag.details.get("count", 1))

    @admin.display(description="reviewed", boolean=True)
    def reviewed(self, flag: PlayerFlag) -> bool:
        return flag.reviewed_at is not None

    @admin.action(description="Mark reviewed", permissions=["change"])
    def mark_reviewed(
        self, request: HttpRequest, queryset: QuerySet[PlayerFlag]
    ) -> HttpResponse | None:
        form = ReviewForm(request.POST if "apply" in request.POST else None)
        if form.is_bound and form.is_valid():
            selected = queryset.count()
            # The filter makes a review final, also against a second reviewer at the same time.
            done = queryset.filter(reviewed_at__isnull=True).update(
                reviewed_by=request.user,
                reviewed_at=timezone.now(),
                resolution=form.cleaned_data["resolution"],
            )
            self.message_user(request, f"{done} flag(s) marked reviewed.")
            if done < selected:
                self.message_user(
                    request,
                    f"{selected - done} flag(s) were already reviewed and stay as they were.",
                    messages.WARNING,
                )
            return None
        context = {
            **self.admin_site.each_context(request),
            "title": "Mark flags reviewed",
            "opts": self.model._meta,
            "form": form,
            "flags": queryset.select_related("player"),
            "selected": request.POST.getlist(helpers.ACTION_CHECKBOX_NAME),
            "action_checkbox_name": helpers.ACTION_CHECKBOX_NAME,
        }
        return TemplateResponse(request, "admin/economy/playerflag/review.html", context)
