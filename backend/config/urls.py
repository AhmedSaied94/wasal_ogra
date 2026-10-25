"""URLs of the API role (contracts/api.md). Later features register `/v1` routes on `router`."""

from django.conf import settings
from django.urls import include, path, re_path
from django.views.static import serve
from rest_framework.routers import SimpleRouter

from apps.accounts.api.views import AnonymousView, LinkView, RefreshView
from apps.common import errors
from apps.common.api.views import HealthzView, ReadyzView
from apps.content.api.views import ManifestView
from apps.economy.api.views import BootstrapView, StateView, SyncView

router = SimpleRouter()

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
            serve,
            {"document_root": settings.CONTENT_PACKS_DIR},
        )
    )

# Last, so every unknown path gets the envelope, in dev too (contracts/api.md).
urlpatterns.append(re_path(r"^", errors.not_found))

handler404 = errors.handler404
handler500 = errors.handler500
