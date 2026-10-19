"""gunicorn settings for the API and admin containers (research R1, R7)."""

import os

bind = "0.0.0.0:8000"
worker_class = "gthread"
workers = int(os.environ.get("GUNICORN_WORKERS", "2"))
threads = int(os.environ.get("GUNICORN_THREADS", "4"))
timeout = 30
graceful_timeout = 20
max_requests = 1000
max_requests_jitter = 100
# The app writes the one JSON access line per request (AccessLogMiddleware).
accesslog = None
