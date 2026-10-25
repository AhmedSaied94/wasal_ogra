"""Permissions every player endpoint inherits (B02 research R10)."""

from __future__ import annotations

from typing import TYPE_CHECKING

from rest_framework.permissions import BasePermission

from apps.common.client import client_info

if TYPE_CHECKING:
    from rest_framework.request import Request
    from rest_framework.views import APIView


class ClientHeaders(BasePermission):
    """`X-Client-Version` and `X-Platform` must both be present and well formed (FR-034)."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        method = request.method.lower() if request.method else ""
        if method == "options" or not hasattr(view, method):
            # DRF checks permissions before the method: a method the view doesn't serve must
            # still get its 405, whatever the headers say.
            return True
        client_info(request)
        return True
