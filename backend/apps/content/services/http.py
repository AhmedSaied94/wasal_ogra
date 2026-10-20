"""Capped GETs to fixed URLs from the settings: the floor file and promotion fetches.

Each call streams with a byte cap, uses `CONTENT_HTTP_TIMEOUT_SECONDS`, follows no redirects, and
retries connection errors, timeouts and `5xx` three times with a short backoff (research R10).
URLs only ever come from settings plus a file name, never from user input.
"""

from __future__ import annotations

import time

import requests
from django.conf import settings

RETRIES = 3
BACKOFF_SECONDS = 0.5
CHUNK = 64 * 1024


class FetchError(Exception):
    """`reason` is `unreachable`, `status` or `too_large`. Messages carry no URL."""

    def __init__(self, reason: str, status: int | None = None) -> None:
        self.reason = reason
        self.status = status
        super().__init__(reason if status is None else f"{reason} {status}")


def fetch(url: str, *, max_bytes: int) -> bytes:
    last = FetchError("unreachable")
    for attempt in range(RETRIES + 1):
        if attempt:
            time.sleep(BACKOFF_SECONDS * attempt)
        try:
            return _get(url, max_bytes)
        except FetchError as error:
            if error.reason == "status" and (error.status or 0) < 500:
                raise
            if error.reason == "too_large":
                raise
            last = error
        except (requests.ConnectionError, requests.Timeout):
            last = FetchError("unreachable")
        except requests.RequestException:
            raise FetchError("unreachable") from None
    raise last


def _get(url: str, max_bytes: int) -> bytes:
    timeout = settings.CONTENT_HTTP_TIMEOUT_SECONDS
    with requests.get(url, timeout=timeout, stream=True, allow_redirects=False) as response:
        if response.status_code != 200:
            raise FetchError("status", response.status_code)
        declared = response.headers.get("Content-Length")
        if declared and declared.isdigit() and int(declared) > max_bytes:
            raise FetchError("too_large")
        body = bytearray()
        for chunk in response.iter_content(CHUNK):
            body += chunk
            if len(body) > max_bytes:
                raise FetchError("too_large")
        return bytes(body)
