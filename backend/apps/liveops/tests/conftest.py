"""Staff clients for the live-ops admin pages (B10 contracts/admin.md)."""

from __future__ import annotations

import pytest
from django.contrib.auth.models import Group, Permission
from django.test import Client

from apps.accounts.models import User
from apps.content.tests.conftest import admin_client


def staff(username: str, group: str | None = None, *permissions: str) -> Client:
    """A staff user in `group`, holding extra `permissions` when a test needs a subset."""
    user = User.objects.create_user(username, is_staff=True)
    if group:
        user.groups.add(Group.objects.get(name=group))
    if permissions:
        user.user_permissions.add(*Permission.objects.filter(codename__in=permissions))
    return admin_client(user)


@pytest.fixture
def live_ops() -> Client:
    return staff("liveops1", "live_ops")


@pytest.fixture
def support() -> Client:
    return staff("support1", "player_support")


@pytest.fixture
def author() -> Client:
    return staff("author1", "content_author")
