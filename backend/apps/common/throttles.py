"""The API's limits, shared by every API process through the cache.

B01 (FR-015, research R4) limits each client address. B02 (research R9) adds the per-player limit
every player endpoint inherits, and the limits of the three auth endpoints. B03 (research R18) adds
the sync limit. Each rate is a setting read on every request, and every limit fails open when the
cache is down.
"""

from __future__ import annotations

import ipaddress
import logging
from typing import TYPE_CHECKING, Any

from django.conf import settings
from redis.exceptions import RedisError
from rest_framework.settings import api_settings
from rest_framework.throttling import SimpleRateThrottle

from apps.common.net import client_ip

if TYPE_CHECKING:
    # Type-only: DRF imports this module while it is still defining APIView.
    from uuid import UUID

    from rest_framework.request import Request
    from rest_framework.views import APIView

logger = logging.getLogger("wassal.throttle")

# Only the host calls these without the edge: container health checks and the deploy's verify step.
HOST_HEALTH_PATHS = frozenset({"/healthz", "/readyz"})
# A phone or a home network gets a whole IPv6 /64 and picks its own addresses in it.
IPV6_CLIENT_PREFIX = 64


def address_bucket(address: str) -> str:
    """What the address limits count: an IPv4 address, or an IPv6 address's /64. Per IPv6
    address, a client could take a fresh one for every request."""
    try:
        ip = ipaddress.ip_address(address)
    except ValueError:
        return address
    if isinstance(ip, ipaddress.IPv4Address):
        return str(ip)
    if ip.ipv4_mapped is not None:
        return str(ip.ipv4_mapped)
    return str(ipaddress.IPv6Network((ip, IPV6_CLIENT_PREFIX), strict=False))


class SettingRateThrottle(SimpleRateThrottle):
    """A limit whose rate is the setting `rate_setting`, and which fails open."""

    rate_setting = ""

    def get_rate(self) -> str | None:
        # Read on every request: DRF would otherwise keep the rate it saw at import time.
        # `None` turns the limit off (the `no_throttle` test fixture).
        rate: str | None = getattr(settings, self.rate_setting)
        return rate

    def allow_request(self, request: Request, view: APIView) -> bool:
        try:
            return super().allow_request(request, view)
        except RedisError:
            # Fail open: a cache outage must not take down /healthz or the API (contracts/api.md).
            logger.warning("throttle cache unavailable, request allowed", exc_info=True)
            return True

    def cache_key_for(self, ident: Any) -> str:
        return self.cache_format % {"scope": self.scope, "ident": ident}


class AddressRateThrottle(SettingRateThrottle):
    """Unauthenticated requests, per client address. A player's requests are limited per player."""

    scope = "address"
    rate_setting = "THROTTLE_ADDRESS_RATE"

    def allow_request(self, request: Request, view: APIView) -> bool:
        if request.auth is not None:
            return True
        if (
            (api_settings.NUM_PROXIES or 0) >= 1
            and "HTTP_X_FORWARDED_FOR" not in request.META
            and request.path in HOST_HEALTH_PATHS
        ):
            # The edge always adds the header and the app ports bind to 127.0.0.1, so only the
            # host gets here. Everything else is counted, header or not.
            return True
        return super().allow_request(request, view)

    def get_cache_key(self, request: Request, view: APIView) -> str:
        return self.cache_key_for(address_bucket(client_ip(request)))


class PlayerRateThrottle(SettingRateThrottle):
    """Every request authenticated as a player, per player (B02 FR-032, backend §6.5)."""

    scope = "player"
    rate_setting = "THROTTLE_PLAYER_RATE"

    def get_cache_key(self, request: Request, view: APIView) -> str | None:
        if request.auth is None:
            return None  # not limited here: the address limit counts it
        return self.cache_key_for(request.user.pk)


class AnonymousThrottle(SettingRateThrottle):
    """`POST /v1/auth/anonymous`, per client address. Carrier NAT puts many phones behind one
    address, hence 60 an hour (B02 research R9)."""

    scope = "anonymous"
    rate_setting = "THROTTLE_ANONYMOUS_RATE"

    def get_cache_key(self, request: Request, view: APIView) -> str:
        return self.cache_key_for(address_bucket(client_ip(request)))


class RefreshThrottle(SettingRateThrottle):
    """`POST /v1/auth/refresh`, per session, never per address: a thousand players behind one
    address renew freely (SC-008). A token that doesn't verify is limited per address instead, at
    B01's address rate, so garbage can't spend a player's budget."""

    scope = "refresh"
    rate_setting = "THROTTLE_REFRESH_RATE"

    def allow_request(self, request: Request, view: APIView) -> bool:
        session_id = _session_of(request)
        if session_id is not None:
            self.scope, self.rate_setting = "refresh", "THROTTLE_REFRESH_RATE"
            self.ident = str(session_id)
        else:
            self.scope, self.rate_setting = "refresh_address", "THROTTLE_ADDRESS_RATE"
            self.ident = address_bucket(client_ip(request))
        self.rate = self.get_rate()
        self.num_requests, self.duration = self.parse_rate(self.rate)
        return super().allow_request(request, view)

    def get_cache_key(self, request: Request, view: APIView) -> str:
        return self.cache_key_for(self.ident)


class LinkThrottle(SettingRateThrottle):
    """`POST /v1/auth/link`, per player, besides the per-player default."""

    scope = "link"
    rate_setting = "THROTTLE_LINK_RATE"

    def get_cache_key(self, request: Request, view: APIView) -> str | None:
        if request.auth is None:
            return None
        return self.cache_key_for(request.user.pk)


class SyncThrottle(SettingRateThrottle):
    """`POST /v1/sync`, per player, besides the per-player default (B03 research R18)."""

    scope = "sync"
    rate_setting = "THROTTLE_SYNC_RATE"

    def get_cache_key(self, request: Request, view: APIView) -> str | None:
        if request.auth is None:
            return None
        return self.cache_key_for(request.user.pk)


def _session_of(request: Request) -> UUID | None:
    """The `sid` of the request's refresh token if its signature verifies, expired or not."""
    # Imported here: DRF imports this module while it is still defining APIView.
    from apps.accounts import tokens
    from apps.common.errors import ApiError

    raw = request.data.get("refresh") if isinstance(request.data, dict) else None
    if not isinstance(raw, str) or len(raw) > tokens.MAX_TOKEN_LENGTH:
        return None
    try:
        return tokens.decode_refresh(raw, verify_exp=False).session_id
    except ApiError:
        return None
