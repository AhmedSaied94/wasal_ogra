"""Every settings write is validated, attributed and recorded (B10 research R14, spec FR-006)."""

from __future__ import annotations

import threading
from collections.abc import Callable
from typing import Any, cast

import pytest
from django.contrib.auth.models import Group, Permission
from django.db import connection

from apps.accounts.models import User
from apps.liveops import registry
from apps.liveops import settings as live
from apps.liveops.models import AppendOnlyError, LiveopsChange, LiveSetting
from apps.liveops.services import settings_admin


@pytest.fixture
def actor(db: None) -> User:
    return User.objects.create_user("ops", is_staff=True)


@pytest.fixture
def on_commit(django_capture_on_commit_callbacks: Any) -> Callable[..., Any]:
    return cast("Callable[..., Any]", django_capture_on_commit_callbacks)


def test_change_writes_the_row_and_one_history_row(actor: User) -> None:
    settings_admin.change("fuel_max", 6, actor, note="tank up")
    assert LiveSetting.objects.get(key="fuel_max").value == 6
    [change] = LiveopsChange.objects.filter(key="fuel_max")
    assert change.target == LiveopsChange.Target.SETTING
    assert (change.old, change.new) == (5, 6)
    assert change.source == LiveopsChange.Source.ADMIN
    assert change.actor == actor
    assert change.note == "tank up"


def test_the_saving_process_sees_its_change_at_once(
    actor: User, on_commit: Callable[..., Any]
) -> None:
    live.refresh()
    with on_commit(execute=True):
        settings_admin.change("fuel_max", 6, actor)
    assert live.current()["fuel_max"] == 6


def test_a_refused_value_writes_neither_row(actor: User) -> None:
    with pytest.raises(ValueError, match="at most 20"):
        settings_admin.change("fuel_max", 21, actor)
    assert LiveSetting.objects.get(key="fuel_max").value == 5
    assert not LiveopsChange.objects.exists()


def test_a_rule_break_writes_neither_row(actor: User) -> None:
    with pytest.raises(registry.RuleBroken, match="subscriber's tank"):
        settings_admin.change("fuel_max_subscriber", 3, actor)
    assert LiveSetting.objects.get(key="fuel_max_subscriber").value == 7
    assert not LiveopsChange.objects.exists()


def test_change_many_checks_the_rules_once(actor: User) -> None:
    # Neither step is valid alone against the current values; both together are.
    settings_admin.change_many(
        {"min_duration_percent": 99, "fast_run_percent": 99}, actor, note="stricter"
    )
    assert live.current()["min_duration_percent"] == 99
    assert live.current()["fast_run_percent"] == 99
    assert LiveopsChange.objects.count() == 2


def test_change_many_refuses_the_whole_batch(actor: User) -> None:
    with pytest.raises(ValueError, match="fast-run"):
        settings_admin.change_many({"min_duration_percent": 90, "fast_run_percent": 80}, actor)
    assert LiveSetting.objects.get(key="min_duration_percent").value == 85
    assert not LiveopsChange.objects.exists()


def test_reset_writes_the_default_as_a_reset(
    live_settings: Callable[..., None], actor: User
) -> None:
    live_settings(fuel_max=6)
    settings_admin.reset("fuel_max", actor, note="back")
    assert LiveSetting.objects.get(key="fuel_max").value == 5
    change = LiveopsChange.objects.filter(key="fuel_max").latest("at")
    assert (change.old, change.new, change.source) == (6, 5, LiveopsChange.Source.RESET)


def test_an_existing_change_cannot_be_saved_again(actor: User) -> None:
    settings_admin.change("fuel_max", 6, actor)
    change = LiveopsChange.objects.get()
    change.note = "edited"
    with pytest.raises(AppendOnlyError):
        change.save()
    with pytest.raises(AppendOnlyError):
        change.delete()


@pytest.mark.django_db
def test_no_group_can_change_or_delete_the_history() -> None:
    assert not Permission.objects.filter(
        group__isnull=False,
        content_type__app_label="liveops",
        codename__in=("change_liveopschange", "delete_liveopschange"),
    ).exists()
    assert Group.objects.filter(name="live_ops").exists()


@pytest.mark.django_db(transaction=True)
def test_two_operators_saving_related_keys_cannot_both_pass() -> None:
    actor = User.objects.create_user("ops", is_staff=True)
    outcomes: list[str] = []
    barrier = threading.Barrier(2)

    def save(key: str, value: int) -> None:
        try:
            barrier.wait(timeout=10)
            settings_admin.change(key, value, actor)
            outcomes.append("applied")
        except registry.RuleBroken as error:
            outcomes.append(str(error))
        finally:
            connection.close()

    threads = [
        threading.Thread(target=save, args=("fuel_max", 8)),
        threading.Thread(target=save, args=("fuel_max_subscriber", 6)),
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=20)

    assert sorted(outcomes) == sorted(
        ["applied", "The subscriber's tank can't be smaller than the normal tank."]
    )
    values = dict(LiveSetting.objects.values_list("key", "value"))
    assert (values["fuel_max"], values["fuel_max_subscriber"]) in {(8, 7), (5, 6)}


@pytest.mark.django_db(transaction=True)
def test_two_saves_of_the_same_key_are_both_in_the_history() -> None:
    actor = User.objects.create_user("ops", is_staff=True)
    settings_admin.change("fuel_max", 6, actor)
    settings_admin.change("fuel_max", 7, actor)
    assert [change.new for change in LiveopsChange.objects.filter(key="fuel_max")] == [7, 6]
    assert LiveSetting.objects.get(key="fuel_max").value == 7


def test_change_many_does_nothing_for_no_values(actor: User) -> None:
    assert settings_admin.change_many({}, actor) == []


def test_candidate_for_falls_back_to_the_default_of_a_bad_row(actor: User) -> None:
    LiveSetting.objects.filter(key="fuel_max").update(value="many")
    candidate = settings_admin.candidate_for("fuel_max", 6)
    assert candidate["fuel_max"] == 6
    assert candidate["fuel_max_subscriber"] == 7


def test_a_change_ignores_a_bad_stored_rule_value(actor: User) -> None:
    LiveSetting.objects.filter(key="fuel_max_subscriber").update(value="many")
    settings_admin.change("fuel_max", 6, actor)
    assert LiveSetting.objects.get(key="fuel_max").value == 6


def test_a_change_of_a_key_without_a_row_records_the_default(actor: User) -> None:
    LiveSetting.objects.filter(key="fuel_max").delete()
    settings_admin.change("fuel_max", 6, actor)
    change = LiveopsChange.objects.get(key="fuel_max")
    assert (change.old, change.new) == (5, 6)
