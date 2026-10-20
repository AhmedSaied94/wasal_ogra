"""Building blocks shared by the content models (data-model.md "Conventions")."""

from __future__ import annotations

from enum import Enum
from typing import Any, ClassVar

from django.core.validators import RegexValidator
from django.db import models

from apps.common.models import UUIDv7Model

SLUG_PATTERN = r"^[a-z][a-z0-9_]{1,31}$"
slug_validator = RegexValidator(
    SLUG_PATTERN, "Use 2-32 lowercase letters, digits or underscores, starting with a letter."
)


def choices(enum: type[Enum]) -> list[tuple[Any, str]]:
    """Model choices from a generated glossary enum. The value is its own label."""
    return [(member.value, str(member.value)) for member in enum]


class TimestampedModel(UUIDv7Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class PermanentModel(TimestampedModel):
    """A row whose identifier becomes permanent once a published pack contains it (FR-016).

    `save()` refuses a rename, and `signals.py` refuses a delete, including queryset and cascade
    deletes. Subclasses name their `PublishedIdentifier` kind and the lookups that make up the full
    identifier, so it can be read back from the stored row.
    """

    permanent_kind: ClassVar[str]
    identifier_lookups: ClassVar[tuple[str, ...]]

    class Meta:
        abstract = True

    @classmethod
    def format_identifier(cls, parts: tuple[Any, ...]) -> str:
        """Stations, seats and scenes are qualified by their parent: `line_hay/kobri`."""
        return "/".join(str(part) for part in parts)

    def permanent_identifier(self) -> str:
        """The identifier as this instance would store it."""
        return self.format_identifier(
            tuple(_follow(self, lookup) for lookup in self.identifier_lookups)
        )

    def stored_identifier(self) -> str | None:
        """The identifier of the stored row, or `None` if the row isn't stored."""
        if self.pk is None:
            return None
        row = type(self)._base_manager.filter(pk=self.pk).values_list(*self.identifier_lookups)
        stored = row.first()
        return None if stored is None else self.format_identifier(tuple(stored))

    def save(self, *args: Any, **kwargs: Any) -> None:
        if not self._state.adding:
            from apps.content.services import permanence

            permanence.refuse_rename(self)
        super().save(*args, **kwargs)


def _follow(instance: object, lookup: str) -> Any:
    value = instance
    for name in lookup.split("__"):
        value = getattr(value, name)
    return value
