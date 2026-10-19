"""Model building blocks shared by every project app."""

from django.db import models

from apps.common.ids import uuid7


class UUIDv7Model(models.Model):
    """Abstract base with a UUIDv7 primary key (FR-016). System check `common.E001` enforces it."""

    id = models.UUIDField(primary_key=True, default=uuid7, editable=False)

    class Meta:
        abstract = True
