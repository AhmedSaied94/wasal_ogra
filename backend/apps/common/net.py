"""The client address, as the throttle and the admin lockout both see it (research R4)."""

from __future__ import annotations

from typing import TYPE_CHECKING, cast

from rest_framework.throttling import BaseThrottle

if TYPE_CHECKING:
    from django.http import HttpRequest
    from rest_framework.request import Request


def client_ip(request: HttpRequest | Request) -> str:
    """Behind `NUM_PROXIES` proxies, the matching `X-Forwarded-For` entry; else `REMOTE_ADDR`."""
    # get_ident only reads request.META, which a plain HttpRequest has too.
    return BaseThrottle().get_ident(cast("Request", request))
