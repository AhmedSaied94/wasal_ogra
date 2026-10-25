"""Typed environment reader with the fail-fast startup rules (FR-003, contracts/environment.md).

Every setting comes from the environment. A missing or invalid value stops the process with a
message that names the variable and never its value. Outside `dev` and `test`, placeholder
secrets, short keys, debug mode and a mismatched `WASSAL_ENV` are refused too.
"""

from __future__ import annotations

import base64
import binascii
import os
import re
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

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
# CONTENT_SOLVER_STAGE (B04, B05): `solver` (the real stage, the default on staging and prod),
# `none`, `stand_in` (dev and test only), or the dotted path of a stage class.
SOLVER_STAGE_PATTERN = re.compile(r"^(solver|none|stand_in|[A-Za-z_]\w*(\.[A-Za-z_]\w*)+)$")
# AUTH_SIGNING_KEYS (B02 research R13): `kid:key` entries, the key base64url (padding optional).
SIGNING_KID_PATTERN = re.compile(r"^[a-z0-9-]{1,32}$")
SIGNING_KEY_PATTERN = re.compile(r"^[A-Za-z0-9_-]+={0,2}$")
MIN_SIGNING_KEY_BYTES = 32
MAX_SIGNING_KEYS = 4
GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
# CLIENT_MIN_VERSION and CLIENT_LATEST_VERSION (B03): a plain MAJOR.MINOR.PATCH.
VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
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

    def integer(
        self, name: str, default: int, *, minimum: int = 0, maximum: int | None = None
    ) -> int:
        value = self._source.get(name)
        if value is None:
            return default
        try:
            number = int(value)
        except ValueError:
            raise ImproperlyConfigured(f"{name} is invalid") from None
        if number < minimum or (maximum is not None and number > maximum):
            raise ImproperlyConfigured(f"{name} is invalid")
        return number

    def choice(self, name: str, choices: tuple[str, ...], default: str = _MISSING) -> str:
        value = self.string(name, default)
        if value not in choices:
            raise ImproperlyConfigured(f"{name} is invalid")
        return value

    def url(self, name: str, default: str = _MISSING, *, directory: bool = False) -> str:
        """An absolute URL, `https://` outside dev and test. Empty stays empty when allowed."""
        value = self.string(name, default)
        if not value:
            return value
        parts = urlsplit(value)
        schemes = ("https",) if self.strict else ("http", "https")
        if parts.scheme not in schemes or not parts.netloc:
            raise ImproperlyConfigured(f"{name} is invalid")
        if directory and not parts.path.endswith("/"):
            raise ImproperlyConfigured(f"{name} is invalid: it must end with /")
        return value

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

    def content(self, default_packs_dir: Path) -> ContentConfig:
        """The content pipeline's settings and their cross-checks (B04 contracts/environment.md)."""
        role = self.choice("CONTENT_ROLE", ("source", "target"))
        if (role == "target") != (self.name == "prod"):
            raise ImproperlyConfigured("CONTENT_ROLE is invalid: target on prod, source elsewhere")
        promotion = self.url("CONTENT_PROMOTION_SOURCE_URL", "", directory=True)
        if role == "target" and not promotion:
            raise ImproperlyConfigured("CONTENT_PROMOTION_SOURCE_URL is required")
        if role == "source" and promotion and self.name != "test":
            raise ImproperlyConfigured("CONTENT_PROMOTION_SOURCE_URL must be empty on a source")
        floor = self.url("CONTENT_VERSION_FLOOR_URL", "", directory=True)
        if role == "target" and floor:
            raise ImproperlyConfigured("CONTENT_VERSION_FLOOR_URL must be empty on the target")
        solver = self.string("CONTENT_SOLVER_STAGE", "solver" if self.strict else "stand_in")
        if not SOLVER_STAGE_PATTERN.match(solver) or (self.strict and solver == "stand_in"):
            raise ImproperlyConfigured("CONTENT_SOLVER_STAGE is invalid")
        packs_dir = self.string(
            "CONTENT_PACKS_DIR", str(default_packs_dir), required_outside_dev=True
        )
        return ContentConfig(
            role=role,
            packs_dir=Path(packs_dir),
            public_url=self.url("CONTENT_PACKS_PUBLIC_URL", directory=True),
            floor_url=floor,
            promotion_url=promotion,
            solver_stage=solver,
            manifest_cache_seconds=self.integer(
                "CONTENT_MANIFEST_CACHE_SECONDS", 30, minimum=0, maximum=60
            ),
            http_timeout_seconds=self.integer(
                "CONTENT_HTTP_TIMEOUT_SECONDS", 10, minimum=1, maximum=30
            ),
            # B03 (specs/010-b03-ledger-sync/contracts/environment.md): B04 kept 5.
            index_keep=self.integer("CONTENT_INDEX_KEEP", 10, minimum=5, maximum=50),
        )

    def signing_keys(
        self, name: str = "AUTH_SIGNING_KEYS", *, forbidden: str = ""
    ) -> tuple[SigningKey, ...]:
        """The token key ring: the first entry signs, every entry verifies (B02 research R13).

        `forbidden` is `SECRET_KEY`, which no signing key may reuse outside dev and test.
        """
        value = self.secret(name)
        entries = [entry.strip() for entry in value.split(",")]
        if not 1 <= len(entries) <= MAX_SIGNING_KEYS:
            raise ImproperlyConfigured(f"{name} is invalid: give 1 to {MAX_SIGNING_KEYS} entries")
        keys: list[SigningKey] = []
        for entry in entries:
            kid, _, encoded = entry.partition(":")
            if not SIGNING_KID_PATTERN.match(kid) or any(key.kid == kid for key in keys):
                raise ImproperlyConfigured(f"{name} is invalid: each kid must be unique, [a-z0-9-]")
            if self.strict and forbidden and encoded == forbidden:
                raise ImproperlyConfigured(f"{name} must not reuse SECRET_KEY")
            keys.append(SigningKey(kid, _base64url(name, encoded)))
        return tuple(keys)

    def auth(self) -> AuthConfig:
        """B02's settings (specs/009-b02-accounts-auth/contracts/environment.md)."""
        client_ids = self.string("GOOGLE_OAUTH_CLIENT_IDS", "", required_outside_dev=True)
        return AuthConfig(
            retry_seconds=self.integer("AUTH_REFRESH_RETRY_SECONDS", 60, minimum=0, maximum=300),
            max_sessions=self.integer("AUTH_MAX_SESSIONS_PER_PLAYER", 10, minimum=1, maximum=50),
            http_timeout_seconds=self.integer(
                "AUTH_HTTP_TIMEOUT_SECONDS", 5, minimum=1, maximum=15
            ),
            google_client_ids=tuple(part.strip() for part in client_ids.split(",") if part.strip()),
            google_jwks_url=self.url("GOOGLE_JWKS_URL", GOOGLE_JWKS_URL),
            # 0 (no cache, as tests use) would let made-up kids make every request fetch.
            google_keys_cache_seconds=self.integer(
                "GOOGLE_KEYS_CACHE_SECONDS", 3600, minimum=60 if self.strict else 0, maximum=21600
            ),
        )

    def economy(self) -> EconomyConfig:
        """B03's settings and their cross-checks (specs/010-b03-ledger-sync/contracts/
        environment.md). None is a secret, so every environment checks them the same way."""
        fuel_max = self.integer("ECONOMY_FUEL_MAX", 5, minimum=1, maximum=20)
        fuel_max_subscriber = self.integer("ECONOMY_FUEL_MAX_SUBSCRIBER", 7, minimum=1, maximum=20)
        if fuel_max_subscriber < fuel_max:
            raise ImproperlyConfigured(
                "ECONOMY_FUEL_MAX_SUBSCRIBER is invalid: it must be at least ECONOMY_FUEL_MAX"
            )
        name_min = self.integer("ECONOMY_NAME_MIN_LENGTH", 2, minimum=1, maximum=32)
        name_max = self.integer("ECONOMY_NAME_MAX_LENGTH", 20, minimum=1, maximum=32)
        if name_max < name_min:
            raise ImproperlyConfigured(
                "ECONOMY_NAME_MAX_LENGTH is invalid: it must be at least ECONOMY_NAME_MIN_LENGTH"
            )
        min_duration = self.integer("SYNC_MIN_DURATION_PERCENT", 85, minimum=1, maximum=100)
        fast_run = self.integer("SYNC_FAST_RUN_PERCENT", 95, minimum=1, maximum=100)
        if fast_run < min_duration:
            raise ImproperlyConfigured(
                "SYNC_FAST_RUN_PERCENT is invalid: it must be at least SYNC_MIN_DURATION_PERCENT"
            )
        client_min = self._version("CLIENT_MIN_VERSION")
        client_latest = self._version("CLIENT_LATEST_VERSION")
        if _version_tuple(client_min) > _version_tuple(client_latest):
            raise ImproperlyConfigured(
                "CLIENT_MIN_VERSION is invalid: it must not be above CLIENT_LATEST_VERSION"
            )
        return EconomyConfig(
            fuel_max=fuel_max,
            fuel_max_subscriber=fuel_max_subscriber,
            fuel_regen_minutes=self.integer(
                "ECONOMY_FUEL_REGEN_MINUTES", 20, minimum=1, maximum=240
            ),
            fuel_refill_daily_cap=self.integer(
                "ECONOMY_FUEL_REFILL_DAILY_CAP", 3, minimum=0, maximum=50
            ),
            fuel_overdraft_per_day=self.integer(
                "ECONOMY_FUEL_OVERDRAFT_PER_DAY", 2, minimum=0, maximum=20
            ),
            traffic_jam_ads_per_trip=self.integer(
                "ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP", 1, minimum=0, maximum=10
            ),
            name_min_length=name_min,
            name_max_length=name_max,
            game_timezone=self._timezone("SYNC_GAME_TIMEZONE", "Africa/Cairo"),
            op_retention_days=self.integer("SYNC_OP_RETENTION_DAYS", 180, minimum=30, maximum=730),
            content_max_age_days=self.integer(
                "SYNC_CONTENT_MAX_AGE_DAYS", 45, minimum=1, maximum=365
            ),
            min_duration_percent=min_duration,
            fast_run_percent=fast_run,
            trips_per_day_flag=self.integer(
                "SYNC_TRIPS_PER_DAY_FLAG", 400, minimum=10, maximum=5000
            ),
            clock_clamp_flag_minutes=self.integer(
                "SYNC_CLOCK_CLAMP_FLAG_MINUTES", 10, minimum=1, maximum=1440
            ),
            session_gap_minutes=self.integer(
                "SYNC_SESSION_GAP_MINUTES", 30, minimum=1, maximum=1440
            ),
            comeback_away_days=self.integer("SYNC_COMEBACK_AWAY_DAYS", 7, minimum=1, maximum=365),
            comeback_cooldown_days=self.integer(
                "SYNC_COMEBACK_COOLDOWN_DAYS", 30, minimum=0, maximum=365
            ),
            client_min_version=client_min,
            client_latest_version=client_latest,
        )

    def _version(self, name: str) -> str:
        value = self.string(name, "1.0.0")
        if not VERSION_PATTERN.match(value):
            raise ImproperlyConfigured(f"{name} is invalid: use MAJOR.MINOR.PATCH")
        return value

    def _timezone(self, name: str, default: str) -> str:
        value = self.string(name, default)
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError):
            raise ImproperlyConfigured(f"{name} is invalid: use an IANA zone name") from None
        return value

    def check_environment(self) -> None:
        """`WASSAL_ENV` must name the settings module in use, and debug is off outside dev."""
        expected = self.name
        if self.string("WASSAL_ENV", expected if not self.strict else _MISSING) != expected:
            raise ImproperlyConfigured(f"WASSAL_ENV is invalid for config.settings.{self.name}")
        if self.strict and self.boolean("DJANGO_DEBUG", default=False):
            raise ImproperlyConfigured("DJANGO_DEBUG must be false outside dev")


@dataclass(frozen=True)
class ContentConfig:
    """The content pipeline's settings (B04 contracts/environment.md "Application variables")."""

    role: str
    packs_dir: Path
    public_url: str
    floor_url: str
    promotion_url: str
    solver_stage: str
    manifest_cache_seconds: int
    http_timeout_seconds: int
    index_keep: int


@dataclass(frozen=True)
class EconomyConfig:
    """B03's settings (specs/010-b03-ledger-sync/contracts/environment.md). Integers only."""

    fuel_max: int
    fuel_max_subscriber: int
    fuel_regen_minutes: int
    fuel_refill_daily_cap: int
    fuel_overdraft_per_day: int
    traffic_jam_ads_per_trip: int
    name_min_length: int
    name_max_length: int
    game_timezone: str
    op_retention_days: int
    content_max_age_days: int
    min_duration_percent: int
    fast_run_percent: int
    trips_per_day_flag: int
    clock_clamp_flag_minutes: int
    session_gap_minutes: int
    comeback_away_days: int
    comeback_cooldown_days: int
    client_min_version: str
    client_latest_version: str


@dataclass(frozen=True)
class SigningKey:
    """One entry of `AUTH_SIGNING_KEYS`. The key never appears in a repr or a log line."""

    kid: str
    key: bytes = field(repr=False)


@dataclass(frozen=True)
class AuthConfig:
    """B02's settings (specs/009-b02-accounts-auth/contracts/environment.md)."""

    retry_seconds: int
    max_sessions: int
    http_timeout_seconds: int
    google_client_ids: tuple[str, ...]
    google_jwks_url: str
    google_keys_cache_seconds: int


def _base64url(name: str, encoded: str) -> bytes:
    """Decode a signing key. `urlsafe_b64decode` alone would skip characters it doesn't know."""
    data = encoded.rstrip("=")
    padded = encoded != data
    if (
        not SIGNING_KEY_PATTERN.match(encoded)
        or len(data) % 4 == 1
        or (padded and len(encoded) % 4)
    ):
        raise ImproperlyConfigured(f"{name} is invalid: each key must be base64url")
    try:
        key = base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))
    except binascii.Error:
        raise ImproperlyConfigured(f"{name} is invalid: each key must be base64url") from None
    if len(key) < MIN_SIGNING_KEY_BYTES:
        raise ImproperlyConfigured(
            f"{name} is invalid: each key must decode to at least {MIN_SIGNING_KEY_BYTES} bytes"
        )
    return key


def _version_tuple(value: str) -> tuple[int, int, int]:
    major, minor, patch = value.split(".")
    return int(major), int(minor), int(patch)


def with_default_query(url: str, key: str, value: str) -> str:
    """Return `url` with `key=value` in its query string unless the key is already there."""
    parts = urlsplit(url)
    query = parse_qsl(parts.query, keep_blank_values=True)
    if any(existing == key for existing, _ in query):
        return url
    return urlunsplit(parts._replace(query=urlencode([*query, (key, value)])))
