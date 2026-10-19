"""pytest settings: the real PostgreSQL and Valkey from the dev stack or CI (constitution XIII).

Loads with no environment at all, which mypy's django plugin needs. The `TEST_*` variables
point the tests at a superuser database URL, so pytest-django can create its test database.
"""

import os

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
os.environ.setdefault("SECRET_KEY", "test-only-not-a-real-secret-key-" * 2)
os.environ.setdefault("API_HOST", "testserver")
os.environ.setdefault("ADMIN_HOST", "testserver")

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
