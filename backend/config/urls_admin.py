"""URLs of the admin role (`ADMIN_ONLY=1`). Staff keep Django's HTML error pages."""

from django.contrib import admin
from django.urls import path

from apps.common.api.views import HealthzView, ReadyzView

urlpatterns = [
    path("admin/", admin.site.urls),
    path("healthz", HealthzView.as_view(), name="healthz"),
    path("readyz", ReadyzView.as_view(), name="readyz"),
]
