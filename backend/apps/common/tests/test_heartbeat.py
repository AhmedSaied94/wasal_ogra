"""The scheduler -> broker -> worker heartbeat (FR-006, FR-007, contracts/operations.md
"Heartbeat")."""

import inspect
import threading
import time
from typing import Any
from unittest import mock

import pytest
import redis
import requests
from celery.contrib.testing.worker import start_worker
from django.conf import settings
from django_celery_beat.models import IntervalSchedule, PeriodicTask
from pytest_django import Settings

from apps.common.tasks import heartbeat
from config.celery import app

PING_URL = "https://hc.invalid/ping/heartbeat"


def ok_response() -> requests.Response:
    response = requests.Response()
    response.status_code = 200
    return response


def test_task_registration_and_retry_policy() -> None:
    task: Any = heartbeat  # the stubs don't declare the autoretry options
    assert task.name == "common.tasks.heartbeat"
    # bind=True: the original function is bound to the task (autoretry replaces `run` itself).
    assert inspect.ismethod(task.__wrapped__)
    assert task.max_retries == 3
    assert task.autoretry_for == (requests.RequestException,)
    assert task.retry_backoff


def test_pings_the_configured_url(settings: Settings) -> None:
    settings.HC_PING_HEARTBEAT_URL = PING_URL
    with mock.patch("requests.get", return_value=ok_response()) as get:
        heartbeat.apply()
    get.assert_called_once_with(PING_URL, timeout=10, allow_redirects=False)


def test_does_nothing_without_a_url(settings: Settings) -> None:
    settings.HC_PING_HEARTBEAT_URL = ""
    with mock.patch("requests.get") as get:
        heartbeat.apply()
    get.assert_not_called()


def test_connection_error_is_retried(settings: Settings) -> None:
    settings.HC_PING_HEARTBEAT_URL = PING_URL
    side_effect = [requests.ConnectionError("down"), ok_response()]
    with mock.patch("requests.get", side_effect=side_effect) as get:
        heartbeat.apply()
    assert get.call_count == 2


def test_round_trip_through_the_real_broker(settings: Settings) -> None:
    settings.HC_PING_HEARTBEAT_URL = PING_URL
    # The test broker (Valkey db 3) is ours alone. Start without queues or bindings from older runs.
    redis.Redis.from_url(settings.CELERY_BROKER_URL).flushdb()
    pinged = threading.Event()
    pings: list[str] = []

    def record(url: str, **kwargs: object) -> requests.Response:
        pings.append(url)
        pinged.set()
        return ok_response()

    with (
        mock.patch("requests.get", side_effect=record),
        start_worker(app, pool="solo", perform_ping_check=False, shutdown_timeout=10),
    ):
        heartbeat.delay()
        assert pinged.wait(timeout=10), "the worker never ran the heartbeat"
        # A message bound to several queues would run more than once.
        time.sleep(1)
    assert pings == [PING_URL]


@pytest.mark.django_db
def test_schedule_created_by_migration() -> None:
    task = PeriodicTask.objects.select_related("interval").get(name="heartbeat")
    assert PeriodicTask.objects.filter(name="heartbeat").count() == 1
    assert task.enabled
    assert task.task == "common.tasks.heartbeat"
    assert task.queue == "default"
    assert task.interval is not None
    assert (task.interval.every, task.interval.period) == (5, IntervalSchedule.MINUTES)


def test_queues_and_scheduler() -> None:
    assert [queue.name for queue in settings.CELERY_TASK_QUEUES] == [
        "default",
        "purchases",
        "content",
        "push",
    ]
    assert settings.CELERY_TASK_DEFAULT_QUEUE == "default"


def test_each_queue_has_its_own_route() -> None:
    """Otherwise one message lands in every queue that shares the route, and runs once per queue."""
    routes = [(queue.exchange.name, queue.routing_key) for queue in app.amqp.queues.values()]
    assert len(set(routes)) == len(routes) == 4
    assert settings.CELERY_BEAT_SCHEDULER == "django_celery_beat.schedulers:DatabaseScheduler"
