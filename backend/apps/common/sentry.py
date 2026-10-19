"""Error tracking (FR-024, FR-035, research R7). No personal data leaves the server.

The SDK's own options already keep most of it out (`send_default_pii=False`, no local variables,
no request bodies). `scrub` removes what is left, from errors and performance transactions alike,
and `scrub_breadcrumb` from breadcrumbs:

- raw paths, which can hold ids: the transaction already carries the URL pattern;
- outgoing URLs, which can be secrets (a Healthchecks ping URL is one): only scheme and host stay.
"""

from __future__ import annotations

import logging
from urllib.parse import urlsplit

import sentry_sdk
from sentry_sdk.integrations.celery import CeleryIntegration
from sentry_sdk.integrations.django import DjangoIntegration
from sentry_sdk.integrations.logging import LoggingIntegration
from sentry_sdk.types import Breadcrumb, BreadcrumbHint, Event, Hint

from apps.common.logging import request_id

SCRUBBED_REQUEST_KEYS = ("headers", "cookies", "data", "env", "query_string")
# Django's request loggers put the raw path in their message ("Not Found: /v1/…").
PATH_LOGGERS = frozenset({"django.request", "django.server"})


def origin(url: object) -> str:
    """`scheme://host[:port]`, without path, query or credentials."""
    parts = urlsplit(str(url))
    host = parts.hostname or ""
    return f"{parts.scheme}://{host}{f':{parts.port}' if parts.port else ''}" if host else ""


def scrub(event: Event, hint: Hint) -> Event | None:
    """`before_send` and `before_send_transaction`."""
    request = event.get("request")
    if isinstance(request, dict):
        for key in SCRUBBED_REQUEST_KEYS:
            request.pop(key, None)
        if "url" in request:
            request["url"] = origin(request["url"])
    if event.get("logger") in PATH_LOGGERS:
        logentry = event.get("logentry")
        if isinstance(logentry, dict):
            logentry["params"] = []
            logentry["formatted"] = str(logentry.get("message", "")).replace("%s", "<path>")
    breadcrumbs = event.get("breadcrumbs")
    if isinstance(breadcrumbs, dict) and isinstance(breadcrumbs.get("values"), list):
        kept = [scrub_breadcrumb(crumb, {}) for crumb in breadcrumbs["values"]]
        breadcrumbs["values"] = [crumb for crumb in kept if crumb is not None]
    user = event.get("user")
    if isinstance(user, dict):
        user.pop("ip_address", None)
    current = request_id.get()
    if current:
        event["tags"] = {**event.get("tags", {}), "request_id": current}
    return event


def scrub_breadcrumb(crumb: Breadcrumb, hint: BreadcrumbHint) -> Breadcrumb | None:
    """`before_breadcrumb`: no raw paths, and outgoing URLs cut to their origin."""
    if crumb.get("category") in PATH_LOGGERS:
        return None
    data = crumb.get("data")
    if isinstance(data, dict):
        for key in ("http.query", "http.fragment"):
            data.pop(key, None)
        if "url" in data:
            data["url"] = origin(data["url"])
    return crumb


def init_sentry(dsn: str, *, environment: str, release: str, traces_sample_rate: float) -> bool:
    """Starts the SDK, unless there is no DSN (dev, test). Called from the settings."""
    if not dsn:
        return False
    sentry_sdk.init(
        dsn=dsn,
        environment=environment,
        release=release,
        send_default_pii=False,
        include_local_variables=False,
        max_request_body_size="never",
        traces_sample_rate=traces_sample_rate,
        before_send=scrub,
        before_send_transaction=scrub,
        before_breadcrumb=scrub_breadcrumb,
        integrations=[
            # Transactions are named by URL pattern, never by the raw path.
            DjangoIntegration(transaction_style="url"),
            CeleryIntegration(),
            LoggingIntegration(level=logging.INFO, event_level=logging.ERROR),
        ],
    )
    return True
