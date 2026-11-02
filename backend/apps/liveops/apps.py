"""The live-ops app: live settings, the store catalog, offers and the Remote Config drift check.

`economy`, `accounts` and `content` import `liveops`; `liveops` never imports `economy` (B10
research R1).
"""

from __future__ import annotations

from typing import Any

from django.apps import AppConfig
from django.db.models.signals import post_migrate


class LiveopsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.liveops"
    label = "liveops"
    verbose_name = "Live ops"

    def ready(self) -> None:
        from apps.liveops import checks  # noqa: F401 - registers the system checks

        post_migrate.connect(seed_registry_rows, sender=self, dispatch_uid="liveops.seed_rows")


def seed_registry_rows(sender: Any, **kwargs: Any) -> None:
    """Create a row for every registry key a deploy added; mark dropped keys `unused` (R2)."""
    from apps.liveops.seed import sync_registry_rows

    sync_registry_rows()
