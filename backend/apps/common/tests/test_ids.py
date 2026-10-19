"""The UUIDv7 primary-key building block (FR-016)."""

import uuid

from apps.common.ids import uuid7
from apps.common.models import UUIDv7Model


def test_uuid7_returns_stdlib_uuid_version_7() -> None:
    value = uuid7()
    assert isinstance(value, uuid.UUID)
    assert value.version == 7


def test_uuid7_values_are_unique_and_time_ordered() -> None:
    values = [uuid7() for _ in range(1000)]
    assert len(set(values)) == 1000
    assert values == sorted(values)


def test_uuidv7_model_primary_key() -> None:
    field = UUIDv7Model._meta.get_field("id")
    assert field.primary_key
    assert field.default is uuid7
    assert field.editable is False
    assert UUIDv7Model._meta.abstract
