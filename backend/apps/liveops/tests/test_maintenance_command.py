"""The `maintenance` command (B10 contracts/admin.md "Command", FR-033)."""

from __future__ import annotations

from datetime import timedelta
from io import StringIO

import pytest
from django.contrib.auth.models import Group
from django.core.management import call_command
from django.core.management.base import CommandError
from django.utils import timezone

from apps.accounts.models import User
from apps.liveops import settings as live
from apps.liveops.models import LiveopsChange
from apps.liveops.services import maintenance

pytestmark = pytest.mark.django_db


@pytest.fixture
def actor() -> User:
    user = User.objects.create_user("ops", is_staff=True)
    user.groups.add(Group.objects.get(name="live_ops"))
    return user


def run(*args: str) -> str:
    out = StringIO()
    call_command("maintenance", *args, stdout=out)
    return out.getvalue()


def refused(*args: str) -> CommandError:
    with pytest.raises(CommandError) as raised:
        call_command("maintenance", *args)
    return raised.value


def test_status_prints_off() -> None:
    assert "Maintenance is off." in run("status")


def test_on_with_an_end_and_a_note(actor: User) -> None:
    until = (timezone.now() + timedelta(hours=2)).replace(microsecond=0)
    output = run(
        "on",
        "--actor",
        actor.username,
        "--until",
        until.isoformat(),
        "--note",
        "deploy",
    )
    live.refresh()
    assert live.current()["maintenance_enabled"] is True
    assert live.current()["maintenance_until"] == until
    assert "applies within 60 s" in output
    change = LiveopsChange.objects.get(key="maintenance_enabled")
    assert (change.new, change.source) == (True, LiveopsChange.Source.COMMAND)
    assert change.note == "deploy"


def test_off(actor: User) -> None:
    maintenance.switch(True, actor=actor)
    assert "Maintenance is off." in run("off", "--actor", actor.username)
    live.refresh()
    assert live.current()["maintenance_enabled"] is False


def test_an_unknown_actor_exits_2_and_changes_nothing() -> None:
    assert refused("on", "--actor", "ghost").returncode == 2
    assert not LiveopsChange.objects.exists()


def test_a_user_without_the_permission_exits_2() -> None:
    user = User.objects.create_user("plain", is_staff=True)
    assert refused("on", "--actor", user.username).returncode == 2
    assert not LiveopsChange.objects.exists()


def test_an_inactive_user_exits_2(actor: User) -> None:
    User.objects.filter(pk=actor.pk).update(is_active=False)
    assert refused("on", "--actor", actor.username).returncode == 2


@pytest.mark.parametrize("until", ["2030-01-01T00:00", "soon", "2030-13-01T00:00Z"])
def test_an_end_without_a_zone_or_in_the_past_exits_2(until: str, actor: User) -> None:
    assert refused("on", "--actor", actor.username, "--until", until).returncode == 2
    assert not LiveopsChange.objects.exists()


def test_an_end_in_the_past_exits_2(actor: User) -> None:
    past = (timezone.now() - timedelta(hours=1)).isoformat()
    assert refused("on", "--actor", actor.username, "--until", past).returncode == 2


def test_a_superuser_may_switch() -> None:
    superuser = User.objects.create_superuser("root")
    run("on", "--actor", superuser.username)
    live.refresh()
    assert live.current()["maintenance_enabled"] is True
