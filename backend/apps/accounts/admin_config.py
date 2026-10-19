"""`django.contrib.admin`, with the OTP-protected staff site as the default site (research R5).

Kept out of apps.py, where a second AppConfig would leave Django no default for `apps.accounts`.
"""

from django.contrib.admin.apps import AdminConfig


class StaffAdminConfig(AdminConfig):
    default_site = "apps.accounts.admin_site.StaffAdminSite"
