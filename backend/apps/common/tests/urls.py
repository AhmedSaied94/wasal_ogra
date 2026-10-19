"""The API routes plus test-only views (T015, T019). Select it with `pytest.mark.urls`."""

from typing import NoReturn

from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.db import InterfaceError, OperationalError
from django.http import Http404
from django.urls import path
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import TimeoutError as RedisTimeoutError
from rest_framework import serializers
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from config.urls import handler404, handler500
from config.urls import urlpatterns as api_urlpatterns

__all__ = ["handler404", "handler500", "urlpatterns"]


class OpenView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)


class EchoView(OpenView):
    def post(self, request: Request) -> Response:
        return Response({"received": request.data})


class OpenGetView(OpenView):
    def get(self, request: Request) -> Response:
        return Response({"ok": True})


class ThingView(OpenView):
    def get(self, request: Request, thing_id: object) -> Response:
        return Response({"ok": True})


class InnerSerializer(serializers.Serializer[None]):
    a = serializers.IntegerField()


class OuterSerializer(serializers.Serializer[None]):
    inner = InnerSerializer()
    items = InnerSerializer(many=True)


class NestedView(OpenView):
    def post(self, request: Request) -> Response:
        OuterSerializer(data=request.data).is_valid(raise_exception=True)
        return Response({})


class BearerAuthentication(BaseAuthentication):
    def authenticate(self, request: Request) -> None:
        return None

    def authenticate_header(self, request: Request) -> str:
        return 'Bearer realm="api"'


class NeedsAuthView(APIView):
    authentication_classes = (BearerAuthentication,)
    permission_classes = (IsAuthenticated,)

    def get(self, request: Request) -> Response:
        return Response({})


def raising(exc: Exception) -> type[APIView]:
    class RaisingView(OpenView):
        def get(self, request: Request) -> NoReturn:
            raise exc

    return RaisingView


# Before the API routes, which end with a catch-all.
urlpatterns = [
    path("test/echo", EchoView.as_view()),
    path("test/open", OpenGetView.as_view()),
    path("test/things/<uuid:thing_id>", ThingView.as_view()),
    path("test/nested", NestedView.as_view()),
    path("test/needs-auth", NeedsAuthView.as_view()),
    path("test/django-forbidden", raising(DjangoPermissionDenied("internal rule 7")).as_view()),
    path("test/db-closed", raising(InterfaceError("connection already closed")).as_view()),
    path("test/boom", raising(RuntimeError("secret internals")).as_view()),
    path("test/http404", raising(Http404("no such thing")).as_view()),
    path("test/forbidden", raising(PermissionDenied("you shall not pass")).as_view()),
    path(
        "test/invalid-fields",
        raising(ValidationError({"name": ["Too short."], "age": "Must be a number."})).as_view(),
    ),
    path("test/invalid", raising(ValidationError(["Pick one."])).as_view()),
    path(
        "test/db-down",
        raising(OperationalError("could not connect to server db.internal:5432")).as_view(),
    ),
    path(
        "test/cache-down",
        raising(RedisConnectionError("Error 111 connecting to cache.internal:6379")).as_view(),
    ),
    path(
        "test/cache-timeout",
        raising(RedisTimeoutError("Timeout reading from cache.internal:6379")).as_view(),
    ),
    *api_urlpatterns,
]
