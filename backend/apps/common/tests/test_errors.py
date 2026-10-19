"""Every API error uses the one envelope (FR-013, contracts/api.md "Error envelope")."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

import pytest
from django.test import Client, override_settings
from pytest_django import Settings

from apps.common.errors import MESSAGES, ErrorCode

if TYPE_CHECKING:
    # The stubs' name for what the test client returns.
    from django.test.client import _MonkeyPatchedWSGIResponse as TestResponse

pytestmark = pytest.mark.urls("apps.common.tests.urls")

LIMIT_BYTES = 524288


def error_of(response: TestResponse, status: int, code: str) -> dict[str, Any]:
    assert response.status_code == status
    assert response["Content-Type"] == "application/json"
    body = json.loads(response.content)
    assert set(body) == {"error"}
    error: dict[str, Any] = body["error"]
    assert set(error) == {"code", "message", "details"}
    assert error["code"] == code
    assert error["message"] == MESSAGES[ErrorCode(code)]
    return error


def test_error_codes_are_exactly_the_contract() -> None:
    assert {code.value for code in ErrorCode} == {
        "validation_error",
        "not_found",
        "method_not_allowed",
        "not_acceptable",
        "payload_too_large",
        "unsupported_media_type",
        "rate_limited",
        "server_error",
        "not_ready",
        "dependency_unavailable",
    }
    assert set(MESSAGES) == set(ErrorCode)


@pytest.mark.parametrize("debug", [False, True])
@pytest.mark.parametrize("path", ["/nope", "/v1/nope", "/v1"])
@pytest.mark.parametrize("method", ["get", "post", "delete"])
def test_unknown_path_is_not_found(settings: Settings, debug: bool, path: str, method: str) -> None:
    settings.DEBUG = debug  # dev runs with DEBUG, where Django would answer with HTML
    # A real client sends no CSRF token; the test client skips the check unless told not to.
    client = Client(enforce_csrf_checks=True)
    error = error_of(getattr(client, method)(path), 404, "not_found")
    assert error["details"] == {}


def test_drf_views_need_no_csrf_token() -> None:
    response = Client(enforce_csrf_checks=True).post(
        "/test/echo", data={"a": 1}, content_type="application/json"
    )
    assert response.status_code == 200


def test_wrong_method_lists_allowed_methods(client: Client) -> None:
    error = error_of(client.delete("/healthz"), 405, "method_not_allowed")
    assert "GET" in error["details"]["allowed"]


def test_unacceptable_accept_header(client: Client) -> None:
    response = client.get("/healthz", headers={"accept": "application/xml"})
    assert error_of(response, 406, "not_acceptable")["details"] == {}


def test_unsupported_media_type(client: Client) -> None:
    response = client.post("/test/echo", data="hello", content_type="text/plain")
    assert error_of(response, 415, "unsupported_media_type")["details"] == {}


def test_body_over_limit_is_payload_too_large(client: Client) -> None:
    body = json.dumps("x" * LIMIT_BYTES)
    response = client.post("/test/echo", data=body, content_type="application/json")
    error = error_of(response, 413, "payload_too_large")
    assert error["details"] == {"limit_bytes": LIMIT_BYTES}


def test_body_under_limit_is_accepted(client: Client) -> None:
    response = client.post("/test/echo", data={"a": 1}, content_type="application/json")
    assert response.status_code == 200


def test_malformed_json_is_validation_error(client: Client) -> None:
    response = client.post("/test/echo", data="{not json", content_type="application/json")
    error_of(response, 400, "validation_error")


def test_field_errors_are_listed_per_field(client: Client) -> None:
    error = error_of(client.get("/test/invalid-fields"), 400, "validation_error")
    assert error["details"] == {"fields": {"name": ["Too short."], "age": ["Must be a number."]}}


def test_non_field_errors_use_the_drf_key(client: Client) -> None:
    error = error_of(client.get("/test/invalid"), 400, "validation_error")
    assert error["details"] == {"fields": {"non_field_errors": ["Pick one."]}}


def test_nested_errors_are_flattened_to_dotted_names(client: Client) -> None:
    body = {"inner": {}, "items": [{"a": 1}, {}]}
    response = client.post("/test/nested", data=body, content_type="application/json")
    error = error_of(response, 400, "validation_error")
    assert error["details"] == {
        "fields": {"inner.a": ["This field is required."], "items.1.a": ["This field is required."]}
    }


def test_django_permission_denied_is_the_envelope(client: Client) -> None:
    response = client.get("/test/django-forbidden")
    assert response.status_code == 403
    assert json.loads(response.content)["error"]["code"] == "permission_denied"
    assert "internal rule 7" not in response.content.decode()


def test_unauthenticated_keeps_www_authenticate(client: Client) -> None:
    response = client.get("/test/needs-auth")
    assert response.status_code == 401
    assert json.loads(response.content)["error"]["code"] == "not_authenticated"
    assert response["WWW-Authenticate"] == 'Bearer realm="api"'


def test_http404_inside_a_view_is_not_found(client: Client) -> None:
    error = error_of(client.get("/test/http404"), 404, "not_found")
    assert "no such thing" not in json.dumps(error)


def test_other_drf_errors_keep_their_code_with_a_generic_message(client: Client) -> None:
    response = client.get("/test/forbidden")
    assert response.status_code == 403
    error = json.loads(response.content)["error"]
    assert error["code"] == "permission_denied"
    assert error["details"] == {}
    assert "you shall not pass" not in response.content.decode()


@override_settings(DEBUG=False)
def test_unhandled_exception_is_generic_server_error() -> None:
    response = Client(raise_request_exception=False).get("/test/boom")
    error = error_of(response, 500, "server_error")
    assert error["details"] == {}
    text = response.content.decode()
    for leak in ("RuntimeError", "secret internals", "Traceback"):
        assert leak not in text
