"""Typed environment reader with the fail-fast startup rules (FR-003, contracts/environment.md).

Every setting comes from the environment. A missing or invalid value stops the process with a
message that names the variable and never its value. Outside `dev` and `test`, placeholder
secrets, short keys, debug mode and a mismatched `WASSAL_ENV` are refused too.
"""

from __future__ import annotations

import os
import re
from collections.abc import Mapping
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import environ
from django.core.exceptions import ImproperlyConfigured

BACKEND_DIR = Path(__file__).resolve().parent.parent
ENVIRONMENTS = ("dev", "test", "staging", "prod")
LENIENT_ENVIRONMENTS = ("dev", "test")
PLACEHOLDER = "change-me"
MIN_SECRET_KEY_LENGTH = 50
DB_CONNECT_TIMEOUT_S = "3"
CACHE_TIMEOUT_S = 2
# What DRF's SimpleRateThrottle.parse_rate accepts: "<count>/<s|m|h|d>…", for example "120/min".
RATE_PATTERN = re.compile(r"^\d+/[smhd][a-z]*$")
TRUE_VALUES = frozenset({"1", "true", "yes", "on"})
FALSE_VALUES = frozenset({"0", "false", "no", "off", ""})

_MISSING: Any = object()


def settings_name() -> str:
    """The leaf settings module in use: `dev`, `test`, `staging` or `prod`."""
    module = os.environ.get("DJANGO_SETTINGS_MODULE", "config.settings.dev")
    return module.rsplit(".", 1)[-1]


def read_dotenv(path: Path = BACKEND_DIR / ".env", *, prefix: str = "") -> None:
    """Load `backend/.env` without overriding variables that are already set.

    `dev` reads every key. `test` passes `prefix="TEST_"`, so only the test URLs come from it.
    """
    if os.environ.get("WASSAL_READ_DOTENV", "1") == "0" or not path.is_file():
        return
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key.strip().startswith(prefix):
            os.environ.setdefault(key.strip(), value.strip())


class Env:
    """Reads and validates settings for one environment."""

    def __init__(self, name: str, source: Mapping[str, str] | None = None) -> None:
        if name not in ENVIRONMENTS:
            raise ImproperlyConfigured("DJANGO_SETTINGS_MODULE is invalid")
        self.name = name
        self.strict = name not in LENIENT_ENVIRONMENTS
        self._source = os.environ if source is None else source

    # -- accessors ---------------------------------------------------------------------------

    def string(
        self, name: str, default: str = _MISSING, *, required_outside_dev: bool = False
    ) -> str:
        """An empty value counts as unset, so `NAME=` in an env file can't satisfy a requirement."""
        value = self._source.get(name)
        if value:
            return value
        if default is _MISSING or (required_outside_dev and self.strict):
            raise ImproperlyConfigured(f"{name} is required")
        return default

    def secret(
        self, name: str, default: str = _MISSING, *, required_outside_dev: bool = False
    ) -> str:
        value = self.string(name, default, required_outside_dev=required_outside_dev)
        if self.strict and PLACEHOLDER in value:
            raise ImproperlyConfigured(f"{name} is a placeholder, which only dev accepts")
        return value

    def boolean(self, name: str, default: bool) -> bool:
        value = self._source.get(name)
        if value is None:
            return default
        lowered = value.strip().lower()
        if lowered in TRUE_VALUES:
            return True
        if lowered in FALSE_VALUES:
            return False
        raise ImproperlyConfigured(f"{name} is invalid")

    def integer(self, name: str, default: int, *, minimum: int = 0) -> int:
        value = self._source.get(name)
        if value is None:
            return default
        try:
            number = int(value)
        except ValueError:
            raise ImproperlyConfigured(f"{name} is invalid") from None
        if number < minimum:
            raise ImproperlyConfigured(f"{name} is invalid")
        return number

    def number(self, name: str, default: float, *, minimum: float, maximum: float) -> float:
        value = self._source.get(name)
        if value is None:
            return default
        try:
            number = float(value)
        except ValueError:
            raise ImproperlyConfigured(f"{name} is invalid") from None
        if not minimum <= number <= maximum:
            raise ImproperlyConfigured(f"{name} is invalid")
        return number

    def rate(self, name: str, default: str) -> str:
        value = self.string(name, default)
        if not RATE_PATTERN.match(value):
            raise ImproperlyConfigured(f"{name} is invalid")
        return value

    # -- composite values --------------------------------------------------------------------

    def secret_key(self) -> str:
        value = self.secret("SECRET_KEY")
        if self.strict and len(value) < MIN_SECRET_KEY_LENGTH:
            raise ImproperlyConfigured(
                f"SECRET_KEY is too short (at least {MIN_SECRET_KEY_LENGTH} characters)"
            )
        return value

    def database(self, name: str = "DATABASE_URL") -> dict[str, Any]:
        url = self.secret(name)
        if urlsplit(url).scheme not in ("postgres", "postgresql"):
            raise ImproperlyConfigured(f"{name} is invalid")
        try:
            config: dict[str, Any] = environ.Env.db_url_config(
                with_default_query(url, "connect_timeout", DB_CONNECT_TIMEOUT_S)
            )
        except Exception:  # noqa: BLE001 - never echo the URL, which holds a password
            raise ImproperlyConfigured(f"{name} is invalid") from None
        return config

    def cache(self, name: str = "CACHE_URL") -> dict[str, Any]:
        url = self.secret(name)
        scheme = urlsplit(url).scheme
        if scheme in ("redis", "rediss"):
            return {
                "BACKEND": "django.core.cache.backends.redis.RedisCache",
                "LOCATION": url,
                "OPTIONS": {
                    "socket_connect_timeout": CACHE_TIMEOUT_S,
                    "socket_timeout": CACHE_TIMEOUT_S,
                },
            }
        if scheme == "locmem":
            return {
                "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
                "LOCATION": "wassal",
            }
        raise ImproperlyConfigured(f"{name} is invalid")

    def broker(self, name: str = "CELERY_BROKER_URL") -> str:
        url = self.secret(name)
        if urlsplit(url).scheme not in ("redis", "rediss", "memory"):
            raise ImproperlyConfigured(f"{name} is invalid")
        return url

    def check_environment(self) -> None:
        """`WASSAL_ENV` must name the settings module in use, and debug is off outside dev."""
        expected = self.name
        if self.string("WASSAL_ENV", expected if not self.strict else _MISSING) != expected:
            raise ImproperlyConfigured(f"WASSAL_ENV is invalid for config.settings.{self.name}")
        if self.strict and self.boolean("DJANGO_DEBUG", default=False):
            raise ImproperlyConfigured("DJANGO_DEBUG must be false outside dev")


def with_default_query(url: str, key: str, value: str) -> str:
    """Return `url` with `key=value` in its query string unless the key is already there."""
    parts = urlsplit(url)
    query = parse_qsl(parts.query, keep_blank_values=True)
    if any(existing == key for existing, _ in query):
        return url
    return urlunsplit(parts._replace(query=urlencode([*query, (key, value)])))
