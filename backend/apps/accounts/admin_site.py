"""The staff admin: password plus TOTP code, on the private network only (FR-022, research R5)."""

from __future__ import annotations

from typing import Any

from django_otp import devices_for_user
from django_otp.admin import OTPAdminAuthenticationForm, OTPAdminSite


class StaffAuthenticationForm(OTPAdminAuthenticationForm):  # type: ignore[misc]  # untyped lib
    """Uses the staff member's one device when the form names none.

    django-otp 1.7 makes the form name the device, so a wrong code isn't tried against every
    device a user has. Staff have exactly one (`staff_totp` enforces it), so that choice is made
    for them, and a user with several devices still has to pick one.
    """

    def _chosen_device(self, user: Any) -> Any:
        device = super()._chosen_device(user)
        if device is None and not self.cleaned_data.get("otp_device"):
            devices = list(devices_for_user(user, confirmed=True, for_verify=True))
            if len(devices) == 1:
                return devices[0]
        return device


class StaffAdminSite(OTPAdminSite):  # type: ignore[misc]  # django-otp has no type hints
    """Every page needs an OTP-verified staff session. It is the project's default admin site, so
    every `admin.register` call, ours and the libraries', lands here (`StaffAdminConfig`)."""

    login_form = StaffAuthenticationForm
    site_header = "wassal admin"
    site_title = "wassal admin"
    index_title = "Administration"

    def __init__(self, name: str = "admin") -> None:
        super().__init__(name)
