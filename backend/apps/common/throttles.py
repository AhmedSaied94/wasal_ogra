"""The per-address limit shared by every API process through the cache (FR-015, research R4)."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from django.conf import settings
from redis.exceptions import RedisError
from rest_framework.settings import api_settings
from rest_framework.throttling import SimpleRateThrottle

from apps.common.net import client_ip

if TYPE_CHECKING:
    # Type-only: DRF imports this module while it is still defining APIView.
    from rest_framework.request import Request
    from rest_framework.views import APIView

logger = logging.getLogger("wassal.throttle")

# Only the host calls these without the edge: container health checks and the deploy's verify step.
HOST_HEALTH_PATHS = frozenset({"/healthz", "/readyz"})


class AddressRateThrottle(SimpleRateThrottle):
    scope = "address"

    def get_rate(self) -> str | None:
        # Read on every request: DRF would otherwise keep the rate it saw at import time.
        # `None` turns the limit off (the `no_throttle` test fixture).
        rate: str | None = settings.THROTTLE_ADDRESS_RATE
        return rate

    def allow_request(self, request: Request, view: APIView) -> bool:
        if (
            (api_settings.NUM_PROXIES or 0) >= 1
            and "HTTP_X_FORWARDED_FOR" not in request.META
            and request.path in HOST_HEALTH_PATHS
        ):
            # The edge always adds the header and the app ports bind to 127.0.0.1, so only the
            # host gets here. Everything else is counted, header or not.
            return True
        try:
            return super().allow_request(request, view)
        except RedisError:
            # Fail open: a cache outage must not take down /healthz or the API (contracts/api.md).
            logger.warning("throttle cache unavailable, request allowed", exc_info=True)
            return True

    def get_cache_key(self, request: Request, view: APIView) -> str:
        return self.cache_format % {"scope": self.scope, "ident": client_ip(request)}
