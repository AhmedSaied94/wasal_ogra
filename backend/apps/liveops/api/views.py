"""`GET /v1/offers`: the store catalog and the caller's eligible offers (B10 US3, US5)."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import cast

from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.views import CLIENT_HEADERS, error
from apps.accounts.models import Player
from apps.common.client import client_info
from apps.common.throttles import PlayerRateThrottle
from apps.liveops.api.serializers import OffersSerializer
from apps.liveops.services import catalog, offers


def _iso(instant: datetime) -> str:
    return instant.astimezone(UTC).isoformat().replace("+00:00", "Z")


class OffersView(APIView):
    """A player endpoint: the defaults (token, headers, 426, throttle). A read, so no 503."""

    throttle_classes = (PlayerRateThrottle,)
    http_method_names = ("get", "options")

    @extend_schema(
        operation_id="offers",
        summary="The store catalog and this player's offers",
        description=(
            "The active products offered on this app's platform, in display order, with the BONAT "
            "and bonus each grants, and the offers this player is eligible for, priority first. "
            "There is no price: prices come from the store."
        ),
        parameters=CLIENT_HEADERS,
        responses={
            200: OffersSerializer,
            400: error("A client header is missing or malformed"),
            401: error("token_expired or token_invalid: the access token"),
            403: error("account_deleted"),
            405: error("Method not allowed"),
            406: error("Not acceptable"),
            426: error("client_outdated: the app is below the platform's minimum"),
            429: error("Too many requests from this player"),
            503: error("The database or the cache is down"),
        },
        tags=["economy"],
    )
    def get(self, request: Request) -> Response:
        info = client_info(request)
        player = cast("Player", request.user)
        listed = offers.eligible_offers(player, info.platform)
        response = Response(
            {
                "server_time": _iso(timezone.now()),
                "products": [
                    {
                        "product_id": product.product_id,
                        "kind": product.kind,
                        "bonat": product.bonat,
                        "bonus_bonat": product.bonus_bonat,
                        "entitlement": product.entitlement or None,
                        "best_value": product.best_value,
                    }
                    for product in catalog.active_products(info.platform)
                ],
                "offers": [
                    {
                        "offer_id": offer.offer_id,
                        "kind": offer.kind,
                        "product_id": offer.product.product_id,
                        "ends_at": _iso(offer.ends_at) if offer.ends_at else None,
                    }
                    for offer in listed
                ],
            }
        )
        response["Cache-Control"] = "private, no-store"
        return response
