"""The economy endpoints (contracts/api.md). Views stay thin: the services decide."""

from __future__ import annotations

from typing import Any, cast

from drf_spectacular.utils import extend_schema
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.views import CLIENT_HEADERS, error
from apps.accounts.models import Player
from apps.common.client import client_info
from apps.common.errors import ApiError, ErrorCode
from apps.common.throttles import PlayerRateThrottle, SyncThrottle
from apps.economy.api.serializers import (
    BootstrapSerializer,
    StateSerializer,
    SyncResultSerializer,
    SyncSerializer,
)
from apps.economy.services import bootstrap, state, sync

# The batch's own limit, under the edge's 512 KB (contracts/api.md "POST /v1/sync").
MAX_BODY_BYTES = 256 * 1024


def _content_length(request: Request) -> int:
    try:
        return int(request.META.get("CONTENT_LENGTH") or 0)
    except ValueError:
        return 0


def _result(result: sync.OpResult) -> dict[str, Any]:
    outcome = result.outcome
    entry: dict[str, Any] = {"client_txn_id": str(result.client_txn_id), "status": outcome.status}
    if outcome.reason:
        entry["reason"] = outcome.reason
    if outcome.granted:
        entry["granted"] = list(outcome.granted)
    if outcome.details:
        entry["details"] = dict(outcome.details)
    return entry


class SyncView(APIView):
    """A player endpoint: the default authentication and permissions, and its own limit."""

    throttle_classes = (PlayerRateThrottle, SyncThrottle)
    http_method_names = ("post", "options")

    @extend_schema(
        operation_id="sync",
        summary="Apply a batch of operations",
        description=(
            "Applies up to 100 operations in array order, in one transaction. Each is accepted "
            "or rejected with a reason; a rejection is not an error and doesn't stop the batch. "
            "Sending the same batch again returns the same results and changes nothing. The "
            "payload of each op_type and every reason are in contracts/operations.md."
        ),
        parameters=CLIENT_HEADERS,
        request=SyncSerializer,
        responses={
            200: SyncResultSerializer,
            400: error(
                "validation_error (details.fields names the first problem) or "
                "batch_too_large (details.max)"
            ),
            401: error("token_expired or token_invalid: the access token"),
            403: error("account_deleted"),
            405: error("Method not allowed"),
            406: error("Not acceptable"),
            413: error("Over 256 KB (details.limit_bytes)"),
            415: error("Unsupported media type"),
            429: error("Too many batches from this player"),
            503: error("The database or the cache is down; nothing was applied"),
        },
        tags=["economy"],
    )
    def post(self, request: Request) -> Response:
        if _content_length(request) > MAX_BODY_BYTES:
            raise ApiError(ErrorCode.PAYLOAD_TOO_LARGE, {"limit_bytes": MAX_BODY_BYTES})
        data = request.data
        ops = data.get("ops") if isinstance(data, dict) else None
        if isinstance(ops, list) and len(ops) > sync.MAX_OPS:
            raise ApiError(ErrorCode.BATCH_TOO_LARGE, {"max": sync.MAX_OPS})
        serializer = SyncSerializer(data=data)
        serializer.is_valid(raise_exception=True)
        valid = serializer.validated_data
        result = sync.process_batch(
            cast("Player", request.user),
            valid["base_state_version"],
            [sync.Op(**op) for op in valid["ops"]],
            client_version=client_info(request).version,
        )
        return Response(
            {
                "state_version": result.state_version,
                "state_stale": result.state_stale,
                "results": [_result(r) for r in result.results],
                "wallet": result.wallet,
            }
        )


class BootstrapView(APIView):
    """A player endpoint: the default authentication, permissions and limit."""

    throttle_classes = (PlayerRateThrottle,)
    http_method_names = ("get", "options")

    @extend_schema(
        operation_id="bootstrap",
        summary="Start or continue a session",
        description=(
            "Where the player stands: the wallet with its fuel recounted to now, the state "
            "version, the current content version, and whether this app must update. The first "
            "call creates the wallet. It answers 200 for any valid player, even an app below the "
            "minimum version."
        ),
        parameters=CLIENT_HEADERS,
        responses={
            200: BootstrapSerializer,
            400: error("A client header is missing or malformed"),
            401: error("token_expired or token_invalid: the access token"),
            403: error("account_deleted"),
            405: error("Method not allowed"),
            406: error("Not acceptable"),
            429: error("Too many requests from this player"),
            503: error("The database or the cache is down"),
        },
        tags=["economy"],
    )
    def get(self, request: Request) -> Response:
        return Response(bootstrap.bootstrap(cast("Player", request.user), client_info(request)))


class StateView(APIView):
    """A player endpoint: the default authentication, permissions and limit."""

    throttle_classes = (PlayerRateThrottle,)
    http_method_names = ("get", "options")

    @extend_schema(
        operation_id="state",
        summary="Everything the server holds of the player",
        description=(
            "A full snapshot at one state_version, read so that no batch applies in the middle: "
            "what a phone replaces its local state with (M05's replaceBase) before it re-sends "
            "what it still holds. The first call creates the wallet."
        ),
        parameters=CLIENT_HEADERS,
        responses={
            200: StateSerializer,
            400: error("A client header is missing or malformed"),
            401: error("token_expired or token_invalid: the access token"),
            403: error("account_deleted"),
            405: error("Method not allowed"),
            406: error("Not acceptable"),
            429: error("Too many requests from this player"),
            503: error("The database or the cache is down"),
        },
        tags=["economy"],
    )
    def get(self, request: Request) -> Response:
        return Response(state.snapshot(cast("Player", request.user)))
