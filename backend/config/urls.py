"""URLs of the API role (contracts/api.md). Later features register `/v1` routes on `router`."""

from django.urls import include, path, re_path
from rest_framework.routers import SimpleRouter

from apps.common import errors
from apps.common.api.views import HealthzView, ReadyzView

router = SimpleRouter()

urlpatterns = [
    path("healthz", HealthzView.as_view(), name="healthz"),
    path("readyz", ReadyzView.as_view(), name="readyz"),
    path("v1/", include(router.urls)),
    # Last, so every unknown path gets the envelope, in dev too (contracts/api.md).
    re_path(r"^", errors.not_found),
]

handler404 = errors.handler404
handler500 = errors.handler500
