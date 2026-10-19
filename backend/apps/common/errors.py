"""The API error envelope (FR-013, contracts/api.md "Error envelope").

Every non-2xx response on the API hostname is `{"error": {"code", "message", "details"}}`. Messages
are fixed strings per code, so no exception text, internal name or hostname can reach a client.
"""

from __future__ import annotations

import math
from enum import StrEnum
from typing import Any

from django.conf import settings
from django.core.exceptions import PermissionDenied, RequestDataTooBig
from django.http import Http404, HttpRequest, JsonResponse
from django.views.decorators.csrf import csrf_exempt
from rest_framework import exceptions
from rest_framework.settings import api_settings
from rest_framework.views import set_rollback


class ErrorCode(StrEnum):
    VALIDATION_ERROR = "validation_error"
    NOT_FOUND = "not_found"
    METHOD_NOT_ALLOWED = "method_not_allowed"
    NOT_ACCEPTABLE = "not_acceptable"
    PAYLOAD_TOO_LARGE = "payload_too_large"
    UNSUPPORTED_MEDIA_TYPE = "unsupported_media_type"
    RATE_LIMITED = "rate_limited"
    SERVER_ERROR = "server_error"
    NOT_READY = "not_ready"
    DEPENDENCY_UNAVAILABLE = "dependency_unavailable"


MESSAGES: dict[ErrorCode, str] = {
    ErrorCode.VALIDATION_ERROR: "Invalid request",
    ErrorCode.NOT_FOUND: "Not found",
    ErrorCode.METHOD_NOT_ALLOWED: "Method not allowed",
    ErrorCode.NOT_ACCEPTABLE: "Not acceptable",
    ErrorCode.PAYLOAD_TOO_LARGE: "Payload too large",  # the edge sends the same body (Caddyfile)
    ErrorCode.UNSUPPORTED_MEDIA_TYPE: "Unsupported media type",
    ErrorCode.RATE_LIMITED: "Too many requests",
    ErrorCode.SERVER_ERROR: "Server error",
    ErrorCode.NOT_READY: "Service not ready",
    ErrorCode.DEPENDENCY_UNAVAILABLE: "Service temporarily unavailable",
}

STATUSES: dict[ErrorCode, int] = {
    ErrorCode.VALIDATION_ERROR: 400,
    ErrorCode.NOT_FOUND: 404,
    ErrorCode.METHOD_NOT_ALLOWED: 405,
    ErrorCode.NOT_ACCEPTABLE: 406,
    ErrorCode.PAYLOAD_TOO_LARGE: 413,
    ErrorCode.UNSUPPORTED_MEDIA_TYPE: 415,
    ErrorCode.RATE_LIMITED: 429,
    ErrorCode.SERVER_ERROR: 500,
    ErrorCode.NOT_READY: 503,
    ErrorCode.DEPENDENCY_UNAVAILABLE: 503,
}

# The explicit table wins over a DRF exception's own `default_code` (contracts/api.md).
DRF_CODES: tuple[tuple[type[exceptions.APIException], ErrorCode], ...] = (
    (exceptions.ValidationError, ErrorCode.VALIDATION_ERROR),
    (exceptions.ParseError, ErrorCode.VALIDATION_ERROR),
    (exceptions.NotFound, ErrorCode.NOT_FOUND),
    (exceptions.MethodNotAllowed, ErrorCode.METHOD_NOT_ALLOWED),
    (exceptions.NotAcceptable, ErrorCode.NOT_ACCEPTABLE),
    (exceptions.UnsupportedMediaType, ErrorCode.UNSUPPORTED_MEDIA_TYPE),
    (exceptions.Throttled, ErrorCode.RATE_LIMITED),
)


def body(code: str, message: str, details: dict[str, Any] | None = None) -> dict[str, Any]:
    return {"error": {"code": code, "message": message, "details": details or {}}}


def envelope(
    code: ErrorCode, details: dict[str, Any] | None = None, *, status: int | None = None
) -> JsonResponse:
    return JsonResponse(body(code, MESSAGES[code], details), status=status or STATUSES[code])


def payload_too_large() -> JsonResponse:
    return envelope(
        ErrorCode.PAYLOAD_TOO_LARGE, {"limit_bytes": settings.DATA_UPLOAD_MAX_MEMORY_SIZE}
    )


def exception_handler(exc: Exception, context: dict[str, Any]) -> JsonResponse | None:
    """DRF's `EXCEPTION_HANDLER`. Returning `None` lets Django's 500 path (`handler500`) run."""
    if isinstance(exc, RequestDataTooBig):
        return payload_too_large()
    if isinstance(exc, Http404):
        exc = exceptions.NotFound()
    elif isinstance(exc, PermissionDenied):
        exc = exceptions.PermissionDenied()
    if not isinstance(exc, exceptions.APIException):
        return None

    set_rollback()
    if isinstance(exc, exceptions.Throttled):
        retry_after = max(1, math.ceil(getattr(exc, "wait", None) or 1))
        response = envelope(ErrorCode.RATE_LIMITED, {"retry_after_s": retry_after})
        response["Retry-After"] = str(retry_after)
        return response
    code = next((code for cls, code in DRF_CODES if isinstance(exc, cls)), None)
    if code is None:
        # Any other DRF exception keeps its own code, which must be in backend §6.2 first.
        detail = body(str(exc.default_code), str(exc.default_detail))
        response = JsonResponse(detail, status=exc.status_code)
        auth_header = getattr(exc, "auth_header", None)  # set by DRF on 401s
        if auth_header:
            response["WWW-Authenticate"] = auth_header
        return response
    return envelope(code, _details(code, exc, context))


def _details(
    code: ErrorCode, exc: exceptions.APIException, context: dict[str, Any]
) -> dict[str, Any]:
    if code is ErrorCode.METHOD_NOT_ALLOWED:
        view = context.get("view")
        return {"allowed": list(getattr(view, "allowed_methods", []))}
    if isinstance(exc, exceptions.ValidationError):
        detail = exc.detail
        if not isinstance(detail, dict):
            detail = {api_settings.NON_FIELD_ERRORS_KEY: detail}
        return {"fields": _flatten(detail)}
    return {}


def _flatten(detail: Any, prefix: str = "") -> dict[str, list[str]]:
    """Nested serializer errors become dotted names: `inner.a`, `items.1.a`."""
    if isinstance(detail, dict):
        entries: Any = detail.items()
    elif isinstance(detail, list) and any(isinstance(item, dict | list) for item in detail):
        entries = enumerate(detail)  # a `many=True` serializer: one entry per item
    else:
        return {prefix: _messages(detail)}
    fields: dict[str, list[str]] = {}
    for key, value in entries:
        fields.update(_flatten(value, f"{prefix}.{key}" if prefix else str(key)))
    return fields


def _messages(value: Any) -> list[str]:
    if isinstance(value, list | tuple):
        return [str(item) for item in value]
    return [str(value)]


def handler404(request: HttpRequest, exception: Exception) -> JsonResponse:
    return envelope(ErrorCode.NOT_FOUND)


@csrf_exempt  # otherwise a POST to an unknown path gets Django's HTML CSRF page, not a 404
def not_found(request: HttpRequest, *args: Any, **kwargs: Any) -> JsonResponse:
    """The API's last route. Under DEBUG (dev), Django would answer unknown paths with HTML."""
    return envelope(ErrorCode.NOT_FOUND)


def handler500(request: HttpRequest) -> JsonResponse:
    return envelope(ErrorCode.SERVER_ERROR)
