"""Pings to Healthchecks.io dead-man's switches (FR-038, research R11)."""

from __future__ import annotations

from typing import Literal

import requests

PingKind = Literal["success", "fail", "start"]


def ping(
    url: str, *, kind: PingKind = "success", body: str | None = None, timeout: float = 10
) -> None:
    """Ping `url`, or `url/fail` or `url/start`. A non-empty `body` is POSTed as the check's log.

    An empty URL (dev, or a check that isn't set up) does nothing. Failures raise
    `requests.RequestException`, so a Celery task can retry them.
    """
    if not url:
        return
    target = url if kind == "success" else f"{url.rstrip('/')}/{kind}"
    # The URL is a secret (anyone holding it can fake pings), and requests puts it in its
    # exception text. Re-raise without it, so it stays out of Celery's log and Sentry.
    try:
        if body is None:
            # No redirects: a redirect would carry the secret URL to another host.
            response = requests.get(target, timeout=timeout, allow_redirects=False)
        else:
            response = requests.post(
                target, data=body.encode(), timeout=timeout, allow_redirects=False
            )
    except requests.RequestException as exc:
        raise requests.RequestException(f"ping failed: {type(exc).__name__}") from None
    if 300 <= response.status_code < 400:
        raise requests.HTTPError(f"ping failed: HTTP {response.status_code}")
    try:
        response.raise_for_status()
    except requests.HTTPError:
        raise requests.HTTPError(f"ping failed: HTTP {response.status_code}") from None
