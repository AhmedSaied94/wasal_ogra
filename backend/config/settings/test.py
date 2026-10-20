"""pytest settings: the real PostgreSQL and Valkey from the dev stack or CI (constitution XIII).

Loads with no environment at all, which mypy's django plugin needs. The `TEST_*` variables
point the tests at a superuser database URL, so pytest-django can create its test database.
"""

import os
import tempfile
from pathlib import Path

from config.env import read_dotenv

# Only the TEST_* URLs, so a developer who moved a port in backend/.env needs nothing else.
read_dotenv(prefix="TEST_")

os.environ["DJANGO_SETTINGS_MODULE"] = "config.settings.test"
os.environ["WASSAL_ENV"] = "test"
os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL", "postgres://postgres:change-me-postgres@127.0.0.1:5432/postgres"
)
os.environ["CACHE_URL"] = os.environ.get("TEST_CACHE_URL", "redis://127.0.0.1:6379/2")
os.environ["CELERY_BROKER_URL"] = os.environ.get("TEST_BROKER_URL", "redis://127.0.0.1:6379/3")


def _worker_url(url: str, worker: int) -> str:
    """`url`'s Valkey database moved up two per pytest-xdist worker: every test clears the cache
    and the broker test flushes its database, so workers can't share them. Valkey has 16."""
    base, _, database = url.rpartition("/")
    return f"{base}/{int(database) + 2 * worker}"


# pytest-xdist names its workers gw0, gw1, ... A serial run has no worker and keeps the URLs.
_xdist_worker = os.environ.get("PYTEST_XDIST_WORKER", "")
if _xdist_worker:
    _worker = int(_xdist_worker.removeprefix("gw"))
    if _worker > 6:
        raise RuntimeError("tests run on at most 7 pytest-xdist workers: Valkey has 16 databases")
    for _name in ("CACHE_URL", "CELERY_BROKER_URL"):
        os.environ[_name] = _worker_url(os.environ[_name], _worker)
os.environ.setdefault("SECRET_KEY", "test-only-not-a-real-secret-key-" * 2)
os.environ.setdefault("API_HOST", "testserver")
os.environ.setdefault("ADMIN_HOST", "testserver")
# B04: tests are a content source with fast timeouts and no manifest cache. The packs_dir fixture
# points each test that writes packs at its own directory.
os.environ.setdefault("CONTENT_ROLE", "source")
os.environ.setdefault("CONTENT_PACKS_DIR", str(Path(tempfile.gettempdir()) / "wassal-test-packs"))
os.environ.setdefault("CONTENT_PACKS_PUBLIC_URL", "https://packs.test.invalid/packs/")
os.environ.setdefault("CONTENT_SOLVER_STAGE", "stand_in")
os.environ.setdefault("CONTENT_MANIFEST_CACHE_SECONDS", "0")
os.environ.setdefault("CONTENT_HTTP_TIMEOUT_SECONDS", "2")

from .base import *  # noqa: E402, F403
from .base import STORAGES  # noqa: E402

DEBUG = False
STORAGES = {
    **STORAGES,
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}
# Serve static files from the apps, as dev does, so tests need no `collectstatic`.
WHITENOISE_USE_FINDERS = True
WHITENOISE_AUTOREFRESH = True
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
