"""The two default permissions every player endpoint inherits (B10 research R6, R7).

They read the process's live-settings snapshot, so neither adds a query to the request path.

- `CurrentClient` answers `426 client_outdated` when `X-Client-Version` is below the platform's live
  minimum. A view sets `allow_outdated_client = True` to opt out; only bootstrap does.
- `NotInMaintenance` answers `503 maintenance` for every unsafe method while maintenance is on.
"""

from __future__ import annotations

from datetime import UTC
from typing import TYPE_CHECKING, Any

from django.utils import timezone
from rest_framework.permissions import BasePermission

from apps.common.client import as_tuple, client_info, parse_client_version
from apps.common.errors import ApiError, ErrorCode
from apps.liveops import settings as live

if TYPE_CHECKING:
    from rest_framework.request import Request
    from rest_framework.views import APIView

UNSAFE_METHODS = ("post", "put", "patch", "delete")


def _serves(request: Request, view: APIView) -> bool:
    method = request.method.lower() if request.method else ""
    return method != "options" and hasattr(view, method)


class CurrentClient(BasePermission):
    """The app must be at least the platform's minimum version (FR-012, FR-013, FR-014)."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        if not _serves(request, view) or getattr(view, "allow_outdated_client", False):
            return True
        info = client_info(request)  # ClientHeaders already refused a bad header
        minimum = live.current()[f"min_client_version_{info.platform}"]
        version = parse_client_version(info.version)
        if version is not None and version < as_tuple(minimum):
            raise ApiError(ErrorCode.CLIENT_OUTDATED, {"min_version": minimum})
        return True


class NotInMaintenance(BasePermission):
    """No write while maintenance is on; reads pass (FR-015, FR-016)."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        method = request.method.lower() if request.method else ""
        if method not in UNSAFE_METHODS or not _serves(request, view):
            return True
        snapshot = live.current()
        if not snapshot["maintenance_enabled"]:
            return True
        details: dict[str, Any] = {}
        until = snapshot["maintenance_until"]
        if until is not None and until > timezone.now():
            details["until"] = until.astimezone(UTC).isoformat().replace("+00:00", "Z")
        raise ApiError(ErrorCode.MAINTENANCE, details)
