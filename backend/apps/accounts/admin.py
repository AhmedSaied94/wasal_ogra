"""Admin for staff accounts, and the read-only player pages for support (B02 contracts/admin.md).

There is no email or name to show for staff (data-model "accounts.User"). A player page never shows
a token, the install id or its hash, a provider subject or a session token id.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import AdminUserCreationForm, UserChangeForm
from django.http import HttpRequest
from django.utils import formats, timezone

from apps.accounts.models import Device, Player, User
from apps.accounts.services.sessions import live_sessions

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
