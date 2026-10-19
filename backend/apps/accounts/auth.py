"""Sign-in helpers for the admin lockout (FR-022)."""

from __future__ import annotations

from typing import Any

from django.http import HttpRequest


def lockout_username(request: HttpRequest, credentials: dict[str, Any] | None) -> str | None:
    """Count failures per account whatever letter case was typed: usernames are stored lowercase.

    django-axes calls this for `AXES_USERNAME_CALLABLE`.
    """
    source: Any = credentials if credentials else request.POST
    username = source.get("username")
    return username.lower() if isinstance(username, str) else None
