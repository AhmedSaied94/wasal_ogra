"""Admin for staff accounts. There is no email or name to show (data-model "accounts.User")."""

from __future__ import annotations

from typing import TYPE_CHECKING

from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import AdminUserCreationForm, UserChangeForm

from apps.accounts.models import User

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
