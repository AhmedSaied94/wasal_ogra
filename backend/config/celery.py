"""The Celery app shared by the worker and the scheduler (FR-006, research R1)."""

import os

from celery import Celery

# A server started without the variable gets the strict settings, never dev's lenient ones.
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.prod")

app = Celery("wassal")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
