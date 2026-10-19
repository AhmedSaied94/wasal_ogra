"""The admin needs a password and a TOTP code, and locks out guessing (FR-022, US3-6)."""

from datetime import timedelta

import pytest
from axes.models import AccessAttempt
from django.test import Client
from django.urls import NoReverseMatch, reverse
from django.utils import timezone
from django_otp.oath import TOTP
from django_otp.plugins.otp_totp.models import TOTPDevice

from apps.accounts.models import User

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

PASSWORD = "a-long-enough-password-1"
WRONG = "not-the-password-at-all"
LOGIN = "/admin/login/"
HOME = "203.0.113.50"


@pytest.fixture
def staff() -> User:
    return User.objects.create_user("ahmed", PASSWORD, is_staff=True)


def add_device(user: User) -> TOTPDevice:
    device: TOTPDevice = TOTPDevice.objects.create(user=user, name="default", confirmed=True)
    return device


def code(device: TOTPDevice) -> str:
    device.refresh_from_db()
    # django-otp refuses a code it has already accepted; forget that between sign-ins.
    TOTPDevice.objects.filter(pk=device.pk).update(last_t=-1)
    totp = TOTP(device.bin_key, device.step, device.t0, device.digits, device.drift)
    return str(totp.token()).zfill(device.digits)


def sign_in(
    username: str, password: str, otp_token: str = "", address: str = HOME
) -> tuple[Client, int]:
    client = Client(REMOTE_ADDR=address)
    response = client.post(
        LOGIN,
        {"username": username, "password": password, "otp_token": otp_token, "next": "/admin/"},
    )
    return client, response.status_code


def is_signed_in(client: Client) -> bool:
    return client.get("/admin/").status_code == 200


def test_staff_without_a_device_cannot_sign_in(staff: User) -> None:
    client, _ = sign_in("ahmed", PASSWORD, "123456")
    assert not is_signed_in(client)


def test_a_session_without_otp_verification_is_refused(staff: User) -> None:
    client = Client()
    client.force_login(staff)
    assert client.get("/admin/").status_code == 302


def test_valid_code_signs_in(staff: User) -> None:
    device = add_device(staff)
    client, status = sign_in("ahmed", PASSWORD, code(device))
    assert status == 302
    assert is_signed_in(client)


def test_username_is_case_insensitive(staff: User) -> None:
    device = add_device(staff)
    client, _ = sign_in("Ahmed", PASSWORD, code(device))
    assert is_signed_in(client)


@pytest.mark.parametrize("token", ["", "000000"])
def test_missing_or_wrong_code_is_refused(staff: User, token: str) -> None:
    add_device(staff)
    client, status = sign_in("ahmed", PASSWORD, token)
    assert status == 200  # the form again, with an error
    assert not is_signed_in(client)


@pytest.mark.parametrize(("is_staff", "is_active"), [(False, True), (True, False)])
def test_non_staff_or_inactive_is_refused(is_staff: bool, is_active: bool) -> None:
    user = User.objects.create_user("sara", PASSWORD, is_staff=is_staff, is_active=is_active)
    device = add_device(user)
    client, _ = sign_in("sara", PASSWORD, code(device))
    assert not is_signed_in(client)


def test_five_failures_lock_the_username(staff: User) -> None:
    device = add_device(staff)
    for attempt in range(5):
        sign_in("ahmed", WRONG, address=f"198.51.100.{attempt + 1}")
    client, status = sign_in("ahmed", PASSWORD, code(device), address="198.51.100.99")
    assert status == 429
    assert not is_signed_in(client)


def test_failures_in_any_letter_case_count_for_one_account(staff: User) -> None:
    device = add_device(staff)
    for attempt, name in enumerate(["ahmed", "AHMED", "Ahmed", "aHmed", "ahMED"]):
        sign_in(name, WRONG, address=f"198.51.100.{attempt + 1}")
    _, status = sign_in("ahmed", PASSWORD, code(device), address="198.51.100.99")
    assert status == 429


def test_five_failures_lock_the_address(staff: User) -> None:
    device = add_device(staff)
    for attempt in range(5):
        sign_in(f"nobody{attempt}", WRONG, address="198.51.100.7")
    _, status = sign_in("ahmed", PASSWORD, code(device), address="198.51.100.7")
    assert status == 429
    other, status = sign_in("ahmed", PASSWORD, code(device), address="198.51.100.8")
    assert is_signed_in(other)


def test_lock_lifts_after_fifteen_minutes(staff: User) -> None:
    device = add_device(staff)
    for _ in range(5):
        sign_in("ahmed", WRONG)
    assert sign_in("ahmed", PASSWORD, code(device))[1] == 429
    AccessAttempt.objects.update(attempt_time=timezone.now() - timedelta(minutes=16))
    client, _ = sign_in("ahmed", PASSWORD, code(device))
    assert is_signed_in(client)


def test_success_resets_the_counter(staff: User) -> None:
    device = add_device(staff)
    for _ in range(4):
        sign_in("ahmed", WRONG)
    assert is_signed_in(sign_in("ahmed", PASSWORD, code(device))[0])
    for _ in range(4):
        sign_in("ahmed", WRONG)
    assert is_signed_in(sign_in("ahmed", PASSWORD, code(device))[0])


@pytest.mark.parametrize("name", ["admin_password_reset", "password_reset", "signup"])
def test_no_self_service_urls(name: str) -> None:
    with pytest.raises(NoReverseMatch):
        reverse(name)


def test_beat_schedules_are_on_the_admin(staff: User) -> None:
    staff.is_superuser = True
    staff.save()
    client, _ = sign_in("ahmed", PASSWORD, code(add_device(staff)))
    page = client.get("/admin/django_celery_beat/periodictask/")
    assert page.status_code == 200
    assert b"heartbeat" in page.content


def test_several_devices_need_an_explicit_choice(staff: User) -> None:
    """The one-device shortcut never tries a code against several devices (django-otp 1.7)."""
    first = add_device(staff)
    TOTPDevice.objects.create(user=staff, name="spare", confirmed=True)
    client, _ = sign_in("ahmed", PASSWORD, code(first))
    assert not is_signed_in(client)
