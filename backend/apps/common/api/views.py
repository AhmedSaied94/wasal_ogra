"""`/healthz` and `/readyz`, served by both the API and the admin containers (FR-010 - FR-012)."""

from __future__ import annotations

from django.http import HttpResponseBase
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.api.serializers import (
    ErrorEnvelopeSerializer,
    LivenessSerializer,
    ReadinessSerializer,
)
from apps.common.errors import ErrorCode, envelope
from apps.common.services import health

RATE_LIMITED = OpenApiResponse(ErrorEnvelopeSerializer, description="Too many requests")


class HealthView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    # HEAD too, because some uptime monitors use it.
    http_method_names = ("get", "head")


class HealthzView(HealthView):
    @extend_schema(
        operation_id="healthz",
        summary="Liveness",
        description="Answers while the process runs. Checks nothing outside it.",
        responses={200: LivenessSerializer, 429: RATE_LIMITED},
        tags=["health"],
    )
    def get(self, request: Request) -> Response:
        return Response(health.liveness())


class ReadyzView(HealthView):
    @extend_schema(
        operation_id="readyz",
        summary="Readiness",
        description="Ready when the database, the cache and the migrations all pass.",
        responses={
            200: ReadinessSerializer,
            429: RATE_LIMITED,
            503: OpenApiResponse(ErrorEnvelopeSerializer, description="A check failed"),
        },
        tags=["health"],
    )
    def get(self, request: Request) -> HttpResponseBase:
        result = health.readiness()
        if result.ready:
            return Response({"status": "ready", "checks": result.checks})
        return envelope(ErrorCode.NOT_READY, {"checks": result.checks})
