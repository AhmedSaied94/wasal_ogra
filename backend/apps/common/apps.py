from django.apps import AppConfig


class CommonConfig(AppConfig):
    name = "apps.common"
    label = "common"
    verbose_name = "Common"

    def ready(self) -> None:
        from django.core import checks
        from django.core.signals import request_finished

        from apps.common.checks import check_uuid7_primary_keys
        from apps.common.logging import clear_request_id

        checks.register(check_uuid7_primary_keys, checks.Tags.models)
        request_finished.connect(clear_request_id, dispatch_uid="common.clear_request_id")
