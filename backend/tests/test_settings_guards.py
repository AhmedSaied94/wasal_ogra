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
}

REQUIRED = ["SECRET_KEY", "DATABASE_URL", "CACHE_URL", "CELERY_BROKER_URL"]
SECRETS = [
    "SECRET_KEY",
    "DATABASE_URL",
    "CACHE_URL",
    "CELERY_BROKER_URL",
    "SENTRY_DSN",
    "HC_PING_HEARTBEAT_URL",
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
    env = {**PROD_ENV, "WASSAL_ENV": module}
    env.update(overrides)
    return env


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
