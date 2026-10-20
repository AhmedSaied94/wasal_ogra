"""`services.permissions` (research R9, FR-019)."""

from __future__ import annotations

import pytest
from django.core.exceptions import PermissionDenied
from pytest_django import Settings

from apps.accounts.models import User
from apps.content.services import permissions

pytestmark = pytest.mark.django_db


def test_a_member_with_the_permission_passes(author: User) -> None:
    assert permissions.require(author, "content.build_pack") is author


def test_a_missing_permission_is_named(publisher: User) -> None:
    with pytest.raises(PermissionDenied, match=r"content\.build_pack is required"):
        permissions.require(publisher, "content.build_pack")


def test_an_inactive_or_absent_actor_is_refused(inactive_author: User) -> None:
    for actor in (inactive_author, None):
        with pytest.raises(PermissionDenied, match="needs an active staff account"):
            permissions.require(actor, "content.build_pack")


def test_a_non_staff_member_is_refused(author: User) -> None:
    author.is_staff = False

    with pytest.raises(PermissionDenied, match="needs an active staff account"):
        permissions.require(author, "content.build_pack")


def test_the_role_comes_from_the_settings(settings: Settings) -> None:
    assert permissions.role() == "source"
    permissions.require_role("source")

    settings.CONTENT_ROLE = "target"
    with pytest.raises(PermissionDenied, match="CONTENT_ROLE=target"):
        permissions.require_role("source")
