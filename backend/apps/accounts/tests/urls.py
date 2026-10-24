"""The API routes plus a test-only player view. Select it with `pytest.mark.urls`."""

from typing import cast

from django.urls import path
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import Token

from config.urls import handler404, handler500
from config.urls import urlpatterns as api_urlpatterns

__all__ = ["handler404", "handler500", "urlpatterns"]


class WhoAmIView(APIView):
    """A later player endpoint: the default authentication, permissions and limits."""

    def get(self, request: Request) -> Response:
        token = cast("Token", request.auth)
        return Response({"player_id": str(request.user.pk), "token_type": token["token_type"]})


# Before the API routes, which end with a catch-all.
urlpatterns = [path("test/whoami", WhoAmIView.as_view()), *api_urlpatterns]
