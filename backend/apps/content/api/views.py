"""`GET /v1/content/manifest` (contracts/api.md)."""

from __future__ import annotations

from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.api.serializers import ErrorEnvelopeSerializer
from apps.content.api.serializers import ContentManifestSerializer
from apps.content.services import manifest

ERROR = OpenApiResponse(ErrorEnvelopeSerializer)


class ManifestView(APIView):
    # Public (B02 FR-035): no token and no client headers. B01's address throttle applies.
    authentication_classes = ()
    permission_classes = (AllowAny,)
    http_method_names = ("get", "head", "options")

    @extend_schema(
        operation_id="content_manifest",
        summary="Content manifest",
        description=(
            "The content pack this app should have: the current one, or for an app below its "
            "minimum version the newest pack that app can read."
        ),
        parameters=[
            OpenApiParameter(
                "X-Client-Version",
                str,
                OpenApiParameter.HEADER,
                required=False,
                description="MAJOR.MINOR.PATCH, with any +BUILD suffix ignored.",
            )
        ],
        responses={
            200: ContentManifestSerializer,
            406: ERROR,
            429: OpenApiResponse(ErrorEnvelopeSerializer, description="Too many requests"),
            503: OpenApiResponse(ErrorEnvelopeSerializer, description="The database is down"),
        },
        tags=["content"],
    )
    def get(self, request: Request) -> Response:
        return Response(manifest.manifest_payload(request.headers.get("X-Client-Version")))
