"""What every content admin page shares."""

from __future__ import annotations

import re

from django.http import HttpRequest, HttpResponse

from apps.content.services import permissions

MAX_LISTED_FINDINGS = 50
TRIP_ID = re.compile(r"^(line_[a-z0-9_]+)\.([0-9]{1,2})$")


def is_staff(request: HttpRequest) -> bool:
    user = request.user
    return bool(user.is_active and user.is_staff)


def on_source() -> bool:
    return permissions.role() == permissions.SOURCE


def on_target() -> bool:
    return permissions.role() == permissions.TARGET


def attachment(data: bytes, name: str, content_type: str = "application/zip") -> HttpResponse:
    response = HttpResponse(data, content_type=content_type)
    response["Content-Disposition"] = f'attachment; filename="{name}"'
    return response
