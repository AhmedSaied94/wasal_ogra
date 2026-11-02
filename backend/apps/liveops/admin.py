"""The live-ops admin pages (B10 contracts/admin.md).

Every save of a setting goes through `apps.liveops.services.settings_admin`, so the registry's
ranges, the cross-setting rules and the history can't be skipped. The change history is read-only.
"""

from __future__ import annotations

from typing import Any, ClassVar, cast

from django import forms
from django.contrib import admin, messages
from django.core.exceptions import PermissionDenied
from django.db.models import QuerySet
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect
from django.template.response import TemplateResponse
from django.urls import path

from apps.accounts.models import User
from apps.liveops import registry
from apps.liveops.models import (
    LiveopsChange,
    LiveSetting,
    Offer,
    RemoteConfigCheck,
    StoreProduct,
)
from apps.liveops.services import catalog, maintenance, remote_config, settings_admin, versions
from apps.liveops.services import offers as offers_service

HISTORY_LIMIT = 50
# The two rows the Maintenance page and the `maintenance` command switch (FR-018, FR-033). They are
# never edited through the generic setting form: that would skip `maintenance.switch`.
MAINTENANCE_KEYS = frozenset({"maintenance_enabled", "maintenance_until"})


def display_value(value: Any) -> str:
    if value is None:
        return "—"
    if isinstance(value, bool):
        return "yes" if value else "no"
    return str(value)


class HistoryMixin:
    """A change page with the object's history below the form (contracts/admin.md)."""

    history_target: ClassVar[str] = ""

    def change_view(
        self,
        request: HttpRequest,
        object_id: str,
        form_url: str = "",
        extra_context: dict[str, Any] | None = None,
    ) -> TemplateResponse:
        context = {**(extra_context or {})}
        row = self.model._default_manager.filter(pk=object_id).first()  # type: ignore[attr-defined]
        if row is not None:
            key = getattr(row, "key", None) or getattr(row, "product_id", None) or row.offer_id
            context["history"] = list(
                LiveopsChange.objects.filter(target=self.history_target, key=key).select_related(
                    "actor"
                )[:HISTORY_LIMIT]
            )
        return cast(
            "TemplateResponse",
            super().change_view(request, object_id, form_url, context),  # type: ignore[misc]
        )


class LiveSettingForm(forms.ModelForm):  # type: ignore[type-arg]
    """The value field of one registry key, plus the note that goes in the history."""

    note = forms.CharField(
        max_length=500,
        required=False,
        widget=forms.Textarea(attrs={"rows": 2}),
        help_text="Why the change was made. Shown in the history.",
    )

    class Meta:
        model = LiveSetting
        fields = ("value",)

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self.spec = registry.get(self.instance.key)
        self.fields["value"] = _field(self.spec)

    def clean_value(self) -> Any:
        try:
            value = registry.validate(self.spec, self.cleaned_data["value"])
        except ValueError as refused:
            raise forms.ValidationError(str(refused)) from None
        try:
            registry.check_rules(
                settings_admin.candidate_for(self.spec.key, value), {self.spec.key}
            )
        except ValueError as refused:
            raise forms.ValidationError(str(refused)) from None
        return value


def _field(spec: registry.Spec) -> forms.Field:
    if spec.kind == registry.INT:
        return forms.IntegerField(
            min_value=spec.minimum,
            max_value=spec.maximum,
            help_text=f"{spec.meaning}. Range {spec.minimum} to {spec.maximum}"
            + (f", multiple of {spec.multiple_of}" if spec.multiple_of else "")
            + ".",
        )
    if spec.kind == registry.CHOICE:
        return forms.ChoiceField(choices=[(choice, choice) for choice in spec.choices])
    if spec.kind == registry.BOOL:
        return forms.BooleanField(required=False)
    if spec.kind == registry.DATETIME:
        return forms.DateTimeField(
            required=False,
            help_text="ISO-8601 UTC, such as 2026-11-03T15:30Z. Empty means no end.",
        )
    return forms.CharField(max_length=32, help_text="MAJOR.MINOR.PATCH, such as 1.3.0.")


class AppliedByFilter(admin.SimpleListFilter):
    title = "applied by"
    parameter_name = "applied_by"

    def lookups(self, request: HttpRequest, model_admin: Any) -> list[tuple[str, str]]:
        return [
            (registry.PHONE, "Phone"),
            (registry.SERVER, "Server"),
            (registry.BOTH, "Both"),
        ]

    def queryset(self, request: HttpRequest, queryset: QuerySet[Any]) -> QuerySet[Any]:
        if self.value() not in (registry.PHONE, registry.SERVER, registry.BOTH):
            return queryset
        keys = [spec.key for spec in registry.SPECS.values() if spec.applied_by == self.value()]
        return queryset.filter(key__in=keys)


class DriftedFilter(admin.SimpleListFilter):
    title = "drifted"
    parameter_name = "drifted"

    def lookups(self, request: HttpRequest, model_admin: Any) -> list[tuple[str, str]]:
        return [("yes", "Drifted"), ("no", "In step")]

    def queryset(self, request: HttpRequest, queryset: QuerySet[Any]) -> QuerySet[Any]:
        marks = set(remote_config.latest_marks())
        if self.value() == "yes":
            return queryset.filter(key__in=marks)
        if self.value() == "no":
            return queryset.exclude(key__in=marks)
        return queryset


class ChangedFromDefaultFilter(admin.SimpleListFilter):
    title = "changed from default"
    parameter_name = "changed"

    def lookups(self, request: HttpRequest, model_admin: Any) -> list[tuple[str, str]]:
        return [("yes", "Changed"), ("no", "At its default")]

    def queryset(self, request: HttpRequest, queryset: QuerySet[Any]) -> QuerySet[Any]:
        changed = [
            row.key
            for row in queryset
            if row.key in registry.SPECS
            and row.value != registry.validate(registry.get(row.key), registry.get(row.key).default)
        ]
        if self.value() == "yes":
            return queryset.filter(key__in=changed)
        if self.value() == "no":
            return queryset.exclude(key__in=changed)
        return queryset


class VersionsForm(forms.Form):
    platform = forms.ChoiceField(choices=[("android", "Android"), ("ios", "iOS")])
    minimum = forms.CharField(max_length=32, help_text="MAJOR.MINOR.PATCH, such as 1.3.0.")


class MaintenanceForm(forms.Form):
    until = forms.DateTimeField(
        required=False, help_text="ISO-8601 UTC, such as 2026-11-03T15:30Z. Empty means no end."
    )
    note = forms.CharField(max_length=500, required=False)


@admin.register(LiveSetting)
class LiveSettingAdmin(HistoryMixin, admin.ModelAdmin):  # type: ignore[type-arg]
    change_form_template = "liveops/livesetting/change_form.html"
    history_target = LiveopsChange.Target.SETTING
    form = LiveSettingForm
    change_form_template = "liveops/livesetting/change_form.html"
    list_display = (
        "key",
        "value_display",
        "default_display",
        "applied_by_display",
        "meaning",
        "drift_display",
        "last_change",
    )
    list_filter = (AppliedByFilter, ChangedFromDefaultFilter, DriftedFilter)
    search_fields = ("key",)
    ordering = ("key",)
    actions = ("reset_to_default",)

    def get_queryset(self, request: HttpRequest) -> QuerySet[LiveSetting]:
        return super().get_queryset(request).filter(unused=False)

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        """The maintenance pair is switched only by someone who may switch it (R1-3)."""
        if (
            obj is not None
            and getattr(obj, "key", None) in MAINTENANCE_KEYS
            and not request.user.has_perm("liveops.switch_maintenance")
        ):
            return False
        return super().has_change_permission(request, obj)

    @admin.display(description="value")
    def value_display(self, obj: LiveSetting) -> str:
        return display_value(obj.value)

    @admin.display(description="default")
    def default_display(self, obj: LiveSetting) -> str:
        spec = registry.SPECS.get(obj.key)
        return display_value(spec.default) if spec else "—"

    @admin.display(description="applied by")
    def applied_by_display(self, obj: LiveSetting) -> str:
        spec = registry.SPECS.get(obj.key)
        return spec.applied_by if spec else "—"

    @admin.display(description="meaning")
    def meaning(self, obj: LiveSetting) -> str:
        spec = registry.SPECS.get(obj.key)
        return spec.meaning if spec else "—"

    @admin.display(description="drift")
    def drift_display(self, obj: LiveSetting) -> str:
        entry = remote_config.latest_marks().get(obj.key)
        if not entry:
            return ""
        return f"Remote Config says {entry.get('remote_config')}"

    @admin.display(description="last change")
    def last_change(self, obj: LiveSetting) -> str:
        change = (
            LiveopsChange.objects.filter(target=LiveopsChange.Target.SETTING, key=obj.key)
            .select_related("actor")
            .first()
        )
        if change is None:
            return "—"
        actor = change.actor.username if change.actor else change.source
        return f"{change.at:%Y-%m-%d %H:%M} {actor}"

    def get_urls(self) -> list[Any]:
        custom = [
            path(
                "versions/",
                self.admin_site.admin_view(self.versions_view),
                name="liveops_livesetting_versions",
            ),
            path(
                "maintenance/",
                self.admin_site.admin_view(self.maintenance_view),
                name="liveops_livesetting_maintenance",
            ),
        ]
        return custom + super().get_urls()

    def versions_view(self, request: HttpRequest) -> HttpResponse:
        """The active players per version, and the share a proposed minimum would block."""
        if not self.has_view_permission(request):
            raise PermissionDenied
        form = VersionsForm(request.POST or None)
        context: dict[str, Any] = {
            **self.admin_site.each_context(request),
            "title": "App versions",
            "opts": self.model._meta,
            "form": form,
            "counts": {
                platform: versions.active_counts(platform) for platform in ("android", "ios")
            },
            "preview": None,
        }
        if request.method == "POST" and form.is_valid():
            platform = form.cleaned_data["platform"]
            key = f"min_client_version_{platform}"
            try:
                minimum = registry.validate(registry.get(key), form.cleaned_data["minimum"])
            except ValueError as refused:
                form.add_error("minimum", str(refused))
            else:
                if request.POST.get("confirm"):
                    if not self.has_change_permission(request):
                        raise PermissionDenied
                    try:
                        settings_admin.change_many(
                            {key: minimum},
                            cast("User | None", request.user),
                            note="from the versions page",
                        )
                    except ValueError as refused:
                        form.add_error("minimum", str(refused))
                    else:
                        self.message_user(request, f"The {platform} minimum is {minimum} now.")
                        return redirect("admin:liveops_livesetting_changelist")
                else:
                    count, share = versions.blocked(platform, minimum)
                    context["preview"] = {
                        "platform": platform,
                        "minimum": minimum,
                        "count": count,
                        "share": round(share * 100, 1),
                    }
        return TemplateResponse(request, "liveops/versions.html", context)

    def maintenance_view(self, request: HttpRequest) -> HttpResponse:
        """The state, and the switch the command also writes through (contracts/admin.md)."""
        if not request.user.has_perm("liveops.switch_maintenance"):
            raise PermissionDenied
        form = MaintenanceForm(request.POST or None)
        if request.method == "POST" and form.is_valid():
            action = request.POST.get("action")
            try:
                if action == "on":
                    maintenance.switch(
                        True,
                        form.cleaned_data["until"],
                        actor=cast("User | None", request.user),
                        note=form.cleaned_data.get("note", ""),
                    )
                elif action == "off":
                    maintenance.switch(
                        False,
                        actor=cast("User | None", request.user),
                        note=form.cleaned_data.get("note", ""),
                    )
                else:
                    form.add_error(None, "Pick on or off.")
            except ValueError as refused:
                form.add_error(None, str(refused))
            else:
                self.message_user(request, "The switch applies within 60 s.")
                return redirect("admin:liveops_livesetting_maintenance")
        return TemplateResponse(
            request,
            "liveops/maintenance.html",
            {
                **self.admin_site.each_context(request),
                "title": "Maintenance",
                "opts": self.model._meta,
                "form": form,
                "state": maintenance.state(),
            },
        )

    @admin.action(description="Reset to default", permissions=("change",))
    def reset_to_default(self, request: HttpRequest, queryset: QuerySet[LiveSetting]) -> None:
        can_switch = request.user.has_perm("liveops.switch_maintenance")
        for row in queryset:
            if row.key in MAINTENANCE_KEYS and not can_switch:
                self.message_user(request, f"{row.key}: use the Maintenance page.", messages.ERROR)
                continue
            try:
                settings_admin.reset(
                    row.key, cast("User | None", request.user), note="from the admin"
                )
            except ValueError as refused:
                self.message_user(request, f"{row.key}: {refused}", messages.ERROR)
            else:
                self.message_user(request, f"{row.key} is back at its default.", messages.SUCCESS)

    def save_model(self, request: HttpRequest, obj: LiveSetting, form: Any, change: bool) -> None:
        try:
            settings_admin.change(
                obj.key,
                form.cleaned_data["value"],
                cast("User | None", request.user),
                form.cleaned_data.get("note", ""),
            )
        except ValueError as refused:
            self.message_user(request, f"{obj.key}: {refused}", messages.ERROR)


class StoreProductForm(forms.ModelForm):  # type: ignore[type-arg]
    product_id = forms.ChoiceField(choices=[])
    platforms = forms.MultipleChoiceField(
        choices=[("android", "Android"), ("ios", "iOS")],
        help_text="The stores that sell it.",
    )
    note = forms.CharField(max_length=500, required=False, widget=forms.Textarea(attrs={"rows": 2}))

    class Meta:
        model = StoreProduct
        fields = ("product_id", *catalog.FIELDS)

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        field = cast("forms.ChoiceField", self.fields["product_id"])
        field.choices = [
            (product_id, product_id) for product_id in sorted(catalog.KNOWN_PRODUCT_IDS)
        ]
        if not self.instance._state.adding:
            self.fields["product_id"].disabled = True

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        if any(field in self.errors for field in catalog.FIELDS):
            return cleaned  # the field's own error is the answer; a refused amount is a field
        try:
            catalog.check_product({field: cleaned.get(field) for field in catalog.FIELDS})
        except ValueError as refused:
            raise forms.ValidationError(str(refused)) from None
        return cleaned


@admin.register(StoreProduct)
class StoreProductAdmin(HistoryMixin, admin.ModelAdmin):  # type: ignore[type-arg]
    form = StoreProductForm
    change_form_template = "liveops/history_change_form.html"
    history_target = LiveopsChange.Target.PRODUCT
    list_display = (
        "product_id",
        "kind",
        "bonat",
        "bonus_bonat",
        "entitlement",
        "best_value",
        "display_order",
        "active",
        "updated_at",
    )
    list_filter = ("kind", "active", "best_value")
    ordering = ("display_order", "product_id")

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def save_model(self, request: HttpRequest, obj: StoreProduct, form: Any, change: bool) -> None:
        values = {field: form.cleaned_data[field] for field in catalog.FIELDS}
        try:
            catalog.save_product(
                form.cleaned_data["product_id"],
                actor=cast("User | None", request.user),
                note=form.cleaned_data.get("note", ""),
                **values,
            )
        except ValueError as refused:
            self.message_user(request, f"{obj.product_id}: {refused}", messages.ERROR)


class OfferForm(forms.ModelForm):  # type: ignore[type-arg]
    product_id = forms.ChoiceField(choices=[])
    note = forms.CharField(max_length=500, required=False, widget=forms.Textarea(attrs={"rows": 2}))

    class Meta:
        model = Offer
        fields = (
            "offer_id",
            "kind",
            "starts_at",
            "ends_at",
            "priority",
            "rules",
            "status",
        )

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self.fields["product_id"] = forms.ChoiceField(
            choices=[
                (row.product_id, row.product_id)
                for row in StoreProduct.objects.order_by("display_order")
            ]
        )
        if not self.instance._state.adding:
            self.fields["product_id"].initial = self.instance.product.product_id
        self.fields["rules"].widget = forms.Textarea(attrs={"rows": 8})

    def clean_rules(self) -> list[dict[str, Any]]:
        try:
            return list(offers_service.validate_rules(self.cleaned_data["rules"]))
        except ValueError as refused:
            raise forms.ValidationError(str(refused)) from None

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        starts, ends = cleaned.get("starts_at"), cleaned.get("ends_at")
        if starts and ends and ends <= starts:
            self.add_error("ends_at", "The end must be after the start.")
        return cleaned


@admin.register(Offer)
class OfferAdmin(HistoryMixin, admin.ModelAdmin):  # type: ignore[type-arg]
    form = OfferForm
    change_form_template = "liveops/history_change_form.html"
    history_target = LiveopsChange.Target.OFFER
    list_display = (
        "offer_id",
        "kind",
        "product",
        "starts_at",
        "ends_at",
        "priority",
        "status",
    )
    list_filter = ("kind", "status")
    ordering = ("-priority", "starts_at")
    list_select_related = ("product",)

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def save_model(self, request: HttpRequest, obj: Offer, form: Any, change: bool) -> None:
        values = {
            "kind": form.cleaned_data["kind"],
            "product_id": form.cleaned_data["product_id"],
            "starts_at": form.cleaned_data["starts_at"],
            "ends_at": form.cleaned_data["ends_at"],
            "priority": form.cleaned_data["priority"],
            "rules": form.cleaned_data["rules"],
            "status": form.cleaned_data["status"],
        }
        try:
            offers_service.save_offer(
                form.cleaned_data["offer_id"],
                actor=cast("User | None", request.user),
                note=form.cleaned_data.get("note", ""),
                **values,
            )
        except ValueError as refused:
            self.message_user(request, f"{obj.offer_id}: {refused}", messages.ERROR)


@admin.register(LiveopsChange)
class LiveopsChangeAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("at", "target", "key", "old", "new", "source", "actor", "note")
    list_filter = ("target", "source")
    search_fields = ("key",)
    ordering = ("-at", "-id")
    list_select_related = ("actor",)

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def get_model_perms(self, request: HttpRequest) -> dict[str, bool]:
        return {"view": True}


@admin.register(RemoteConfigCheck)
class RemoteConfigCheckAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("ran_at", "status", "template_version", "drift")
    list_filter = ("status",)
    ordering = ("-ran_at", "-id")
    actions = None

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False
