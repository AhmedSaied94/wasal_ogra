"""URLs of the API role (contracts/api.md). Later features register `/v1` routes on `router`."""

from django.conf import settings
from django.http import HttpRequest
from django.http.response import HttpResponseBase
from django.urls import include, path, re_path
from django.views.static import serve
from rest_framework.routers import SimpleRouter

from apps.accounts.api.views import AnonymousView, LinkView, RefreshView
from apps.common import errors
from apps.common.api.views import HealthzView, ReadyzView
from apps.content.api.views import ManifestView
from apps.economy.api.views import BootstrapView, StateView, SyncView

router = SimpleRouter()


def pack_file(request: HttpRequest, path: str) -> HttpResponseBase:
    """Dev only: a pack file with the edge's headers (contracts/pack-delivery.md).

    `serve` labels `core-N.json.gz` as gzip-encoded JSON, so an HTTP client unpacks it on the way
    and the app refuses the larger body. The edge sends the gzip file itself.
    """
    response = serve(request, path, document_root=str(settings.CONTENT_PACKS_DIR))
    if path.endswith(".gz"):
        response.headers.pop("Content-Encoding", None)
        response.headers["Content-Type"] = "application/gzip"
    return response


urlpatterns = [
    path("healthz", HealthzView.as_view(), name="healthz"),
    path("readyz", ReadyzView.as_view(), name="readyz"),
    path("v1/content/manifest", ManifestView.as_view(), name="content-manifest"),
    path("v1/auth/anonymous", AnonymousView.as_view(), name="auth-anonymous"),
    path("v1/auth/refresh", RefreshView.as_view(), name="auth-refresh"),
    path("v1/auth/link", LinkView.as_view(), name="auth-link"),
    path("v1/bootstrap", BootstrapView.as_view(), name="bootstrap"),
    path("v1/state", StateView.as_view(), name="state"),
    path("v1/sync", SyncView.as_view(), name="sync"),
    path("v1/", include(router.urls)),
]

if settings.DEBUG:
    # Dev only: the pack files the edge serves elsewhere (contracts/pack-delivery.md), so the
    # emulator can download what the manifest names. Only the edge's file names match.
    urlpatterns.append(
        re_path(
            r"^packs/(?P<path>core-[0-9]+\.(?:json\.gz|release\.json))$",
            pack_file,
        )
    )

# Last, so every unknown path gets the envelope, in dev too (contracts/api.md).
urlpatterns.append(re_path(r"^", errors.not_found))

handler404 = errors.handler404
handler500 = errors.handler500
