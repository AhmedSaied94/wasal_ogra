"""The content rules a change can break, raised from `save()`, signals and services."""

from __future__ import annotations

from django.core.exceptions import ValidationError


class ContentRuleError(ValidationError):
    """A change the content rules refuse. The message says which rule and why."""

    def __init__(self, message: str, *, code: str) -> None:
        super().__init__(message, code=code)


class PermanenceError(ContentRuleError):
    """An identifier in a published pack can't be renamed or deleted (FR-016)."""

    def __init__(self, kind: str, identifier: str, version: int, action: str) -> None:
        self.kind = kind
        self.identifier = identifier
        self.version = version
        super().__init__(
            f"{kind} {identifier} is in published pack version {version}, so it can't be {action}",
            code="permanent",
        )


class ImmutableError(ContentRuleError):
    """A stored record that can't change this way: a pack after validation, or the audit log."""

    def __init__(self, message: str) -> None:
        super().__init__(message, code="immutable")
