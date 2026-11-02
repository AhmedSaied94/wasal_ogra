"""Maintenance pauses writes, not reads (B10 US4, FR-015 to FR-018, contracts/api.md)."""

from __future__ import annotations

import uuid
from collections.abc import Callable
from datetime import UTC, timedelta

import pytest
import time_machine
from django.utils import timezone

from apps.accounts.models import Player, User
from apps.economy.models import ProcessedOp
from apps.economy.services import ledger
from apps.economy.tests.helpers import Api, batch, op, signed_in_api
from apps.liveops import registry
from apps.liveops import settings as live
from apps.liveops.models import LiveopsChange, LiveSetting
from apps.liveops.services import maintenance, settings_admin

pytestmark = pytest.mark.django_db

ENVELOPE = op("settings_update", {"settings": {"sound": True}})


@pytest.fixture
def api() -> Api:
    return signed_in_api()


@pytest.fixture
def actor() -> User:
    return User.objects.create_user("ops", is_staff=True)


def error_of(response: object) -> dict[str, object]:
    return response.json()["error"]  # type: ignore[attr-defined,no-any-return]


def test_a_write_while_on_answers_503_and_applies_nothing(
    api: Api, live_settings: Callable[..., None]
) -> None:
    live_settings(maintenance_enabled=True)
    response = api.sync(batch(ENVELOPE))
    assert response.status_code == 503
    assert error_of(response) == {
        "code": "maintenance",
        "message": "Down for maintenance",
        "details": {},
    }
    assert not ProcessedOp.objects.exists()


def test_a_link_while_on_answers_503(api: Api, live_settings: Callable[..., None]) -> None:
    live_settings(maintenance_enabled=True)
    response = api.client.post(
        "/v1/auth/link",
        data={"provider": "google", "id_token": "x"},
        content_type="application/json",
        headers=api.headers,
    )
    assert response.status_code == 503


def test_the_end_time_is_in_the_details_only_when_it_is_in_the_future(
    api: Api, live_settings: Callable[..., None]
) -> None:
    until = timezone.now() + timedelta(minutes=20)
    live_settings(maintenance_enabled=True, maintenance_until=until)
    details = error_of(api.sync(batch(ENVELOPE)))["details"]
    assert isinstance(details, dict)
    assert details["until"] == until.astimezone(UTC).isoformat().replace("+00:00", "Z")
    with time_machine.travel(until + timedelta(minutes=1), tick=False):
        assert error_of(api.sync(batch(ENVELOPE)))["details"] == {}


def test_reads_go_on(api: Api, live_settings: Callable[..., None]) -> None:
    live_settings(maintenance_enabled=True)
    assert api.bootstrap().status_code == 200
    assert api.state().status_code == 200
    assert api.client.get("/v1/offers", headers=api.headers).status_code == 200
    assert api.client.get("/v1/content/manifest", headers=api.headers).status_code == 200
    anonymous = api.client.post(
        "/v1/auth/anonymous",
        data={"install_id": str(uuid.uuid4()), "platform": "android", "locale": "ar-EG"},
        content_type="application/json",
        headers=api.headers,
    )
    assert anonymous.status_code == 201
    refresh = api.client.post(
        "/v1/auth/refresh",
        data={"refresh": "x"},
        content_type="application/json",
        headers=api.headers,
    )
    assert refresh.status_code == 401  # not 503


def test_a_request_already_inside_the_view_completes(
    api: Api, monkeypatch: pytest.MonkeyPatch
) -> None:
    live.refresh()
    real = ledger.lock_wallet

    def lock(*args: object, **kwargs: object) -> object:
        # The switch flips after the permission check has already passed.
        LiveSetting.objects.filter(key="maintenance_enabled").update(value=True)
        live.refresh()
        return real(*args, **kwargs)  # type: ignore[arg-type]

    monkeypatch.setattr(ledger, "lock_wallet", lock)
    assert api.sync(batch(ENVELOPE)).status_code == 200


def test_the_switch_writes_two_changes(actor: User) -> None:
    maintenance.switch(True, actor=actor, note="deploy")
    maintenance.switch(False, actor=actor, note="done")
    changes = LiveopsChange.objects.filter(key="maintenance_enabled").order_by("at")
    assert [(change.old, change.new) for change in changes] == [(False, True), (True, False)]


def test_an_end_without_enabling_is_refused(actor: User) -> None:
    until = timezone.now() + timedelta(hours=1)
    with pytest.raises(registry.RuleBroken, match="Set an end time in the future"):
        settings_admin.change("maintenance_until", until, actor)


def test_an_end_in_the_past_is_refused(actor: User) -> None:
    past = timezone.now() - timedelta(minutes=1)
    with pytest.raises(registry.RuleBroken, match="Set an end time in the future"):
        settings_admin.change_many({"maintenance_enabled": True, "maintenance_until": past}, actor)


def test_a_refused_batch_is_applied_once_after_the_switch_off(
    api: Api, actor: User, live_settings: Callable[..., None]
) -> None:
    live_settings(maintenance_enabled=True)
    assert api.sync(batch(ENVELOPE)).status_code == 503
    assert not ProcessedOp.objects.exists()

    settings_admin.change("maintenance_enabled", False, actor)
    live.refresh()
    first = api.sync(batch(ENVELOPE))
    assert first.status_code == 200
    assert [result["status"] for result in first.json()["results"]] == ["accepted"]
    assert ProcessedOp.objects.count() == 1

    third = api.sync(batch(ENVELOPE))
    assert third.status_code == 200
    assert third.json()["results"] == first.json()["results"]
    assert ProcessedOp.objects.count() == 1
    assert Player.objects.get(pk=api.player_id).settings == {"sound": True}
