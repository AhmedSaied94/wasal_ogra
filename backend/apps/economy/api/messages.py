"""Fixed field messages for `POST /v1/sync` (contracts/api.md).

None repeats the submitted value: a payload may hold a display name, and an error body is logged
by clients and proxies (FR-044).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from django.utils.functional import _StrPromise  # django-stubs' name for a lazy string

REQUIRED = "This field is required."
NULL = "This field may not be null."
OBJECT = "Must be an object."
UNKNOWN = "Not a field of this object."
STATE_VERSION = "Must be an integer of at least 0."
OPS = "Must be a list of at most 100 operations."
TXN_ID = "Must be a version-7 UUID in its canonical lowercase form."
OP_TYPE = "Must be a string of 1 to 40 characters."
OCCURRED_AT = "Must be an ISO-8601 time in UTC, ending in Z."
PAYLOAD = "Must be an object."

# Every error key DRF's fields used here can raise.
KEYS = (
    "invalid",
    "blank",
    "max_length",
    "min_length",
    "max_value",
    "min_value",
    "not_a_list",
    "empty",
    "max_string_length",
)


def fixed(message: str) -> dict[str, str | _StrPromise]:
    """A field's error messages: `message` for any bad value, and the two fixed absences."""
    return {"required": REQUIRED, "null": NULL, **dict.fromkeys(KEYS, message)}
