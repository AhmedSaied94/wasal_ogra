"""Error tracking without personal data (FR-024, FR-035, research R7)."""

import io
import json
import os
import subprocess
import sys
from unittest import mock

import pytest
from django.conf import settings
from django.core.management import CommandError, call_command
from sentry_sdk.integrations.celery import CeleryIntegration
from sentry_sdk.integrations.django import DjangoIntegration
from sentry_sdk.integrations.logging import LoggingIntegration
from sentry_sdk.types import Event

from apps.common import sentry
from apps.common.logging import request_id
from apps.common.tasks import SentryTestError
from apps.common.tasks import sentry_test as sentry_test_task

DSN = "https://public@sentry.invalid/1"


def event() -> Event:
    return {
        "request": {
            "url": "https://api.example.test/v1/things",
            "method": "POST",
            "headers": {"Authorization": "Bearer t"},
            "cookies": {"sessionid": "c"},
            "data": {"password": "p"},
            "env": {"REMOTE_ADDR": "203.0.113.9"},
            "query_string": "token=q",
        },
        "user": {"id": "u1", "ip_address": "203.0.113.9"},
    }


@pytest.mark.parametrize("hook", ["before_send", "before_send_transaction"])
def test_the_scrubber_removes_personal_data(hook: str) -> None:
    scrubbed = sentry.scrub(event(), {})

    assert scrubbed is not None
    assert scrubbed["request"] == {"url": "https://api.example.test", "method": "POST"}
    assert scrubbed["user"] == {"id": "u1"}
    assert "203.0.113.9" not in json.dumps(scrubbed)


def test_raw_paths_never_leave_the_server() -> None:
    raw = "/v1/things/5f0c1d2e-7a1b-4c3d-9e8f-0a1b2c3d4e5f"
    scrubbed = sentry.scrub(
        {
            "logger": "django.request",
            "logentry": {"message": "Internal Server Error: %s", "params": [raw]},
            "request": {"url": f"https://api.example.test{raw}?token=q", "method": "GET"},
            "breadcrumbs": {
                "values": [
                    {"category": "django.request", "message": f"Not Found: {raw}"},
                    {"category": "query", "message": "SELECT 1"},
                ]
            },
        },
        {},
    )

    assert scrubbed is not None
    assert raw not in json.dumps(scrubbed)
    assert scrubbed["logentry"]["formatted"] == "Internal Server Error: <path>"
    assert json.loads(json.dumps(scrubbed["breadcrumbs"])) == {
        "values": [{"category": "query", "message": "SELECT 1"}]
    }


def test_outgoing_urls_keep_only_their_origin() -> None:
    secret = "https://hc-ping.com/0b7e3f6a-secret-uuid"
    crumb = sentry.scrub_breadcrumb(
        {
            "category": "httplib",
            "type": "http",
            "data": {"url": secret, "method": "POST", "http.query": "a=b", "status_code": 200},
        },
        {},
    )

    assert crumb is not None
    assert crumb["data"] == {"url": "https://hc-ping.com", "method": "POST", "status_code": 200}


def test_the_scrubber_tags_the_request_id() -> None:
    token = request_id.set("req-12345678")
    try:
        scrubbed = sentry.scrub(event(), {})
    finally:
        request_id.reset(token)

    assert scrubbed is not None
    assert scrubbed["tags"]["request_id"] == "req-12345678"


def test_the_scrubber_handles_events_without_a_request() -> None:
    assert sentry.scrub({"message": "boom"}, {}) == {"message": "boom"}


def test_no_dsn_means_no_sentry() -> None:
    with mock.patch("apps.common.sentry.sentry_sdk.init") as init:
        assert (
            sentry.init_sentry("", environment="prod", release="r", traces_sample_rate=0.05)
            is False
        )
    init.assert_not_called()


def test_init_passes_the_privacy_options() -> None:
    with mock.patch("apps.common.sentry.sentry_sdk.init") as init:
        assert sentry.init_sentry(DSN, environment="prod", release="abc", traces_sample_rate=0.07)

    options = init.call_args.kwargs
    assert options["dsn"] == DSN
    assert options["environment"] == "prod"
    assert options["release"] == "abc"
    assert options["send_default_pii"] is False
    assert options["include_local_variables"] is False
    assert options["max_request_body_size"] == "never"
    assert options["traces_sample_rate"] == 0.07
    assert options["before_send"] is sentry.scrub
    assert options["before_send_transaction"] is sentry.scrub
    assert options["before_breadcrumb"] is sentry.scrub_breadcrumb
    kinds = {type(integration) for integration in options["integrations"]}
    assert {DjangoIntegration, CeleryIntegration, LoggingIntegration} <= kinds


def test_settings_start_sentry_when_a_dsn_is_set() -> None:
    probe = (
        "import django, sentry_sdk; django.setup(); "
        "client = sentry_sdk.get_client(); "
        "print(client.is_active(), client.options['environment'], client.options['release'])"
    )
    env = {**os.environ, "SENTRY_DSN": DSN, "RELEASE": "probe-release"}
    result = subprocess.run(  # noqa: S603 - fixed interpreter and arguments
        [sys.executable, "-c", probe],
        cwd=settings.BASE_DIR,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    # Earlier stdout lines are JSON log lines; the probe prints last.
    assert result.stdout.splitlines()[-1].split() == ["True", "test", "probe-release"]


COMMAND = "apps.common.management.commands.sentry_test.sentry_sdk"


def test_sentry_test_sends_a_tagged_error() -> None:
    out = io.StringIO()
    with (
        mock.patch(f"{COMMAND}.capture_exception", return_value="event-1") as capture,
        mock.patch(f"{COMMAND}.flush") as flush,
    ):
        call_command("sentry_test", stdout=out)

    [error] = capture.call_args.args
    assert isinstance(error, SentryTestError)
    assert capture.call_args.kwargs["tags"] == {"sentry_test": "command"}
    flush.assert_called_once()
    assert "event-1" in out.getvalue()


def test_sentry_test_fails_without_a_dsn() -> None:
    with pytest.raises(CommandError, match="SENTRY_DSN"):
        call_command("sentry_test")


def test_sentry_test_task_queues_the_test_task() -> None:
    with mock.patch.object(sentry_test_task, "apply_async") as apply_async:
        call_command("sentry_test", "--task")

    apply_async.assert_called_once_with(queue="default")


def test_the_test_task_raises() -> None:
    assert sentry_test_task.name == "common.tasks.sentry_test"
    with pytest.raises(SentryTestError):
        sentry_test_task.run()
