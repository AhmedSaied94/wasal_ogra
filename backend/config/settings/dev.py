"""Local development (quickstart "Setup"). Reads `backend/.env` first."""

from config.env import read_dotenv

read_dotenv()

from .base import *  # noqa: E402, F403
from .base import ALLOWED_HOSTS, STORAGES, env  # noqa: E402

DEBUG = env.boolean("DJANGO_DEBUG", default=True)

# The Android emulator reaches the host's loopback as 10.0.2.2 (mobile §21).
ALLOWED_HOSTS = [*ALLOWED_HOSTS, "10.0.2.2"]
# The dev edge (`--profile edge`) serves HTTPS on these, in front of a plain-HTTP Django.
CSRF_TRUSTED_ORIGINS = ["https://localhost:8443", "https://localhost:8444"]

if DEBUG:
    # Serve static files straight from the apps. The image build runs with DEBUG off, so
    # `collectstatic` there writes the manifest that production needs (T027).
    STORAGES = {
        **STORAGES,
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    }
    WHITENOISE_USE_FINDERS = True
    WHITENOISE_AUTOREFRESH = True
