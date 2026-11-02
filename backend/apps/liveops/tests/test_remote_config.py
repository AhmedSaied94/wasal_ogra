"""The Remote Config drift check (B10 FR-009, research R8)."""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
import pytest
import requests
import sentry_sdk
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from django.utils import timezone

from apps.liveops import settings as live
from apps.liveops.models import RemoteConfigCheck
from apps.liveops.services import remote_config

pytestmark = pytest.mark.django_db

PROJECT = "wassal-ogra"
EMAIL = "checker@wassal.ogra.iam.gserviceaccount.com"
KEY_ID = "kid-0123456789"


def pem() -> str:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()


@pytest.fixture
def account(settings: Any) -> str:
    raw = json.dumps({"client_email": EMAIL, "private_key": pem(), "private_key_id": KEY_ID})
    settings.FIREBASE_PROJECT_ID = PROJECT
    settings.REMOTE_CONFIG_SERVICE_ACCOUNT = raw
    return raw


def template(values: dict[str, Any], version: str = "7") -> dict[str, Any]:
    parameters = {}
    for key, value in values.items():
        parameters[key] = {"defaultValue": {"value": value}}
    return {"version": {"versionNumber": version}, "parameters": parameters}


@pytest.fixture
def fetched(monkeypatch: pytest.MonkeyPatch) -> list[dict[str, Any]]:
    """Swap the module's fetch function so no test touches the network."""
    served: list[dict[str, Any]] = [template({})]

    def fetch(project_id: str, account_dict: dict[str, Any]) -> dict[str, Any]:
        return served[0]

    monkeypatch.setattr(remote_config, "_fetch", fetch)
    return served


@pytest.fixture
def captured(monkeypatch: pytest.MonkeyPatch) -> list[tuple[str, dict[str, Any]]]:
    calls: list[tuple[str, dict[str, Any]]] = []

    def capture(message: str, **kwargs: Any) -> str:
        calls.append((message, kwargs))
        return "event-id"

    monkeypatch.setattr(sentry_sdk, "capture_message", capture)
    return calls


def test_the_signed_assertion(account: str, monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    class Response:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, Any]:
            return {"access_token": "ya29.fake"}

    def post(url: str, data: dict[str, Any], timeout: int) -> Response:
        captured.update({"url": url, "data": data, "timeout": timeout})
        return Response()

    monkeypatch.setattr(requests, "post", post)
    now = datetime(2026, 11, 1, 9, 0, tzinfo=UTC)
    token = remote_config.fetch_token(json.loads(account), now=now)
    assert token == "ya29.fake"
    assert captured["url"] == remote_config.TOKEN_URL
    claims = jwt.decode(captured["data"]["assertion"], options={"verify_signature": False})
    assert claims["iss"] == EMAIL
    assert claims["scope"] == remote_config.SCOPE
    assert claims["aud"] == remote_config.TOKEN_URL
    assert claims["exp"] - claims["iat"] <= 3600
    assert captured["data"]["grant_type"].endswith("jwt-bearer")
    assert captured["timeout"] == 10


def test_equal_defaults_record_ok(account: str, fetched: list[Any]) -> None:
    row = remote_config.run()
    assert (row.status, row.template_version, row.drift) == ("ok", "7", [])


def test_a_both_key_drift_alerts_sentry(
    account: str, fetched: list[Any], captured: list[Any]
) -> None:
    fetched[0] = template({"fuel_max": "6"})
    row = remote_config.run()
    assert row.status == "drift"
    assert [entry["key"] for entry in row.drift] == ["fuel_max"]
    assert row.drift[0]["server"] == 5
    assert row.drift[0]["remote_config"] == 6
    assert row.drift[0]["applied_by"] == "both"
    [message] = captured
    assert message[1]["level"] == "warning"
    assert message[1]["fingerprint"] == ["liveops", "remote-config-drift"]


def test_a_phone_only_drift_logs_but_does_not_alert(
    account: str, fetched: list[Any], captured: list[Any], caplog: Any
) -> None:
    fetched[0] = template({"trip_hop_ms_line_hay": "1500"})
    with caplog.at_level("WARNING"):
        row = remote_config.run()
    assert [entry["key"] for entry in row.drift] == ["trip_hop_ms_line_hay"]
    assert captured == []
    assert any(record.message == "remote_config_drift" for record in caplog.records)


def test_an_absent_parameter_compares_the_bundled_default(account: str, fetched: list[Any]) -> None:
    live.refresh()
    assert live.current()["fuel_max"] == 5
    fetched[0] = template({})
    assert remote_config.run().status == "ok"


def test_use_in_app_default_compares_the_bundled_default(account: str, fetched: list[Any]) -> None:
    fetched[0] = {
        "version": {"versionNumber": "9"},
        "parameters": {"fuel_max": {"defaultValue": {"useInAppDefault": True}}},
    }
    assert remote_config.run().status == "ok"


def test_conditional_values_are_ignored(account: str, fetched: list[Any]) -> None:
    fetched[0] = {
        "version": {"versionNumber": "9"},
        "parameters": {
            "fuel_max": {
                "defaultValue": {"value": "5"},
                "conditionalValues": {"EG": {"value": "9"}},
            }
        },
    }
    assert remote_config.run().status == "ok"


def test_a_network_error_retries_then_records_unreachable(
    account: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[int] = []

    def fetch(project_id: str, account_dict: dict[str, Any]) -> dict[str, Any]:
        calls.append(1)
        raise requests.ConnectionError("no route")

    monkeypatch.setattr(remote_config, "_fetch", fetch)
    row = remote_config.run()
    assert len(calls) == remote_config.ATTEMPTS
    assert row.status == "unreachable"
    assert row.drift == []


def test_an_unreachable_run_keeps_the_previous_marks(
    account: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    RemoteConfigCheck.objects.create(
        ran_at=timezone.now() - timedelta(hours=2),
        status="drift",
        template_version="6",
        drift=[{"key": "fuel_max", "server": 5, "remote_config": 6, "applied_by": "both"}],
    )

    def fetch(project_id: str, account_dict: dict[str, Any]) -> dict[str, Any]:
        raise requests.ConnectionError("no route")

    monkeypatch.setattr(remote_config, "_fetch", fetch)
    remote_config.run()
    assert list(remote_config.latest_marks()) == ["fuel_max"]


def test_no_variables_record_not_configured_without_a_call(
    settings: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings.FIREBASE_PROJECT_ID = ""
    settings.REMOTE_CONFIG_SERVICE_ACCOUNT = ""

    def fetch(project_id: str, account_dict: dict[str, Any]) -> dict[str, Any]:
        raise AssertionError("the network must not be called")

    monkeypatch.setattr(remote_config, "_fetch", fetch)
    row = remote_config.run()
    assert row.status == "not_configured"


def test_rows_older_than_90_days_are_deleted(account: str, fetched: list[Any]) -> None:
    old = RemoteConfigCheck.objects.create(
        ran_at=timezone.now() - timedelta(days=91), status="ok", template_version="1"
    )
    remote_config.run()
    assert not RemoteConfigCheck.objects.filter(pk=old.pk).exists()


def test_neither_the_key_nor_the_token_reaches_a_log_or_sentry(
    account: str,
    monkeypatch: pytest.MonkeyPatch,
    caplog: Any,
    captured: list[Any],
) -> None:
    key = json.loads(account)
    token = "ya29.secret-token"

    def fetch(project_id: str, account_dict: dict[str, Any]) -> dict[str, Any]:
        raise requests.HTTPError(f"401 from {token}")

    monkeypatch.setattr(remote_config, "_fetch", fetch)
    with caplog.at_level("DEBUG"):
        remote_config.run()
    text = " ".join(record.getMessage() for record in caplog.records)
    assert key["private_key_id"] not in text
    assert token not in text
    assert all(key["private_key_id"] not in str(call) for call in captured)
    assert all(token not in str(call) for call in captured)


def test_an_unparseable_service_account_is_unreachable(settings: Any, fetched: list[Any]) -> None:
    settings.FIREBASE_PROJECT_ID = PROJECT
    settings.REMOTE_CONFIG_SERVICE_ACCOUNT = "not json"
    assert remote_config.run().status == "unreachable"


def test_fetch_template_sends_the_token_and_reads_the_body(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    seen: dict[str, Any] = {}

    class Response:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, Any]:
            return {"version": {"versionNumber": "3"}, "parameters": {}}

    def get(url: str, headers: dict[str, str], timeout: int) -> Response:
        seen.update({"url": url, "headers": headers, "timeout": timeout})
        return Response()

    monkeypatch.setattr(requests, "get", get)
    body = remote_config.fetch_template(PROJECT, "ya29.fake")
    assert body["version"]["versionNumber"] == "3"
    assert seen["url"].endswith(f"/projects/{PROJECT}/remoteConfig")
    assert seen["headers"]["Authorization"] == "Bearer ya29.fake"
    assert seen["timeout"] == 10


def test_fetch_calls_the_token_step_first(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[str] = []

    def token(account: dict[str, Any]) -> str:
        calls.append("token")
        return "ya29.fake"

    def template(project_id: str, token_value: str) -> dict[str, Any]:
        calls.append("template")
        return {"version": {"versionNumber": "1"}, "parameters": {}}

    monkeypatch.setattr(remote_config, "fetch_token", token)
    monkeypatch.setattr(remote_config, "fetch_template", template)
    remote_config._fetch(PROJECT, {"client_email": EMAIL, "private_key": "k"})
    assert calls == ["token", "template"]


def test_the_account_needs_an_email_and_a_key(settings: Any) -> None:
    settings.FIREBASE_PROJECT_ID = PROJECT
    settings.REMOTE_CONFIG_SERVICE_ACCOUNT = "{}"
    assert remote_config.run().status == "unreachable"


def test_a_template_value_that_does_not_parse_is_recorded_as_drift(
    account: str, fetched: list[Any]
) -> None:
    fetched[0] = template({"fuel_max": "many"})
    row = remote_config.run()
    assert row.drift[0]["remote_config"] == "many"


def test_the_bool_parser() -> None:
    from apps.liveops import registry

    spec = registry.get("maintenance_enabled")
    assert remote_config._parse(spec, "true") is True
    assert remote_config._parse(spec, "no") is False
    assert remote_config._parse(registry.get("min_client_version_android"), "1.2.3") == "1.2.3"


def test_the_task_returns_its_status(settings: Any) -> None:
    from apps.liveops.tasks import check_remote_config

    settings.FIREBASE_PROJECT_ID = ""
    settings.REMOTE_CONFIG_SERVICE_ACCOUNT = ""
    assert check_remote_config.apply().get() == {"status": "not_configured", "drift": 0}
