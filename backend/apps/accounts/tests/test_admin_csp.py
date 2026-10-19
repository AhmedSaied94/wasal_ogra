"""The edge's admin CSP allows exactly the admin's inline scripts (FR-019, research R5).

`script-src` has no `'unsafe-inline'`, so every inline script an admin page renders needs its hash
in the CSP, or the browser blocks it. A library upgrade that changes one of those scripts fails
here instead of breaking a page quietly.
"""

import base64
import hashlib
import re
from html.parser import HTMLParser

import pytest
from django.conf import settings
from django.test import Client
from django_celery_beat.models import PeriodicTask
from django_otp.oath import TOTP
from django_otp.plugins.otp_totp.models import TOTPDevice

from apps.accounts.models import User

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

EDGE = settings.BASE_DIR / "docker" / "edge"
CSP_LINE = re.compile(r'header Content-Security-Policy "([^"]+)"')
PASSWORD = "a-long-enough-password-1"
# Data blocks the browser never runs, so CSP doesn't apply to them. Any other type counts as a
# script, the conservative reading: import maps and speculation rules fall under script-src too.
DATA_TYPES = ("application/json", "application/ld+json")


class InlineScripts(HTMLParser):
    """Collects inline script bodies, inline event handlers and `javascript:` URLs."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.scripts: list[str] = []
        self.handlers: list[str] = []
        self._current: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        self.handlers += [name for name, _ in attrs if name.startswith("on")]
        self.handlers += [
            f"{name}={value}"
            for name, value in attrs
            if value and value.strip().lower().startswith("javascript:")
        ]
        kind = (values.get("type") or "").split(";")[0].strip().lower()
        is_inline = "src" not in values and kind not in DATA_TYPES
        if tag == "script" and is_inline:
            self._current = []

    def handle_data(self, data: str) -> None:
        if self._current is not None:
            self._current.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self._current is not None:
            self.scripts.append("".join(self._current))
            self._current = None


def csp_hash(script: str) -> str:
    digest = hashlib.sha256(script.encode()).digest()
    return f"'sha256-{base64.b64encode(digest).decode()}'"


def admin_csp(caddyfile: str) -> str:
    policies = CSP_LINE.findall((EDGE / caddyfile).read_text())
    assert len(policies) == 1, f"{caddyfile} sets the admin CSP once"
    return str(policies[0])


def script_sources(policy: str) -> list[str]:
    for directive in policy.split(";"):
        name, *sources = directive.split()
        if name == "script-src":
            return sources
    raise AssertionError("the admin CSP has no script-src")


@pytest.fixture
def signed_in() -> Client:
    user = User.objects.create_superuser("csp", PASSWORD)
    device = TOTPDevice.objects.create(user=user, name="default", confirmed=True)
    token = TOTP(device.bin_key, device.step, device.t0, device.digits, device.drift).token()
    client = Client()
    response = client.post(
        "/admin/login/",
        {"username": "csp", "password": PASSWORD, "otp_token": str(token).zfill(6)},
    )
    assert response.status_code == 302
    return client


def admin_pages() -> list[str]:
    user = User.objects.get(username="csp")
    task = PeriodicTask.objects.get(name="heartbeat")
    totp = TOTPDevice.objects.get(user=user)
    return [
        "/admin/",
        "/admin/password_change/",
        "/admin/accounts/user/",
        "/admin/accounts/user/add/",
        f"/admin/accounts/user/{user.pk}/change/",
        f"/admin/accounts/user/{user.pk}/history/",
        f"/admin/accounts/user/{user.pk}/delete/",
        "/admin/django_celery_beat/periodictask/",
        "/admin/django_celery_beat/periodictask/add/",
        f"/admin/django_celery_beat/periodictask/{task.pk}/change/",
        f"/admin/django_celery_beat/periodictask/{task.pk}/delete/",
        "/admin/django_celery_beat/crontabschedule/add/?_to_field=id&_popup=1",
        "/admin/django_celery_beat/intervalschedule/",
        "/admin/otp_totp/totpdevice/",
        f"/admin/otp_totp/totpdevice/{totp.pk}/change/",
        "/admin/axes/accessattempt/",
        "/admin/axes/accesslog/",
    ]


def test_both_edges_send_the_same_admin_csp() -> None:
    assert admin_csp("Caddyfile") == admin_csp("Caddyfile.dev")


def test_the_admin_csp_has_no_unsafe_script_sources() -> None:
    sources = script_sources(admin_csp("Caddyfile"))
    assert "'unsafe-inline'" not in sources
    assert "'unsafe-eval'" not in sources
    assert "'unsafe-hashes'" not in sources


def test_every_inline_script_is_allowed_and_every_hash_is_used(signed_in: Client) -> None:
    allowed = {s for s in script_sources(admin_csp("Caddyfile")) if s.startswith("'sha256-")}
    pages = ["/admin/login/", *admin_pages()]
    used: set[str] = set()
    for path in pages:
        client = Client() if path == "/admin/login/" else signed_in
        response = client.get(path)
        assert response.status_code == 200, path
        parser = InlineScripts()
        parser.feed(response.content.decode())
        assert parser.handlers == [], f"{path} has inline handlers, which a hash can't allow"
        hashes = {csp_hash(script) for script in parser.scripts}
        assert hashes <= allowed, f"{path}: add {sorted(hashes - allowed)} to the admin CSP"
        used |= hashes
    assert allowed <= used, f"remove {sorted(allowed - used)} from the admin CSP"
