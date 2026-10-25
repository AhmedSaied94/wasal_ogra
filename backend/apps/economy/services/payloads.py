"""Payload shapes of the sync operations (contracts/operations.md).

Every payload is a closed object: a key not listed, a missing required key, a wrong type, a float
or a boolean where an integer belongs is `validation_error` for that operation only. Integers are
checked with `type(value) is int`, which refuses both `True` and `1.0`. A key not listed is named
`payload`, never by itself: the phone chose it, and the answer is stored. Strings may not hold NUL
or a lone surrogate, which no column or JSON value can store.
"""

from __future__ import annotations

import re
import uuid
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Any

# Wider than any count, amount or duration the game has, and exact in every JSON parser.
INT_LIMIT = 2**53
DEFAULT_MAX_LENGTH = 64
# Columns are PostgreSQL `integer`: what a stored count or revision may reach.
INT32_MAX = 2**31 - 1
_SURROGATES = re.compile("[\ud800-\udfff]")

INT = "int"
STR = "str"
UUID = "uuid"
BOOL = "bool"
OBJECT = "object"


class PayloadError(Exception):
    """The payload's shape is wrong at `field`."""

    def __init__(self, field: str) -> None:
        super().__init__(field)
        self.field = field


@dataclass(frozen=True)
class Field:
    kind: str
    required: bool = True
    minimum: int = -INT_LIMIT
    maximum: int = INT_LIMIT
    max_length: int = DEFAULT_MAX_LENGTH
    choices: tuple[str, ...] = ()
    # For an object: validates it and returns the cleaned value, or raises PayloadError.
    check: Callable[[Any], Any] | None = None


PayloadSpec = Mapping[str, Field]


def validate(spec: PayloadSpec, payload: Mapping[str, Any]) -> dict[str, Any]:
    """The cleaned payload: UUID strings become `uuid.UUID`. Raises `PayloadError`."""
    if any(key not in spec for key in payload):
        raise PayloadError("payload")
    cleaned: dict[str, Any] = {}
    for key, field in spec.items():
        if key not in payload:
            if field.required:
                raise PayloadError(key)
            continue
        cleaned[key] = _value(key, field, payload[key])
    return cleaned


def _value(key: str, field: Field, value: Any) -> Any:
    if field.kind == INT:
        if type(value) is not int or not field.minimum <= value <= field.maximum:
            raise PayloadError(key)
        return value
    if field.kind == STR:
        if not is_text(value, field.max_length):
            raise PayloadError(key)
        if field.choices and value not in field.choices:
            raise PayloadError(key)
        return value
    if field.kind == UUID:
        return as_uuid(key, value)
    if field.kind == BOOL:
        if type(value) is not bool:
            raise PayloadError(key)
        return value
    if field.kind == OBJECT:
        if not isinstance(value, dict):
            raise PayloadError(key)
        return field.check(value) if field.check else value
    raise PayloadError(key)  # pragma: no cover - a spec with an unknown kind


def is_text(value: Any, max_length: int) -> bool:
    """A string of 1 to `max_length` characters that PostgreSQL can store."""
    return (
        isinstance(value, str)
        and 1 <= len(value) <= max_length
        and "\x00" not in value
        and not _SURROGATES.search(value)
    )


def as_uuid(key: str, value: Any) -> uuid.UUID:
    """A UUID in its canonical 36-character form."""
    if not isinstance(value, str) or len(value) != 36:
        raise PayloadError(key)
    try:
        return uuid.UUID(value)
    except ValueError:
        raise PayloadError(key) from None


def maybe_uuid(value: Any) -> uuid.UUID | None:
    """`value` as a UUID if it is one, else None: for prefetching the ids a batch names."""
    try:
        return as_uuid("", value)
    except PayloadError:
        return None
