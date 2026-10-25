"""The staff account (B01 FR-017) and the player tables (B02 data-model.md).

Staff and players never mix: `User` is `AUTH_USER_MODEL` and signs in to the admin only, and a
`Player` authenticates the API with its own tokens (B02 research R1). Neither keeps an email
address or a name.
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


# -- Players (B02, specs/009-b02-accounts-auth/data-model.md) --------------------------------------


class Platform(models.TextChoices):
    ANDROID = "android"
    IOS = "ios"


class Player(UUIDv7Model):
    """One game account. B03 attaches the wallet and progress, B09 changes the status."""

    class Status(models.TextChoices):
        ACTIVE = "active"
        PENDING_DELETION = "pending_deletion"
        DELETED = "deleted"

    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.ACTIVE, db_index=True
    )
    display_name = models.CharField(max_length=32, blank=True)
    country = models.CharField(max_length=2, blank=True)
    locale = models.CharField(max_length=16)
    platform = models.CharField(max_length=8, choices=Platform.choices)
    client_version = models.CharField(max_length=32)
    driver_level = models.PositiveSmallIntegerField(default=1)
    is_tester = models.BooleanField(default=False)
    # The app's settings, written only by B03's `settings_update` (B03 research R10).
    settings = models.JSONField(default=dict, blank=True)
    # Set only when tokens are issued or renewed (FR-018).
    last_seen_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = (
            models.CheckConstraint(
                condition=models.Q(driver_level__gte=1), name="player_driver_level_at_least_1"
            ),
        )

    def __str__(self) -> str:
        return str(self.id)

    @property
    def is_authenticated(self) -> bool:
        """What DRF's `IsAuthenticated` reads. Every loaded player is authenticated."""
        return True

    @property
    def is_active(self) -> bool:
        return self.status == self.Status.ACTIVE


class Device(UUIDv7Model):
    """One installation, keyed by its install id: the anonymous identity (research R4)."""

    # sha256 hex of the canonical v4 install id. Never shown or logged.
    install_id_hash = models.CharField(max_length=64, unique=True)
    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="devices")
    platform = models.CharField(max_length=8, choices=Platform.choices)
    app_version = models.CharField(max_length=32)
    last_seen_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return str(self.id)


class Identity(UUIDv7Model):
    """A provider account that signs in to a player: `google` now, `apple` in phase 3."""

    class Provider(models.TextChoices):
        GOOGLE = "google"

    player = models.ForeignKey(Player, on_delete=models.PROTECT, related_name="identities")
    provider = models.CharField(max_length=16, choices=Provider.choices)
    # The provider's account number (`sub`). Never shown or logged.
    subject = models.CharField(max_length=255)
    linked_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "identities"
        constraints = (
            models.UniqueConstraint(
                fields=("provider", "subject"), name="identity_one_player_per_account"
            ),
            models.UniqueConstraint(
                fields=("player", "provider"), name="identity_one_account_per_provider"
            ),
        )

    def __str__(self) -> str:
        return f"{self.provider} {self.id}"


class PlayerSession(UUIDv7Model):
    """The chain of refresh tokens from one sign-in on one device (research R3).

    It stores the claims of the current and the previous refresh token, never a token. Live means
    `status == active` and `current_expires_at > now`; a lapsed session is not a stored status.
    """

    class Status(models.TextChoices):
        ACTIVE = "active"
        ENDED = "ended"

    class EndReason(models.TextChoices):
        REUSE = "reuse"
        SWITCH = "switch"
        LIMIT = "limit"

    player = models.ForeignKey(Player, on_delete=models.CASCADE, related_name="sessions")
    device = models.ForeignKey(Device, on_delete=models.CASCADE, related_name="sessions")
    status = models.CharField(max_length=8, choices=Status.choices, default=Status.ACTIVE)
    end_reason = models.CharField(max_length=8, choices=EndReason.choices, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    current_jti = models.UUIDField()
    current_issued_at = models.DateTimeField()
    current_expires_at = models.DateTimeField()
    current_kid = models.CharField(max_length=32)
    previous_jti = models.UUIDField(null=True, blank=True)
    previous_spent_at = models.DateTimeField(null=True, blank=True)
    last_renewed_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = (
            models.Index(
                fields=("player", "status", "current_expires_at"), name="session_live_by_player"
            ),
            models.Index(fields=("status", "ended_at"), name="session_ended"),
            models.Index(fields=("current_expires_at",), name="session_lapse"),
        )

    def __str__(self) -> str:
        return str(self.id)


class NameFilterEntry(UUIDv7Model):
    """A term display names may not contain, edited by staff in the admin (B03 research R10).

    `normalized` is the term after `apps.accounts.services.names.normalize`, the same function the
    name check uses, so spelling variants of a term match too.
    """

    term = models.CharField(max_length=40)
    normalized = models.CharField(max_length=40, unique=True, editable=False)
    added_by = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "name filter entry"
        verbose_name_plural = "name filter"

    def __str__(self) -> str:
        return self.term

    def save(self, *args: Any, **kwargs: Any) -> None:
        from apps.accounts.services.names import normalize  # the service imports this module

        self.normalized = normalize(self.term)[:40]
        super().save(*args, **kwargs)
