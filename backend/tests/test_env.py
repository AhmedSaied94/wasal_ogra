"""The typed environment reader, in-process (contracts/environment.md). The subprocess cases in
test_settings_guards.py prove the settings modules use it; these pin its edge cases."""

import os
from pathlib import Path

import pytest
from django.core.exceptions import ImproperlyConfigured

from config.env import Env, read_dotenv, with_default_query

DB_URL = "postgres://wassal:test-db-password@db.invalid:5432/wassal"


def strict(**values: str) -> Env:
    return Env("prod", values)


def lenient(**values: str) -> Env:
    return Env("dev", values)


def test_unknown_environment_refused() -> None:
    with pytest.raises(ImproperlyConfigured, match="DJANGO_SETTINGS_MODULE is invalid"):
        Env("production", {})


@pytest.mark.parametrize(("raw", "expected"), [("1", True), ("Yes", True), ("off", False)])
def test_boolean_values(raw: str, expected: bool) -> None:
    assert lenient(FLAG=raw).boolean("FLAG", default=not expected) is expected


def test_boolean_default_and_invalid() -> None:
    assert lenient().boolean("FLAG", default=True) is True
    with pytest.raises(ImproperlyConfigured, match="FLAG is invalid"):
        lenient(FLAG="maybe").boolean("FLAG", default=False)


def test_integer_parsing_and_minimum() -> None:
    assert lenient().integer("N", 4) == 4
    assert lenient(N="7").integer("N", 4) == 7
    for raw in ("seven", "-1"):
        with pytest.raises(ImproperlyConfigured, match="N is invalid"):
            lenient(N=raw).integer("N", 4)


def test_number_parsing_and_bounds() -> None:
    assert lenient().number("R", 0.05, minimum=0, maximum=0.1) == 0.05
    assert lenient(R="0.1").number("R", 0.05, minimum=0, maximum=0.1) == 0.1
    for raw in ("high", "0.2"):
        with pytest.raises(ImproperlyConfigured, match="R is invalid"):
            lenient(R=raw).number("R", 0.05, minimum=0, maximum=0.1)


def test_required_outside_dev() -> None:
    assert lenient().string("SENTRY_DSN", "", required_outside_dev=True) == ""
    with pytest.raises(ImproperlyConfigured, match="SENTRY_DSN is required"):
        strict(SENTRY_DSN="").string("SENTRY_DSN", "", required_outside_dev=True)


def test_placeholder_accepted_only_when_lenient() -> None:
    assert lenient(SENTRY_DSN="change-me-x").secret("SENTRY_DSN") == "change-me-x"
    with pytest.raises(ImproperlyConfigured, match="SENTRY_DSN is a placeholder"):
        strict(SENTRY_DSN="change-me-x").secret("SENTRY_DSN")


def test_database_url_rules() -> None:
    config = strict(DATABASE_URL=DB_URL).database()
    assert config["HOST"] == "db.invalid"
    assert str(config["OPTIONS"]["connect_timeout"]) == "3"
    for url in ("mysql://u:p@h/db", "postgres://u:p@h:notaport/db"):
        with pytest.raises(ImproperlyConfigured, match="DATABASE_URL is invalid") as excinfo:
            strict(DATABASE_URL=url).database()
        assert "u:p" not in str(excinfo.value)


def test_cache_backends() -> None:
    redis = strict(CACHE_URL="rediss://cache.invalid:6380/0").cache()
    assert redis["BACKEND"] == "django.core.cache.backends.redis.RedisCache"
    assert redis["OPTIONS"] == {"socket_connect_timeout": 2, "socket_timeout": 2}
    locmem = strict(CACHE_URL="locmem://").cache()
    assert locmem["BACKEND"] == "django.core.cache.backends.locmem.LocMemCache"


@pytest.mark.parametrize("url", ["redis://b.invalid:6379/1", "memory://"])
def test_broker_schemes_accepted(url: str) -> None:
    assert strict(CELERY_BROKER_URL=url).broker() == url


def test_broker_scheme_refused() -> None:
    with pytest.raises(ImproperlyConfigured, match="CELERY_BROKER_URL is invalid"):
        strict(CELERY_BROKER_URL="amqp://b.invalid//").broker()


def test_wassal_env_defaults_only_when_lenient() -> None:
    lenient().check_environment()
    with pytest.raises(ImproperlyConfigured, match="WASSAL_ENV is required"):
        strict().check_environment()


def test_with_default_query_keeps_existing_values() -> None:
    assert with_default_query("postgres://h/db?sslmode=require", "connect_timeout", "3") == (
        "postgres://h/db?sslmode=require&connect_timeout=3"
    )
    assert with_default_query("postgres://h/db?connect_timeout=9", "connect_timeout", "3") == (
        "postgres://h/db?connect_timeout=9"
    )


def test_read_dotenv(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text(
        "# comment\n\nNOT_A_PAIR\nWASSAL_T_A=1\nTEST_WASSAL_B=2\nWASSAL_T_SET=file\n"
    )
    for name in ("WASSAL_T_A", "TEST_WASSAL_B", "WASSAL_READ_DOTENV"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("WASSAL_T_SET", "shell")

    read_dotenv(env_file, prefix="TEST_")
    assert "WASSAL_T_A" not in os.environ
    assert os.environ["TEST_WASSAL_B"] == "2"

    read_dotenv(env_file)
    assert os.environ["WASSAL_T_A"] == "1"
    assert os.environ["WASSAL_T_SET"] == "shell"  # never overrides


def test_read_dotenv_can_be_turned_off(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text("WASSAL_T_OFF=1\n")
    monkeypatch.delenv("WASSAL_T_OFF", raising=False)
    monkeypatch.setenv("WASSAL_READ_DOTENV", "0")
    read_dotenv(env_file)
    assert "WASSAL_T_OFF" not in os.environ


@pytest.mark.parametrize("raw", ["120/min", "5/s", "1000/hour", "10/d"])
def test_rate_accepted(raw: str) -> None:
    assert lenient(RATE=raw).rate("RATE", "120/min") == raw


@pytest.mark.parametrize("raw", ["120", "x/min", "120/week", "/min"])
def test_rate_refused(raw: str) -> None:
    with pytest.raises(ImproperlyConfigured, match="RATE is invalid"):
        lenient(RATE=raw).rate("RATE", "120/min")


# -- Signing keys and auth settings (B02 research R13, contracts/environment.md) -----------------

KEY_A = "dGVzdC1vbmx5LXNpZ25pbmcta2V5LTAwMDAwMDAwMDA"  # base64url of 32 bytes
KEY_B = "c2Vjb25kLXRlc3Qtc2lnbmluZy1rZXktMDAwMDAwMDA"


def test_signing_keys_keep_their_order_and_decode() -> None:
    keys = strict(AUTH_SIGNING_KEYS=f"new-1:{KEY_B}, old-1:{KEY_A}=").signing_keys()
    assert [key.kid for key in keys] == ["new-1", "old-1"]
    assert keys[1].key == b"test-only-signing-key-0000000000"


def test_signing_key_repr_hides_the_key() -> None:
    (key,) = strict(AUTH_SIGNING_KEYS=f"k1:{KEY_A}").signing_keys()
    assert KEY_A not in repr(key)
    assert "test-only" not in repr(key)


def test_placeholder_signing_key_only_when_lenient() -> None:
    value = "dev1:change-me-dev-signing-key-0000000000000000000000000"
    assert lenient(AUTH_SIGNING_KEYS=value).signing_keys()[0].kid == "dev1"
    with pytest.raises(ImproperlyConfigured, match="AUTH_SIGNING_KEYS is a placeholder"):
        strict(AUTH_SIGNING_KEYS=value).signing_keys()


def test_signing_key_may_equal_the_secret_key_only_when_lenient() -> None:
    assert lenient(AUTH_SIGNING_KEYS=f"k1:{KEY_A}").signing_keys(forbidden=KEY_A)
    with pytest.raises(ImproperlyConfigured, match="must not reuse SECRET_KEY"):
        strict(AUTH_SIGNING_KEYS=f"k1:{KEY_A}").signing_keys(forbidden=KEY_A)


@pytest.mark.parametrize(
    "value",
    [
        "k1:eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eA",  # 31 bytes
        f"k_1:{KEY_A}",
        f"k1:{KEY_A},k1:{KEY_B}",
        f"k1:{KEY_A},",
        ",".join(f"k{n}:{KEY_A}" for n in range(5)),
        f"k1:{KEY_A}==",
        f"k1:{KEY_A}xx",
    ],
)
def test_malformed_signing_keys_refused_without_the_value(value: str) -> None:
    with pytest.raises(ImproperlyConfigured, match="AUTH_SIGNING_KEYS is invalid") as excinfo:
        lenient(AUTH_SIGNING_KEYS=value).signing_keys()
    assert KEY_A not in str(excinfo.value)


def test_signing_keys_required_everywhere() -> None:
    with pytest.raises(ImproperlyConfigured, match="AUTH_SIGNING_KEYS is required"):
        lenient().signing_keys()


def test_auth_config_defaults_and_google_ids() -> None:
    config = lenient(GOOGLE_OAUTH_CLIENT_IDS=" a.apps , b.apps ").auth()
    assert config.google_client_ids == ("a.apps", "b.apps")
    assert config.retry_seconds == 60
    assert config.max_sessions == 10
    assert config.http_timeout_seconds == 5
    assert config.google_jwks_url == "https://www.googleapis.com/oauth2/v3/certs"
    assert config.google_keys_cache_seconds == 3600
    assert lenient().auth().google_client_ids == ()
    with pytest.raises(ImproperlyConfigured, match="GOOGLE_OAUTH_CLIENT_IDS is required"):
        strict().auth()
