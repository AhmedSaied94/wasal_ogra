"""WSGI entry point for gunicorn (`config.wsgi`)."""

import os

from django.core.wsgi import get_wsgi_application

# A server started without the variable gets the strict settings, never dev's lenient ones.
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.prod")

application = get_wsgi_application()
