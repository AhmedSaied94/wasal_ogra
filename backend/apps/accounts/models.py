"""The project-owned staff account (FR-017, data-model "accounts.User").

Staff only: players are a later feature. The account keeps no email address or name.
"""

from __future__ import annotations

from typing import Any, ClassVar

from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.core.validators import RegexValidator
from django.db import models
from django.utils import timezone

from apps.common.models import UUIDv7Model

USERNAME_PATTERN = r"^[a-z0-9._-]{3,150}$"


class UserManager(BaseUserManager["User"]):
    def get_by_natural_key(self, username: str | None) -> User:
        # Usernames are stored lowercase, so sign-in ignores the letter case typed.
        return self.get(username=(username or "").lower())

    def create_user(self, username: str, password: str | None = None, **extra: Any) -> User:
        user = self.model(username=username.lower(), **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, username: str, password: str | None = None, **extra: Any) -> User:
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        return self.create_user(username, password, **extra)


class User(UUIDv7Model, AbstractBaseUser, PermissionsMixin):
    username = models.CharField(
        max_length=150,
        unique=True,
        validators=[
            RegexValidator(
                USERNAME_PATTERN,
                "Use 3-150 lowercase letters, digits, dots, dashes or underscores.",
            )
        ],
    )
    is_staff = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    date_joined = models.DateTimeField(default=timezone.now)

    objects: ClassVar[UserManager] = UserManager()

    USERNAME_FIELD = "username"
    REQUIRED_FIELDS: ClassVar[list[str]] = []

    def __str__(self) -> str:
        return self.username

    def clean(self) -> None:
        super().clean()
        self.username = self.username.lower()

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.username = self.username.lower()
        super().save(*args, **kwargs)
