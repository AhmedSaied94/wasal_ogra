"""JSON log lines on stdout (FR-036, research R7, contracts/api.md "Access log line").

Every line is one JSON object: `ts`, `level`, `logger`, `request_id`, the message if there is one,
the record's own fields, then `release` and `env`. Request paths never appear, only the route
pattern, so ids and query strings stay out of the logs.
"""

from __future__ import annotations

import functools
import json
import logging
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Any

from django.conf import settings
from django.http import HttpRequest
from pythonjsonlogger.core import RESERVED_ATTRS
from pythonjsonlogger.json import JsonFormatter

# Set by RequestIdMiddleware, cleared when the response is finished (CommonConfig.ready), so
# Django's own response log line, written after the middleware returns, still carries it.
request_id: ContextVar[str | None] = ContextVar("request_id", default=None)

UNMATCHED = "<unmatched>"


def route_of(request: HttpRequest) -> str:
    """The URL pattern that served the request, such as `/v1/things/<uuid:id>`."""
    match = getattr(request, "resolver_match", None)
    if match is None or match.route in ("", "^"):  # the catch-all 404 route is `^`
        return UNMATCHED
    return f"/{match.route}"


def clear_request_id(**kwargs: Any) -> None:
    request_id.set(None)


class ContextFilter(logging.Filter):
    """Adds `request_id`, `release` and `env` to every record."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id.get()
        record.release = getattr(settings, "RELEASE", None)
        record.env = getattr(settings, "WASSAL_ENV", None)
        return True


class JsonLineFormatter(JsonFormatter):
    def __init__(self) -> None:
        super().__init__(
            ["levelname", "name", "message"],
            rename_fields={"levelname": "level", "name": "logger"},
            # Request objects never get serialized: their repr holds the raw path.
            reserved_attrs=[*RESERVED_ATTRS, "request", "taskName", "color_message"],
            json_serializer=functools.partial(json.dumps, separators=(",", ":")),
        )

    def format(self, record: logging.LogRecord) -> str:
        # Django logs every 4xx/5xx response as "<reason>: <raw path>". Log the route instead.
        request = record.__dict__.get("request")
        if (
            record.name == "django.request"
            and isinstance(request, HttpRequest)
            and isinstance(record.args, tuple)
            and record.args
        ):
            record = logging.makeLogRecord(
                {**record.__dict__, "msg": "%s: %s", "args": (record.args[0], route_of(request))}
            )
        return super().format(record)

    def add_fields(
        self, log_data: dict[str, Any], record: logging.LogRecord, message_dict: dict[str, Any]
    ) -> None:
        super().add_fields(log_data, record, message_dict)
        created = datetime.fromtimestamp(record.created, UTC)
        log_data["ts"] = created.strftime("%Y-%m-%dT%H:%M:%S.") + f"{int(record.msecs):03d}Z"

    def process_log_record(self, log_data: dict[str, Any]) -> dict[str, Any]:
        line: dict[str, Any] = {
            "ts": log_data.pop("ts"),
            "level": log_data.pop("level"),
            "logger": log_data.pop("logger"),
            "request_id": log_data.pop("request_id", None),
        }
        message = log_data.pop("message", "")
        if message:
            line["message"] = message
        release, env = log_data.pop("release", None), log_data.pop("env", None)
        return {**line, **log_data, "release": release, "env": env}
