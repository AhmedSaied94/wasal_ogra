"""`create_staff --group` (B04 tasks.md T068, contracts/admin.md "Roles")."""

from io import StringIO
from unittest import mock

import pytest
from django.contrib.auth.models import Group
from django.core.management import CommandError, call_command

from apps.accounts.models import User

pytestmark = pytest.mark.django_db

PASSWORD = "a-long-enough-password-1"


def run(*args: str) -> str:
    out = StringIO()
    with mock.patch("getpass.getpass", side_effect=[PASSWORD, PASSWORD]):
        call_command("create_staff", *args, stdout=out)
    return out.getvalue()


def test_groups_are_given_at_creation() -> None:
    Group.objects.get_or_create(name="content_author")
    Group.objects.get_or_create(name="content_publisher")

    output = run("owner", "--group", "content_author", "--group", "content_publisher")

    user = User.objects.get(username="owner")
    assert sorted(user.groups.values_list("name", flat=True)) == [
        "content_author",
        "content_publisher",
    ]
    assert "in content_author, content_publisher" in output


def test_an_unknown_group_is_refused_before_anything_is_created() -> None:
    with pytest.raises(CommandError, match="Unknown group"):
        run("owner", "--group", "content_editors")

    assert not User.objects.exists()


def test_no_group_is_the_default() -> None:
    run("plain")

    assert not User.objects.get(username="plain").groups.exists()
