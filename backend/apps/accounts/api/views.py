"""The auth endpoints (B02 contracts/api.md). Views stay thin: the services decide."""

from __future__ import annotations

import uuid
from typing import Any, cast

from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework.exceptions import ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api import messages
from apps.accounts.api.serializers import (
    AnonymousSerializer,
    AnonymousTokenPairSerializer,
    ConflictEnvelopeSerializer,
    LinkResultSerializer,
    LinkSerializer,
    RefreshSerializer,
    TokenPairSerializer,
)
from apps.accounts.models import Player
from apps.accounts.services import linking, players, sessions
from apps.accounts.services.sessions import IssuedTokens
from apps.common.api.serializers import ErrorEnvelopeSerializer
from apps.common.client import (
    MAX_STORED_VERSION,
    PLATFORM_HEADER,
    VERSION_HEADER,
    client_info,
)
from apps.common.errors import ApiError, ErrorCode
from apps.common.permissions import ClientHeaders
from apps.common.throttles import (
    AnonymousThrottle,
    LinkThrottle,
    PlayerRateThrottle,
    RefreshThrottle,
)

CLIENT_HEADERS = [
    OpenApiParameter(
        VERSION_HEADER,
        {
            "type": "string",
            "pattern": r"^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9A-Za-z.-]+)?$",
            "maxLength": MAX_STORED_VERSION,
        },
        OpenApiParameter.HEADER,
        required=True,
        description="MAJOR.MINOR.PATCH with an optional +BUILD, such as 1.4.0+57.",
    ),
    OpenApiParameter(
        PLATFORM_HEADER,
        str,
        OpenApiParameter.HEADER,
        required=True,
        enum=["android", "ios"],
    ),
]


def error(description: str) -> OpenApiResponse:
    return OpenApiResponse(ErrorEnvelopeSerializer, description=description)


def token_pair(issued: IssuedTokens) -> dict[str, Any]:
    return {
        "player_id": str(issued.player_id),
        "access": issued.access,
        "refresh": issued.refresh,
        "access_expires_in": issued.access_expires_in,
        "providers": list(issued.providers),
    }


class AnonymousView(APIView):
    """Public: the install id is the credential (FR-001)."""

    authentication_classes = ()
    permission_classes = (ClientHeaders,)
    throttle_classes = (AnonymousThrottle,)
    http_method_names = ("post", "options")

    @extend_schema(
        operation_id="auth_anonymous",
        summary="Create or return the device's player",
        description=(
            "The player of this install id, with a new session: created on the first call, "
            "returned afterwards, linked or not. A device whose player is pending deletion or "
            "deleted gets a new player."
        ),
        parameters=CLIENT_HEADERS,
        request=AnonymousSerializer,
        responses={
            200: OpenApiResponse(AnonymousTokenPairSerializer, description="The device's player"),
            201: OpenApiResponse(AnonymousTokenPairSerializer, description="A new player"),
            400: error("A field or header is invalid"),
            406: error("Not acceptable"),
            413: error("Payload too large"),
            415: error("Unsupported media type"),
            429: error("Too many accounts from this address"),
            503: error("The database is down"),
        },
        auth=[],
        tags=["auth"],
    )
    def post(self, request: Request) -> Response:
        client = client_info(request)
        serializer = AnonymousSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        if data["platform"] != client.platform:
            raise ValidationError({"platform": [messages.PLATFORM_MISMATCH]})
        issued, created = players.create_or_return(
            data["install_id"], data["platform"], data["locale"], client=client
        )
        return Response({**token_pair(issued), "created": created}, status=201 if created else 200)


class RefreshView(APIView):
    """Public: the refresh token is the credential (FR-009)."""

    authentication_classes = ()
    permission_classes = (ClientHeaders,)
    throttle_classes = (RefreshThrottle,)
    http_method_names = ("post", "options")

    @extend_schema(
        operation_id="auth_refresh",
        summary="Renew a session",
        description=(
            "The session's current refresh token gives a new pair. Its previous token, spent "
            "within the retry window, gives the same refresh token again. Any other spent token "
            "ends the session."
        ),
        parameters=CLIENT_HEADERS,
        request=RefreshSerializer,
        responses={
            200: TokenPairSerializer,
            400: error("A field or header is invalid"),
            401: error("token_expired, or token_invalid (which may have ended the session)"),
            403: error("account_deleted"),
            406: error("Not acceptable"),
            413: error("Payload too large"),
            415: error("Unsupported media type"),
            429: error("Too many renewals of this session"),
            503: error("The database is down"),
        },
        auth=[],
        tags=["auth"],
    )
    def post(self, request: Request) -> Response:
        client = client_info(request)
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        issued = sessions.rotate(serializer.validated_data["refresh"], client=client)
        return Response(token_pair(issued))


class LinkView(APIView):
    """A player endpoint: the default authentication and permissions (FR-019)."""

    throttle_classes = (PlayerRateThrottle, LinkThrottle)
    http_method_names = ("post", "options")

    @extend_schema(
        operation_id="auth_link",
        summary="Link Google, or resolve a conflict",
        description=(
            "Links the Google account of `id_token` to this player. If another active player "
            "holds it, the answer is 409 provider_in_use with both players' summaries; the retry "
            "names that player in `existing_player_id` with `resolve`: `switch_to_existing` "
            "answers that player's token pair and moves this device to it, `keep_current` moves "
            "the Google account here."
        ),
        parameters=CLIENT_HEADERS,
        request=LinkSerializer,
        responses={
            200: LinkResultSerializer,
            400: error("A field or header is invalid"),
            401: error("token_expired or token_invalid: the access token"),
            403: error("account_deleted"),
            406: error("Not acceptable"),
            409: OpenApiResponse(
                ConflictEnvelopeSerializer,
                description="provider_in_use (with both summaries) or provider_already_linked",
            ),
            413: error("Payload too large"),
            415: error("Unsupported media type"),
            422: error("provider_token_invalid, with details.reason"),
            429: error("Too many requests from this player"),
            503: error("Google's keys can't be fetched, or the database is down"),
        },
        tags=["auth"],
    )
    def post(self, request: Request) -> Response:
        client = client_info(request)
        serializer = LinkSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            session_id = uuid.UUID(str(request.auth["sid"]))  # type: ignore[index]
        except (KeyError, TypeError, ValueError):
            raise ApiError(ErrorCode.TOKEN_INVALID) from None
        result = linking.link(
            cast("Player", request.user),
            data["provider"],
            data["id_token"],
            session_id=session_id,
            client=client,
            resolve=data.get("resolve"),
            existing_player_id=data.get("existing_player_id"),
        )
        if isinstance(result, IssuedTokens):
            return Response(token_pair(result))
        return Response({"player_id": str(result.player_id), "providers": list(result.providers)})
