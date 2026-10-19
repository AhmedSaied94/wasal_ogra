"""Request ids and the one JSON access line per API request (FR-036, contracts/api.md)."""

import io
import json
import logging
import uuid
from collections.abc import Callable, Iterator
from typing import Any

import pytest
from django.conf import settings
from django.test import Client

from apps.common.logging import ContextFilter, JsonLineFormatter, request_id

pytestmark = [pytest.mark.django_db, pytest.mark.urls("apps.common.tests.urls")]

ACCESS_FIELDS = {
    "ts",
    "level",
    "logger",
    "request_id",
    "method",
    "route",
    "status",
    "duration_ms",
    "release",
    "env",
}

Lines = Callable[[], list[dict[str, object]]]


@pytest.fixture
def captured() -> Iterator[tuple[Lines, io.StringIO]]:
    """Lines written through the project formatter and filter, as the stdout handler does."""
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonLineFormatter())
    handler.addFilter(ContextFilter())
    root = logging.getLogger()
    root.addHandler(handler)
    level = root.level
    root.setLevel(logging.INFO)
    yield (lambda: [json.loads(line) for line in stream.getvalue().splitlines()]), stream
    root.removeHandler(handler)
    root.setLevel(level)


def access(lines: Lines) -> list[dict[str, object]]:
    return [line for line in lines() if line["logger"] == "wassal.access"]


def test_one_request_writes_one_access_line(captured: tuple[Lines, io.StringIO]) -> None:
    lines, _ = captured
    response = Client().get("/readyz")

    [line] = access(lines)
    assert line.keys() >= ACCESS_FIELDS
    assert line["method"] == "GET"
    assert line["route"] == "/readyz"
    assert line["status"] == 200
    assert line["level"] == "INFO"
    assert line["release"] == settings.RELEASE
    assert line["env"] == settings.WASSAL_ENV
    assert isinstance(line["duration_ms"], float)
    assert line["request_id"] == response["X-Request-ID"]
    assert str(line["ts"]).endswith("Z")
    assert "message" not in line


def test_the_route_pattern_is_logged_not_the_path(captured: tuple[Lines, io.StringIO]) -> None:
    lines, stream = captured
    thing = uuid.uuid4()

    Client().get(f"/test/things/{thing}?token=abc123")

    [line] = access(lines)
    assert line["route"] == "/test/things/<uuid:thing_id>"
    assert str(thing) not in stream.getvalue()
    assert "abc123" not in stream.getvalue()


def test_an_unrouted_path_is_logged_without_it(captured: tuple[Lines, io.StringIO]) -> None:
    lines, stream = captured

    Client().get("/players/12345/secret-page")

    [line] = access(lines)
    assert line["status"] == 404
    assert line["route"] == "<unmatched>"
    assert "12345" not in stream.getvalue()


def test_no_address_header_cookie_or_body_is_logged(captured: tuple[Lines, io.StringIO]) -> None:
    _, stream = captured
    client = Client(
        REMOTE_ADDR="203.0.113.77",
        HTTP_X_FORWARDED_FOR="198.51.100.88",
        HTTP_AUTHORIZATION="Bearer header-token-value",
        HTTP_USER_AGENT="agent-string-value",
    )
    client.cookies["sessionid"] = "cookie-value"

    client.post("/test/echo", {"password": "body-value"}, content_type="application/json")

    text = stream.getvalue()
    for secret in (
        "203.0.113.77",
        "198.51.100.88",
        "header-token-value",
        "agent-string-value",
        "cookie-value",
        "body-value",
    ):
        assert secret not in text


def test_a_valid_request_id_is_echoed_and_logged(captured: tuple[Lines, io.StringIO]) -> None:
    lines, _ = captured

    response = Client().get("/healthz", HTTP_X_REQUEST_ID="mobile-abc-12345678")

    assert response["X-Request-ID"] == "mobile-abc-12345678"
    assert access(lines)[0]["request_id"] == "mobile-abc-12345678"


@pytest.mark.parametrize(
    "incoming",
    ["short", "has space here", "semi;colon-1234", "x" * 65, "line-1234\n", "ünïcode-12345"],
)
def test_an_invalid_request_id_is_replaced(incoming: str) -> None:
    response = Client().get("/healthz", HTTP_X_REQUEST_ID=incoming)

    assert response["X-Request-ID"] != incoming
    assert uuid.UUID(response["X-Request-ID"]).version == 7


@pytest.mark.parametrize("path", ["/healthz", "/nowhere", "/test/boom", "/test/forbidden"])
def test_every_response_carries_a_request_id(path: str) -> None:
    response = Client(raise_request_exception=False).get(path)

    assert uuid.UUID(response["X-Request-ID"]).version == 7


def test_log_lines_inside_a_request_carry_its_id(captured: tuple[Lines, io.StringIO]) -> None:
    lines, _ = captured

    response = Client(raise_request_exception=False).get("/test/boom")

    assert response.status_code == 500
    errors = [line for line in lines() if line["level"] == "ERROR"]
    assert errors
    assert {line["request_id"] for line in errors} == {response["X-Request-ID"]}
    assert all(line["message"] == "Internal Server Error: /test/boom" for line in errors)


def test_lines_outside_a_request_have_no_id(captured: tuple[Lines, io.StringIO]) -> None:
    lines, _ = captured

    logging.getLogger("wassal.test").warning("outside")

    [line] = lines()
    assert line["request_id"] is None
    assert line["message"] == "outside"
    assert request_id.get() is None


def test_logging_writes_json_to_stdout() -> None:
    config: dict[str, Any] = settings.LOGGING
    handler = config["handlers"]["stdout"]
    assert handler["stream"] == "ext://sys.stdout"
    assert (
        config["formatters"][handler["formatter"]]["()"] == "apps.common.logging.JsonLineFormatter"
    )
    assert config["filters"][handler["filters"][0]]["()"] == "apps.common.logging.ContextFilter"
    assert config["root"] == {"handlers": ["stdout"], "level": settings.LOG_LEVEL}


def test_the_request_id_and_access_log_lead_the_middleware() -> None:
    assert settings.MIDDLEWARE[:2] == [
        "apps.common.middleware.RequestIdMiddleware",
        "apps.common.middleware.AccessLogMiddleware",
    ]
