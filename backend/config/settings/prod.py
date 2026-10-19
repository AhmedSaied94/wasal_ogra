"""Production. Debug off, proxy-aware, secure cookies (research R3)."""

from .base import *  # noqa: F403
from .base import ADMIN_HOST

DEBUG = False
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = True
SESSION_COOKIE_HTTPONLY = True
CSRF_COOKIE_SECURE = True
CSRF_TRUSTED_ORIGINS = [f"https://{ADMIN_HOST}"]

# The edge sets HSTS and redirects HTTP to HTTPS for every hostname (research R6).
SILENCED_SYSTEM_CHECKS = ["security.W004", "security.W008"]
