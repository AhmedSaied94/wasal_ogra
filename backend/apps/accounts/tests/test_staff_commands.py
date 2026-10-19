"""Staff accounts are created from the command line only (data-model "Lifecycle")."""

from io import StringIO
from unittest import mock

import pytest
from django.core.management import CommandError, call_command
from django_otp.plugins.otp_totp.models import TOTPDevice

from apps.accounts.models import User

pytestmark = pytest.mark.django_db

PASSWORD = "a-long-enough-password-1"


def run(*args: str, passwords: tuple[str, ...] = (PASSWORD, PASSWORD)) -> str:
    out = StringIO()
    with mock.patch("getpass.getpass", side_effect=list(passwords)):
        call_command(*args, stdout=out)
    return out.getvalue()


def test_create_staff_makes_an_active_staff_user_without_a_device() -> None:
    output = run("create_staff", "ahmed")
    user = User.objects.get(username="ahmed")
    assert (user.is_staff, user.is_active, user.is_superuser) == (True, True, False)
    assert user.check_password(PASSWORD)
    assert not TOTPDevice.objects.filter(user=user).exists()
    assert PASSWORD not in output


def test_create_staff_superuser() -> None:
    run("create_staff", "root.user", "--superuser")
    assert User.objects.get(username="root.user").is_superuser


def test_existing_username_is_refused() -> None:
    User.objects.create_user("ahmed", PASSWORD)
    with pytest.raises(CommandError, match="already exists"):
        run("create_staff", "Ahmed")


def test_invalid_username_is_refused() -> None:
    with pytest.raises(CommandError, match="username"):
        run("create_staff", "ab")
    assert not User.objects.exists()


@pytest.mark.parametrize(
    "passwords", [("password1234", "password1234"), (PASSWORD, PASSWORD + "x")]
)
def test_weak_or_mismatched_password_is_refused(passwords: tuple[str, str]) -> None:
    with pytest.raises(CommandError):
        run("create_staff", "ahmed", passwords=passwords)
    assert not User.objects.exists()


def test_deactivate_an_existing_user() -> None:
    User.objects.create_user("ahmed", PASSWORD, is_staff=True)
    run("create_staff", "ahmed", "--deactivate", passwords=())
    assert not User.objects.get(username="ahmed").is_active


def test_deactivate_an_unknown_user_is_refused() -> None:
    with pytest.raises(CommandError, match="no staff user"):
        run("create_staff", "ghost", "--deactivate", passwords=())


def test_staff_totp_issues_one_confirmed_device() -> None:
    user = User.objects.create_user("ahmed", PASSWORD, is_staff=True)
    output = run("staff_totp", "ahmed", passwords=())
    device = TOTPDevice.objects.get(user=user)
    assert (device.name, device.confirmed) == ("default", True)
    assert output.count("otpauth://totp/") == 1
    assert device.config_url in output


def test_staff_totp_refuses_a_second_device_without_reset() -> None:
    User.objects.create_user("ahmed", PASSWORD, is_staff=True)
    run("staff_totp", "ahmed", passwords=())
    with pytest.raises(CommandError, match="--reset"):
        run("staff_totp", "ahmed", passwords=())
    assert TOTPDevice.objects.count() == 1


def test_staff_totp_reset_replaces_the_device() -> None:
    user = User.objects.create_user("ahmed", PASSWORD, is_staff=True)
    run("staff_totp", "ahmed", passwords=())
    old_key = TOTPDevice.objects.get(user=user).key
    run("staff_totp", "ahmed", "--reset", passwords=())
    devices = list(TOTPDevice.objects.filter(user=user))
    assert len(devices) == 1
    assert devices[0].key != old_key


def test_staff_totp_unknown_user_is_refused() -> None:
    with pytest.raises(CommandError, match="no staff user"):
        run("staff_totp", "ghost", passwords=())
