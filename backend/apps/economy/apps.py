from django.apps import AppConfig


class EconomyConfig(AppConfig):
    name = "apps.economy"
    label = "economy"
    verbose_name = "Economy"

    def ready(self) -> None:
        # The ledger invariant and the operation handlers register on import.
        from apps.economy import invariants  # noqa: F401
        from apps.economy.api import schema  # noqa: F401 - the closed objects' OpenAPI shape
        from apps.economy.services import ops  # noqa: F401
