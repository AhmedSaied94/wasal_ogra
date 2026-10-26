"""Admin for staff accounts, and the read-only player pages for support (B02 contracts/admin.md).

There is no email or name to show for staff (data-model "accounts.User"). A player page never shows
a token, the install id or its hash, a provider subject or a session token id. B03 adds the
economy's blocks and the balance adjustment to the player page (`apps.economy.player_page`) and the
name filter (B03 contracts/admin.md).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from django import forms
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import AdminUserCreationForm, UserChangeForm
from django.http import HttpRequest, HttpResponse
from django.urls import URLPattern, path
from django.utils import formats, timezone

from apps.accounts.models import Device, NameFilterEntry, Player, User
from apps.accounts.services.names import normalize
from apps.accounts.services.sessions import live_sessions
from apps.economy import player_page

# The stubs make these classes generic, but Django can't subscript them at runtime. The stubs also
# tie UserAdmin to AbstractUser, and this User extends AbstractBaseUser, so mypy sees ModelAdmin.
if TYPE_CHECKING:
    _ChangeForm = UserChangeForm[User]
    _UserAdmin = admin.ModelAdmin[User]
else:
    _ChangeForm = UserChangeForm
    _UserAdmin = BaseUserAdmin


class UserChangeAdminForm(_ChangeForm):
    class Meta:
        model = User
        fields = ("username", "password", "is_active", "is_staff", "is_superuser")


class UserCreationAdminForm(AdminUserCreationForm):
    class Meta:
        model = User
        fields = ("username",)


@admin.register(User)
class UserAdmin(_UserAdmin):
    form = UserChangeAdminForm
    add_form = UserCreationAdminForm
    list_display = ("username", "is_staff", "is_superuser", "is_active", "last_login")
    list_filter = ("is_staff", "is_superuser", "is_active")
    search_fields = ("username",)
    ordering = ("username",)
    readonly_fields = ("last_login", "date_joined")
    filter_horizontal = ("groups", "user_permissions")
    fieldsets = (
        (None, {"fields": ("username", "password")}),
        (
            "Permissions",
            {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")},
        ),
        ("Dates", {"fields": ("last_login", "date_joined")}),
    )
    add_fieldsets = (
        (
            None,
            {
                "classes": ("wide",),
                "fields": ("username", "usable_password", "password1", "password2"),
            },
        ),
    )


class DeviceInline(admin.TabularInline):  # type: ignore[type-arg]
    model = Device
    fields = ("id", "platform", "app_version", "created_at", "last_seen_at")
    readonly_fields = fields
    extra = 0
    can_delete = False
    show_change_link = False

    def has_add_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False


@admin.register(Player)
class PlayerAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    """Support looks a player up by the id they read out; only the tester flag changes (US5)."""

    change_form_template = "admin/accounts/player/change_form.html"
    list_display = (
        "id",
        "status",
        "platform",
        "client_version",
        "is_tester",
        "created_at",
        "last_seen_at",
    )
    list_filter = ("status", "platform", "is_tester")
    search_fields = ("=id",)
    search_help_text = "An exact player_id (the full UUID)."
    actions = None
    inlines = (DeviceInline,)
    fieldsets = (
        (
            "Account",
            {
                "fields": (
                    "id",
                    "status",
                    "display_name",
                    "locale",
                    "country",
                    "platform",
                    "client_version",
                    "driver_level",
                    "created_at",
                    "last_seen_at",
                )
            },
        ),
        ("Testing", {"fields": ("is_tester",)}),
        ("Sign-in", {"fields": ("providers", "live_sessions")}),
    )
    readonly_fields = (
        "id",
        "status",
        "display_name",
        "locale",
        "country",
        "platform",
        "client_version",
        "driver_level",
        "created_at",
        "last_seen_at",
        "providers",
        "live_sessions",
    )

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def get_urls(self) -> list[URLPattern]:
        return [
            path(
                "<path:object_id>/adjust/",
                self.admin_site.admin_view(self.adjust_view),
                name="accounts_player_adjust",
            ),
            *super().get_urls(),
        ]

    def change_view(
        self,
        request: HttpRequest,
        object_id: str,
        form_url: str = "",
        extra_context: dict[str, Any] | None = None,
    ) -> HttpResponse:
        player = self.get_object(request, object_id)
        context: dict[str, Any] = {}
        if player is not None and self.has_view_or_change_permission(request, player):
            context = {
                "economy_blocks": player_page.blocks(request.user, player),
                "can_adjust": request.user.has_perm(player_page.ADJUST_PERMISSION),
            }
        return super().change_view(
            request, object_id, form_url, {**(extra_context or {}), **context}
        )

    def adjust_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        return player_page.adjust_view(self, request, object_id)

    @admin.display(description="Linked providers")
    def providers(self, player: Player) -> str:
        linked = player.identities.order_by("provider")
        return ", ".join(
            f"{i.provider} (linked {formats.localize(timezone.localtime(i.linked_at))})"
            for i in linked
        )

    @admin.display(description="Live sessions")
    def live_sessions(self, player: Player) -> int:
        return len(live_sessions(player, timezone.now()))


class NameFilterEntryForm(forms.ModelForm):  # type: ignore[type-arg]
    term = forms.CharField(
        max_length=40,
        help_text="Names containing this, in any common spelling, are refused. It is matched "
        "after normalization, shown on the entry once saved.",
    )

    class Meta:
        model = NameFilterEntry
        fields = ("term",)

    def clean_term(self) -> str:
        term: str = self.cleaned_data["term"].strip()
        folded = normalize(term)
        if not folded:
            raise forms.ValidationError(
                "This term has no letters left to match after normalization."
            )
        taken = NameFilterEntry.objects.filter(normalized=folded[:40]).exclude(pk=self.instance.pk)
        if taken.exists():
            raise forms.ValidationError(f"An entry already matches «{folded}».")
        return term


@admin.register(NameFilterEntry)
class NameFilterEntryAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    """The terms display names may not contain (B03 contracts/admin.md "The name filter")."""

    form = NameFilterEntryForm
    list_display = ("term", "normalized", "added_by", "created_at")
    list_select_related = ("added_by",)
    search_fields = ("term", "normalized")
    ordering = ("normalized",)
    fields = ("term", "normalized", "added_by", "created_at")
    readonly_fields = ("normalized", "added_by", "created_at")

    def save_model(
        self, request: HttpRequest, obj: NameFilterEntry, form: Any, change: bool
    ) -> None:
        if not change:
            obj.added_by = request.user  # type: ignore[assignment]  # the admin's staff user
        super().save_model(request, obj, form, change)
        self.message_user(request, f"Names containing «{obj.normalized}» are refused from now on.")
