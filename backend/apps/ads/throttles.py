"""The callback's own limit (B07 research R3): per client address, at `THROTTLE_SSV_RATE`.

Google calls from few addresses, so the callback has its own budget instead of the address limit
every unauthenticated request shares. Fails open with the cache, as every limit does.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from apps.common.net import client_ip
from apps.common.throttles import SettingRateThrottle, address_bucket

if TYPE_CHECKING:
    from rest_framework.request import Request
    from rest_framework.views import APIView


class SsvThrottle(SettingRateThrottle):
    scope = "ssv"
    rate_setting = "THROTTLE_SSV_RATE"

    def get_cache_key(self, request: Request, view: APIView) -> str:
        return self.cache_key_for(address_bucket(client_ip(request)))
