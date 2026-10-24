"""Startup rules for every settings module (FR-003, FR-004, contracts/environment.md).

Each case loads a settings module in a fresh interpreter with a crafted environment, so the
developer's own `backend/.env` and shell are never involved.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parent.parent

PROBE = """
import json, django
django.setup()
from django.conf import settings
db = settings.DATABASES["default"]
print(json.dumps({
    "root_urlconf": settings.ROOT_URLCONF,
    "time_zone": settings.TIME_ZONE,
    "use_tz": settings.USE_TZ,
    "debug": settings.DEBUG,
    "connect_timeout": str(db.get("OPTIONS", {}).get("connect_timeout")),
    "traces_sample_rate": settings.SENTRY_TRACES_SAMPLE_RATE,
    "wassal_env": settings.WASSAL_ENV,
}))
"""

# base64url of 32 bytes. Low-entropy on purpose: none of these is a real secret.
PROD_SIGNING_KEY = "dGVzdC1vbmx5LXByb2Qtc2lnbmluZy1rZXktMDAwMDA"
OTHER_SIGNING_KEY = "c2Vjb25kLXRlc3Qtc2lnbmluZy1rZXktMDAwMDAwMDA"
SHORT_SIGNING_KEY = "eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eA"  # 31 bytes

# Valid production values. Low-entropy on purpose: none of this is a real secret.
PROD_ENV = {
    "WASSAL_ENV": "prod",
    "SECRET_KEY": "test-only-not-a-real-secret-key-" * 2,
    "DATABASE_URL": "postgres://wassal:test-db-password@db.invalid:5432/wassal",
    "CACHE_URL": "redis://cache.invalid:6379/0",
    "CELERY_BROKER_URL": "redis://cache.invalid:6379/1",
    "API_HOST": "api.example.test",
    "ADMIN_HOST": "admin.example.test",
    "SENTRY_DSN": "https://publickey@sentry.invalid/1",
    "HC_PING_HEARTBEAT_URL": "https://hc.invalid/ping/heartbeat",
    # B04 (specs/003-b04-content-pipeline/contracts/environment.md): production is the target.
    "CONTENT_ROLE": "target",
    "CONTENT_PACKS_DIR": "/var/lib/wassal/packs",
    "CONTENT_PACKS_PUBLIC_URL": "https://api.example.test/packs/",
    "CONTENT_PROMOTION_SOURCE_URL": "https://api.staging.example.test/packs/",
    # B02 (specs/009-b02-accounts-auth/contracts/environment.md).
    "AUTH_SIGNING_KEYS": f"k20261024:{PROD_SIGNING_KEY}",
    "GOOGLE_OAUTH_CLIENT_IDS": "web-client.apps.googleusercontent.com",
}
# Staging (and dev) is a content source: no promotion source, and it reads production's floor file.
STAGING_CONTENT = {
    "CONTENT_ROLE": "source",
    "CONTENT_PACKS_PUBLIC_URL": "https://api.staging.example.test/packs/",
    "CONTENT_VERSION_FLOOR_URL": "https://api.example.test/packs/",
}

REQUIRED = ["SECRET_KEY", "DATABASE_URL", "CACHE_URL", "CELERY_BROKER_URL"]
SECRETS = [
    "SECRET_KEY",
    "DATABASE_URL",
    "CACHE_URL",
    "CELERY_BROKER_URL",
    "SENTRY_DSN",
    "HC_PING_HEARTBEAT_URL",
    "AUTH_SIGNING_KEYS",
]


def load(module: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    clean = {
        "PATH": os.environ["PATH"],
        "WASSAL_READ_DOTENV": "0",
        "DJANGO_SETTINGS_MODULE": f"config.settings.{module}",
        **env,
    }
    return subprocess.run(  # noqa: S603 - fixed interpreter and arguments
        [sys.executable, "-c", PROBE],
        cwd=BACKEND_DIR,
        env=clean,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )


def probe(module: str, env: dict[str, str]) -> dict[str, object]:
    result = load(module, env)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout.strip().splitlines()[-1])  # type: ignore[no-any-return]


def env_for(module: str, **overrides: str) -> dict[str, str]:
    """Valid values for `module`, with `overrides` applied."""
    env = {**PROD_ENV, "WASSAL_ENV": module}
    if module != "prod":
        del env["CONTENT_PROMOTION_SOURCE_URL"]
        env.update(STAGING_CONTENT)
    env.update(overrides)
    return {name: value for name, value in env.items() if value is not None}


def assert_refused(result: subprocess.CompletedProcess[str], message: str) -> None:
    assert result.returncode != 0
    assert message in result.stderr


def assert_no_values_leaked(result: subprocess.CompletedProcess[str], env: dict[str, str]) -> None:
    output = result.stdout + result.stderr
    for name, value in env.items():
        if name in SECRETS and len(value) >= 8:
            assert value not in output, f"{name}'s value appears in the output"


@pytest.mark.parametrize("name", REQUIRED)
def test_missing_required_variable_names_it_without_values(name: str) -> None:
    env = {k: v for k, v in PROD_ENV.items() if k != name}
    result = load("prod", env)
    assert_refused(result, f"{name} is required")
    assert_no_values_leaked(result, env)


@pytest.mark.parametrize("module", ["prod", "dev"])
@pytest.mark.parametrize("name", REQUIRED)
def test_empty_required_variable_counts_as_missing(module: str, name: str) -> None:
    result = load(module, env_for(module, **{name: ""}))
    assert_refused(result, f"{name} is required")


@pytest.mark.parametrize("module", ["prod", "staging"])
@pytest.mark.parametrize("name", SECRETS)
def test_placeholder_secret_refused_outside_dev(module: str, name: str) -> None:
    value = PROD_ENV[name]
    placeholder = value.replace("test", "change-me", 1) if "test" in value else value + "change-me"
    result = load(module, env_for(module, **{name: placeholder}))
    assert_refused(result, f"{name} is a placeholder")


@pytest.mark.parametrize("module", ["prod", "staging"])
def test_short_secret_key_refused(module: str) -> None:
    result = load(module, env_for(module, SECRET_KEY="x" * 49))
    assert_refused(result, "SECRET_KEY is too short")


@pytest.mark.parametrize("module", ["prod", "staging"])
def test_debug_refused_outside_dev(module: str) -> None:
    result = load(module, env_for(module, DJANGO_DEBUG="true"))
    assert_refused(result, "DJANGO_DEBUG")


@pytest.mark.parametrize(("module", "wrong"), [("prod", "staging"), ("staging", "prod")])
def test_wassal_env_must_match_module(module: str, wrong: str) -> None:
    result = load(module, env_for(module, WASSAL_ENV=wrong))
    assert_refused(result, "WASSAL_ENV is invalid")


@pytest.mark.parametrize("module", ["prod", "staging"])
def test_valid_production_values_start(module: str) -> None:
    values = probe(module, env_for(module))
    assert values["debug"] is False
    assert values["wassal_env"] == module


def test_dev_starts_with_env_example() -> None:
    example: dict[str, str] = {}
    for line in (BACKEND_DIR / ".env.example").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, _, value = line.partition("=")
            example[key] = value
    values = probe("dev", example)
    assert values["wassal_env"] == "dev"


def test_test_settings_load_without_any_environment() -> None:
    values = probe("test", {})
    assert values["wassal_env"] == "test"


def test_connect_timeout_appended_when_absent() -> None:
    assert probe("prod", env_for("prod"))["connect_timeout"] == "3"


def test_connect_timeout_kept_when_present() -> None:
    url = PROD_ENV["DATABASE_URL"] + "?connect_timeout=7"
    assert probe("prod", env_for("prod", DATABASE_URL=url))["connect_timeout"] == "7"


def test_traces_sample_rate_default_and_bound() -> None:
    assert probe("prod", env_for("prod"))["traces_sample_rate"] == 0.05
    result = load("prod", env_for("prod", SENTRY_TRACES_SAMPLE_RATE="0.2"))
    assert_refused(result, "SENTRY_TRACES_SAMPLE_RATE is invalid")


def test_admin_only_selects_admin_urlconf() -> None:
    assert probe("prod", env_for("prod"))["root_urlconf"] == "config.urls"
    assert probe("prod", env_for("prod", ADMIN_ONLY="1"))["root_urlconf"] == "config.urls_admin"


def test_server_time_is_utc() -> None:
    values = probe("prod", env_for("prod"))
    assert values["time_zone"] == "UTC"
    assert values["use_tz"] is True


def test_unknown_cache_scheme_refused() -> None:
    result = load("prod", env_for("prod", CACHE_URL="memcache://cache.invalid:11211"))
    assert_refused(result, "CACHE_URL is invalid")


def test_malformed_throttle_rate_refused_at_startup() -> None:
    result = load("prod", env_for("prod", THROTTLE_ADDRESS_RATE="120"))
    assert_refused(result, "THROTTLE_ADDRESS_RATE is invalid")


@pytest.mark.parametrize("entry", ["config.wsgi", "config.celery"])
def test_server_entry_points_default_to_prod(entry: str) -> None:
    """A server started without DJANGO_SETTINGS_MODULE gets the strict settings, never dev."""
    clean = {"PATH": os.environ["PATH"], "WASSAL_READ_DOTENV": "0"}
    code = f"import os, {entry}; print(os.environ['DJANGO_SETTINGS_MODULE'])"
    result = subprocess.run(  # noqa: S603 - fixed interpreter and arguments
        [sys.executable, "-c", code],
        cwd=BACKEND_DIR,
        env=clean,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    if entry == "config.wsgi":
        assert_refused(result, "WASSAL_ENV is required")
    else:
        assert result.stdout.strip().splitlines()[-1] == "config.settings.prod"


# -- Content settings (B04, contracts/environment.md) ----------------------------------------------

CONTENT_PROBE = """
import json, django
django.setup()
from django.conf import settings
print(json.dumps({
    "role": settings.CONTENT_ROLE,
    "packs_dir": str(settings.CONTENT_PACKS_DIR),
    "public_url": settings.CONTENT_PACKS_PUBLIC_URL,
    "floor_url": settings.CONTENT_VERSION_FLOOR_URL,
    "promotion_url": settings.CONTENT_PROMOTION_SOURCE_URL,
    "solver_stage": settings.CONTENT_SOLVER_STAGE,
    "cache_seconds": settings.CONTENT_MANIFEST_CACHE_SECONDS,
    "timeout_seconds": settings.CONTENT_HTTP_TIMEOUT_SECONDS,
}))
"""


def content_probe(module: str, env: dict[str, str]) -> dict[str, object]:
    clean = {
        "PATH": os.environ["PATH"],
        "WASSAL_READ_DOTENV": "0",
        "DJANGO_SETTINGS_MODULE": f"config.settings.{module}",
        **env,
    }
    result = subprocess.run(  # noqa: S603 - fixed interpreter and arguments
        [sys.executable, "-c", CONTENT_PROBE],
        cwd=BACKEND_DIR,
        env=clean,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout.strip().splitlines()[-1])  # type: ignore[no-any-return]


@pytest.mark.parametrize(
    ("module", "overrides", "message"),
    [
        ("prod", {"CONTENT_ROLE": "source"}, "CONTENT_ROLE is invalid"),
        ("staging", {"CONTENT_ROLE": "target"}, "CONTENT_ROLE is invalid"),
        ("prod", {"CONTENT_ROLE": "mirror"}, "CONTENT_ROLE is invalid"),
        ("prod", {"CONTENT_ROLE": ""}, "CONTENT_ROLE is required"),
        ("staging", {"CONTENT_SOLVER_STAGE": "stand_in"}, "CONTENT_SOLVER_STAGE is invalid"),
        ("prod", {"CONTENT_SOLVER_STAGE": "stand_in"}, "CONTENT_SOLVER_STAGE is invalid"),
        ("prod", {"CONTENT_SOLVER_STAGE": "not a path"}, "CONTENT_SOLVER_STAGE is invalid"),
        (
            "staging",
            {"CONTENT_PACKS_PUBLIC_URL": "http://api.staging.example.test/packs/"},
            "CONTENT_PACKS_PUBLIC_URL is invalid",
        ),
        ("prod", {"CONTENT_PACKS_PUBLIC_URL": ""}, "CONTENT_PACKS_PUBLIC_URL is required"),
        (
            "prod",
            {"CONTENT_PACKS_PUBLIC_URL": "https://api.example.test/packs"},
            "CONTENT_PACKS_PUBLIC_URL is invalid",
        ),
        (
            "prod",
            {"CONTENT_PACKS_PUBLIC_URL": "/packs/"},
            "CONTENT_PACKS_PUBLIC_URL is invalid",
        ),
        ("prod", {"CONTENT_PACKS_DIR": ""}, "CONTENT_PACKS_DIR is required"),
        (
            "prod",
            {"CONTENT_PROMOTION_SOURCE_URL": ""},
            "CONTENT_PROMOTION_SOURCE_URL is required",
        ),
        (
            "prod",
            {"CONTENT_PROMOTION_SOURCE_URL": "http://api.staging.example.test/packs/"},
            "CONTENT_PROMOTION_SOURCE_URL is invalid",
        ),
        (
            "staging",
            {"CONTENT_PROMOTION_SOURCE_URL": "https://api.example.test/packs/"},
            "CONTENT_PROMOTION_SOURCE_URL must be empty",
        ),
        (
            "prod",
            {"CONTENT_VERSION_FLOOR_URL": "https://api.example.test/packs/"},
            "CONTENT_VERSION_FLOOR_URL must be empty",
        ),
        (
            "staging",
            {"CONTENT_VERSION_FLOOR_URL": "http://api.example.test/packs/"},
            "CONTENT_VERSION_FLOOR_URL is invalid",
        ),
        (
            "prod",
            {"CONTENT_MANIFEST_CACHE_SECONDS": "61"},
            "CONTENT_MANIFEST_CACHE_SECONDS is invalid",
        ),
        ("prod", {"CONTENT_HTTP_TIMEOUT_SECONDS": "0"}, "CONTENT_HTTP_TIMEOUT_SECONDS is invalid"),
        ("prod", {"CONTENT_HTTP_TIMEOUT_SECONDS": "31"}, "CONTENT_HTTP_TIMEOUT_SECONDS is invalid"),
    ],
)
def test_content_settings_refuse_to_start(
    module: str, overrides: dict[str, str], message: str
) -> None:
    result = load(module, env_for(module, **overrides))
    assert_refused(result, message)


def test_dev_refuses_a_promotion_source() -> None:
    env = {
        **PROD_ENV,
        "WASSAL_ENV": "dev",
        "CONTENT_ROLE": "source",
        "CONTENT_PACKS_PUBLIC_URL": "http://localhost:8000/packs/",
    }
    result = load("dev", env)
    assert_refused(result, "CONTENT_PROMOTION_SOURCE_URL must be empty")


@pytest.mark.parametrize("module", ["prod", "staging"])
def test_content_settings_on_the_hosts(module: str) -> None:
    values = content_probe(module, env_for(module))
    assert values["role"] == ("target" if module == "prod" else "source")
    assert values["solver_stage"] == "solver"
    assert values["cache_seconds"] == 30
    assert values["timeout_seconds"] == 10
    assert values["packs_dir"] == "/var/lib/wassal/packs"


@pytest.mark.parametrize("module", ["prod", "staging"])
@pytest.mark.parametrize("stage", ["solver", "none", "apps.content.tests.stages.Solver"])
def test_the_hosts_accept_the_real_stage_none_or_a_dotted_path(module: str, stage: str) -> None:
    values = content_probe(module, env_for(module, CONTENT_SOLVER_STAGE=stage))
    assert values["solver_stage"] == stage


def test_content_settings_for_tests_need_no_environment() -> None:
    values = content_probe("test", {})
    assert values["role"] == "source"
    assert values["solver_stage"] == "stand_in"
    assert values["cache_seconds"] == 0
    assert values["timeout_seconds"] == 2
    assert values["public_url"] == "https://packs.test.invalid/packs/"
    assert values["floor_url"] == ""
    assert values["promotion_url"] == ""


def test_dev_packs_dir_defaults_inside_the_backend() -> None:
    example: dict[str, str] = {}
    for line in (BACKEND_DIR / ".env.example").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, _, value = line.partition("=")
            example[key] = value
    values = content_probe("dev", example)
    assert values["packs_dir"] == str(BACKEND_DIR / "var" / "packs")
    assert values["public_url"] == "http://localhost:8000/packs/"
    assert values["solver_stage"] == "stand_in"


# -- Parallel tests (pytest-xdist) ---------------------------------------------------------------

VALKEY_PROBE = """
import json, django
django.setup()
from django.conf import settings
print(json.dumps({
    "cache": settings.CACHES["default"]["LOCATION"],
    "broker": settings.CELERY_BROKER_URL,
}))
"""


def valkey_probe(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    clean = {
        "PATH": os.environ["PATH"],
        "WASSAL_READ_DOTENV": "0",
        "DJANGO_SETTINGS_MODULE": "config.settings.test",
        **env,
    }
    return subprocess.run(  # noqa: S603 - fixed interpreter and arguments
        [sys.executable, "-c", VALKEY_PROBE],
        cwd=BACKEND_DIR,
        env=clean,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )


@pytest.mark.parametrize(
    ("worker", "cache_db", "broker_db"),
    [(None, 2, 3), ("gw0", 2, 3), ("gw1", 4, 5), ("gw6", 14, 15)],
)
def test_each_xdist_worker_gets_its_own_valkey_databases(
    worker: str | None, cache_db: int, broker_db: int
) -> None:
    """Every test clears the cache, so workers sharing a database would clear each other's."""
    result = valkey_probe({"PYTEST_XDIST_WORKER": worker} if worker else {})
    assert result.returncode == 0, result.stderr
    values = json.loads(result.stdout.strip().splitlines()[-1])
    assert values == {
        "cache": f"redis://127.0.0.1:6379/{cache_db}",
        "broker": f"redis://127.0.0.1:6379/{broker_db}",
    }


def test_more_xdist_workers_than_valkey_databases_are_refused() -> None:
    result = valkey_probe({"PYTEST_XDIST_WORKER": "gw7"})
    assert result.returncode != 0
    assert "at most 7 pytest-xdist workers" in result.stderr


# -- Auth settings (B02, specs/009-b02-accounts-auth/contracts/environment.md) --------------------

AUTH_PROBE = """
import json, django
django.setup()
from django.conf import settings
print(json.dumps({
    "kids": [key.kid for key in settings.AUTH_SIGNING_KEYS],
    "retry_seconds": settings.AUTH_REFRESH_RETRY_SECONDS,
    "max_sessions": settings.AUTH_MAX_SESSIONS_PER_PLAYER,
    "http_timeout": settings.AUTH_HTTP_TIMEOUT_SECONDS,
    "google_client_ids": list(settings.GOOGLE_OAUTH_CLIENT_IDS),
    "google_jwks_url": settings.GOOGLE_JWKS_URL,
    "google_cache": settings.GOOGLE_KEYS_CACHE_SECONDS,
    "simple_jwt_key_is_first": settings.SIMPLE_JWT["SIGNING_KEY"]
        == settings.AUTH_SIGNING_KEYS[0].key,
    "rates": {
        scope: settings.REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"][scope]
        for scope in ("player", "anonymous", "refresh", "link")
    },
}))
"""


def auth_probe(module: str, env: dict[str, str]) -> dict[str, object]:
    clean = {
        "PATH": os.environ["PATH"],
        "WASSAL_READ_DOTENV": "0",
        "DJANGO_SETTINGS_MODULE": f"config.settings.{module}",
        **env,
    }
    result = subprocess.run(  # noqa: S603 - fixed interpreter and arguments
        [sys.executable, "-c", AUTH_PROBE],
        cwd=BACKEND_DIR,
        env=clean,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout.strip().splitlines()[-1])  # type: ignore[no-any-return]


def without(env: dict[str, str], name: str) -> dict[str, str]:
    return {key: value for key, value in env.items() if key != name}


@pytest.mark.parametrize("module", ["prod", "staging"])
@pytest.mark.parametrize("name", ["AUTH_SIGNING_KEYS", "GOOGLE_OAUTH_CLIENT_IDS"])
def test_auth_variables_required_on_the_hosts(module: str, name: str) -> None:
    env = without(env_for(module), name)
    result = load(module, env)
    assert_refused(result, f"{name} is required")
    assert_no_values_leaked(result, env)


@pytest.mark.parametrize("module", ["prod", "staging"])
@pytest.mark.parametrize(
    ("value", "reason"),
    [
        (f"k1:{SHORT_SIGNING_KEY}", "short key"),
        (f"K1:{PROD_SIGNING_KEY}", "upper-case kid"),
        (f"{'k' * 33}:{PROD_SIGNING_KEY}", "kid too long"),
        (f":{PROD_SIGNING_KEY}", "empty kid"),
        (PROD_SIGNING_KEY, "no kid"),
        (f"k1:{PROD_SIGNING_KEY},k1:{OTHER_SIGNING_KEY}", "duplicate kid"),
        (",", "no entries"),
        (",".join(f"k{n}:{PROD_SIGNING_KEY}" for n in range(5)), "five entries"),
        (f"k1:{PROD_SIGNING_KEY[:-1]}!", "not base64url"),
        (f"k1:{PROD_SIGNING_KEY}+/", "standard base64"),
        (f"k1:{PROD_SIGNING_KEY}xx", "bad length"),
    ],
)
def test_malformed_signing_keys_refused(module: str, value: str, reason: str) -> None:
    env = env_for(module, AUTH_SIGNING_KEYS=value)
    result = load(module, env)
    assert_refused(result, "AUTH_SIGNING_KEYS is invalid")
    assert PROD_SIGNING_KEY not in result.stdout + result.stderr, reason


@pytest.mark.parametrize("module", ["prod", "staging"])
def test_signing_key_must_not_be_the_secret_key(module: str) -> None:
    env = env_for(module, AUTH_SIGNING_KEYS=f"k1:{PROD_ENV['SECRET_KEY']}")
    result = load(module, env)
    assert_refused(result, "AUTH_SIGNING_KEYS must not reuse SECRET_KEY")
    assert_no_values_leaked(result, env)


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("AUTH_REFRESH_RETRY_SECONDS", "301"),
        ("AUTH_REFRESH_RETRY_SECONDS", "-1"),
        ("AUTH_MAX_SESSIONS_PER_PLAYER", "0"),
        ("AUTH_MAX_SESSIONS_PER_PLAYER", "51"),
        ("AUTH_HTTP_TIMEOUT_SECONDS", "0"),
        ("AUTH_HTTP_TIMEOUT_SECONDS", "16"),
        ("GOOGLE_KEYS_CACHE_SECONDS", "21601"),
        # No cache would let made-up kids make every request fetch (B02 security review).
        ("GOOGLE_KEYS_CACHE_SECONDS", "0"),
        ("GOOGLE_KEYS_CACHE_SECONDS", "59"),
        ("GOOGLE_JWKS_URL", "http://www.googleapis.com/oauth2/v3/certs"),
        ("THROTTLE_PLAYER_RATE", "120"),
        ("THROTTLE_ANONYMOUS_RATE", "60/week"),
        ("THROTTLE_REFRESH_RATE", "x/min"),
        ("THROTTLE_LINK_RATE", "/min"),
    ],
)
def test_auth_values_out_of_range_refused(name: str, value: str) -> None:
    result = load("prod", env_for("prod", **{name: value}))
    assert_refused(result, f"{name} is invalid")


@pytest.mark.parametrize("module", ["prod", "staging"])
def test_auth_settings_on_the_hosts(module: str) -> None:
    rotated = f"k20261124:{OTHER_SIGNING_KEY},k20261024:{PROD_SIGNING_KEY}"
    values = auth_probe(module, env_for(module, AUTH_SIGNING_KEYS=rotated))
    assert values == {
        "kids": ["k20261124", "k20261024"],
        "retry_seconds": 60,
        "max_sessions": 10,
        "http_timeout": 5,
        "google_client_ids": ["web-client.apps.googleusercontent.com"],
        "google_jwks_url": "https://www.googleapis.com/oauth2/v3/certs",
        "google_cache": 3600,
        "simple_jwt_key_is_first": True,
        "rates": {
            "player": "120/min",
            "anonymous": "60/hour",
            "refresh": "30/min",
            "link": "10/min",
        },
    }


def test_dev_accepts_the_placeholder_key_and_no_google_client() -> None:
    example: dict[str, str] = {}
    for line in (BACKEND_DIR / ".env.example").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, _, value = line.partition("=")
            example[key] = value
    values = auth_probe("dev", example)
    assert values["kids"] == ["dev1"]
    assert values["google_client_ids"] == []


def test_auth_settings_for_tests_need_no_environment() -> None:
    values = auth_probe("test", {})
    assert values["kids"] == ["test1"]
    assert values["google_client_ids"] == ["test-client.apps.googleusercontent.com"]
    assert values["google_cache"] == 0
    assert values["http_timeout"] == 2
