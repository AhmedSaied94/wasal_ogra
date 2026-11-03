"""The ads endpoints (B07 contracts/api.md). Views stay thin: the services decide."""

from __future__ import annotations

import logging
import uuid
from typing import cast

from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.views import CLIENT_HEADERS, error
from apps.accounts.models import Player
from apps.ads.api.serializers import RewardSerializer, SsvAnswerSerializer
from apps.ads.services import alerts, rewards, ssv
from apps.ads.services.keys import KeysUnavailable
from apps.ads.throttles import SsvThrottle
from apps.common.errors import ApiError, ErrorCode
from apps.common.throttles import PlayerRateThrottle

logger = logging.getLogger("apps.ads")

SSV_PARAMETERS = [
    OpenApiParameter(name, str, OpenApiParameter.QUERY, required=required, description=text)
    for name, required, text in (
        ("ad_network", False, "Recorded."),
        ("ad_unit", False, "Recorded."),
        (
            "custom_data",
            False,
            'URL-encoded compact JSON {"placement":"morning_piggy","nonce":"<uuid>"}, set by the '
            "app.",
        ),
        ("reward_amount", False, "Recorded, never used for the amount."),
        ("reward_item", False, "Recorded."),
        ("timestamp", False, "Milliseconds since the epoch; older than 7 days is refused."),
        ("transaction_id", False, "AdMob's id: the idempotency key."),
        ("user_id", False, "The player id, set by the app."),
        (
            "signature",
            True,
            "URL-safe base64 DER ECDSA (P-256, SHA-256) over the query before &signature=.",
        ),
        ("key_id", True, "The id of Google's verifier key. The last parameter."),
    )
]


class SsvView(APIView):
    """Public: Google calls it, and the signature is the credential (research R3). No token, no
    client headers, no version gate and no maintenance check: refusing a real callback would lose
    a player's reward."""

    authentication_classes = ()
    permission_classes = ()
    throttle_classes = (SsvThrottle,)
    http_method_names = ("get", "options")

    @extend_schema(
        operation_id="ads_ssv",
        summary="AdMob server-side verification callback",
        description=(
            "Called by Google after a rewarded ad, not by the app. Every validly signed callback "
            "answers 200 {} whatever happened to it (granted, a repeat, or recorded as refused), "
            "so the answer reveals nothing. Grants the morning piggy at most "
            "ads_morning_piggy_daily_cap times per game day; the amounts are live settings."
        ),
        parameters=SSV_PARAMETERS,
        responses={
            200: OpenApiResponse(SsvAnswerSerializer, description="Validly signed: recorded"),
            403: error("signature_invalid: missing, not verifying, or anything after key_id"),
            405: error("Method not allowed"),
            406: error("Not acceptable"),
            429: error("Too many callbacks from this address"),
            503: error("dependency_unavailable: Google's keys can't be had; nothing recorded"),
        },
        auth=[],
        tags=["ads"],
    )
    def get(self, request: Request) -> Response:
        try:
            ssv.process(request.META.get("QUERY_STRING", ""))
        except ssv.SignatureInvalid as refused:
            reason = str(refused)  # a fixed word: no player, reference or query
            logger.info("ad_ssv_refused", extra={"reason": reason})
            if reason in ssv.FORGED:
                alerts.signature_refused()
            raise ApiError(ErrorCode.SIGNATURE_INVALID) from None
        except KeysUnavailable:
            alerts.keys_unavailable()
            raise ApiError(ErrorCode.DEPENDENCY_UNAVAILABLE) from None
        return Response({})


class RewardView(APIView):
    """A player endpoint: the default authentication, permissions and limit. Never writes."""

    throttle_classes = (PlayerRateThrottle,)
    http_method_names = ("get", "options")

    @extend_schema(
        operation_id="ads_reward",
        summary="Has my ad reward arrived?",
        description=(
            "The caller's reward with this reference: granted (with the amounts and the wallet "
            "recounted to now) or refused (with the reason). 404 means not known yet, which is "
            "normal while Google's callback is on its way: poll at 1 s, 2 s and 4 s."
        ),
        parameters=[
            *CLIENT_HEADERS,
            OpenApiParameter("nonce", str, OpenApiParameter.PATH, description="The reference."),
        ],
        responses={
            200: RewardSerializer,
            400: error("A client header is missing or malformed"),
            401: error("token_expired or token_invalid: the access token"),
            403: error("account_deleted"),
            404: error("not_found: not recorded yet, not this player's, or not a UUID"),
            405: error("Method not allowed"),
            406: error("Not acceptable"),
            426: error("client_outdated: the app is below the platform's minimum"),
            429: error("Too many requests from this player"),
            503: error("The database or the cache is down"),
        },
        tags=["ads"],
    )
    def get(self, request: Request, nonce: str) -> Response:
        try:
            reference = uuid.UUID(nonce)
        except ValueError:
            raise ApiError(ErrorCode.NOT_FOUND) from None
        answer = rewards.lookup(cast("Player", request.user), reference)
        if answer is None:
            raise ApiError(ErrorCode.NOT_FOUND)
        return Response(answer)
