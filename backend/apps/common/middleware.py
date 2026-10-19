"""Request middlewares for the API role (contracts/api.md)."""

from __future__ import annotations

import logging
import re
import time
from collections.abc import Callable

from django.conf import settings
from django.db import InterfaceError, OperationalError
from django.http import HttpRequest, HttpResponse
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import TimeoutError as RedisTimeoutError

from apps.common.errors import ErrorCode, envelope, payload_too_large
from apps.common.ids import uuid7
from apps.common.logging import request_id, route_of

logger = logging.getLogger("wassal.request")
access_logger = logging.getLogger("wassal.access")

REQUEST_ID = re.compile(r"[A-Za-z0-9-]{8,64}")

DEPENDENCY_ERRORS = (OperationalError, InterfaceError, RedisConnectionError, RedisTimeoutError)

GetResponse = Callable[[HttpRequest], HttpResponse]


class RequestIdMiddleware:
    """First in `MIDDLEWARE`. Takes a well-formed `X-Request-ID` or makes a UUIDv7, puts it in
    the `request_id` context for every log line, and echoes it on the response."""

    def __init__(self, get_response: GetResponse) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        incoming = request.headers.get("X-Request-ID", "")
        value = incoming if REQUEST_ID.fullmatch(incoming) else str(uuid7())
        # Not reset on the way out: Django logs 4xx/5xx responses after the middleware returns.
        # The request_finished signal clears it (CommonConfig.ready).
        request_id.set(value)
        response = self.get_response(request)
        response["X-Request-ID"] = value
        return response


class AccessLogMiddleware:
    """Second in `MIDDLEWARE` on the API role: one `wassal.access` line per request, with the
    route pattern and never the path, address, headers, cookies or body."""

    def __init__(self, get_response: GetResponse) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        started = time.perf_counter()
        response = self.get_response(request)
        access_logger.info(
            "",
            extra={
                "method": request.method,
                "route": route_of(request),
                "status": response.status_code,
                "duration_ms": round((time.perf_counter() - started) * 1000, 1),
            },
        )
        return response


class DependencyUnavailableMiddleware:
    """A database or cache outage during a request becomes `503 dependency_unavailable`."""

    def __init__(self, get_response: GetResponse) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        return self.get_response(request)

    def process_exception(self, request: HttpRequest, exception: Exception) -> HttpResponse | None:
        if not isinstance(exception, DEPENDENCY_ERRORS):
            return None
        logger.error("dependency unavailable", exc_info=exception)
        return envelope(ErrorCode.DEPENDENCY_UNAVAILABLE)


class NoStoreMiddleware:
    """Nothing the API returns in B01 may be cached by a client or a proxy."""

    def __init__(self, get_response: GetResponse) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        response = self.get_response(request)
        response["Cache-Control"] = "no-store"
        return response


class BodySizeLimitMiddleware:
    """The backstop for the edge's 512 KB limit (FR-020).

    DRF parses the request stream itself, which skips Django's `DATA_UPLOAD_MAX_MEMORY_SIZE`
    check. Django never reads past `Content-Length`, so checking the header is enough.
    """

    def __init__(self, get_response: GetResponse) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        try:
            length = int(request.META.get("CONTENT_LENGTH") or 0)
        except ValueError:
            length = 0
        if length > settings.DATA_UPLOAD_MAX_MEMORY_SIZE:
            return payload_too_large()
        return self.get_response(request)
