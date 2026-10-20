from django.apps import AppConfig


class ContentConfig(AppConfig):
    name = "apps.content"
    label = "content"
    verbose_name = "Content"

    def ready(self) -> None:
        from celery.signals import worker_init

        from apps.content import invariants, signals  # noqa: F401 - they register on import
        from apps.content.checks import check_packs_dir_on_worker_start

        worker_init.connect(check_packs_dir_on_worker_start, dispatch_uid="content.packs_dir")
