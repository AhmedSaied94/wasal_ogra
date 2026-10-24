"""Fixed field messages for the auth endpoints (B02 FR-002).

DRF's defaults can repeat the submitted value (a choice's `"%(input)s" is not a valid choice.`), and
an install id or a token is a credential. Every field of the three request serializers takes its
messages from here, and none of them has a placeholder.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from django.utils.functional import _StrPromise  # django-stubs' name for a lazy string

REQUIRED = "This field is required."
NULL = "This field may not be null."
INSTALL_ID = "Must be a version-4 UUID."
PLATFORM = "Must be android or ios."
PLATFORM_MISMATCH = "Must equal the X-Platform header."
LOCALE = "Must be a language code with an optional region, such as ar-EG."
TOKEN = "Must be a token of at most 4096 characters."  # noqa: S105 - a message
PROVIDER = "Must be a supported provider."
PROVIDER_DISABLED = "This provider is not enabled here."
RESOLVE = "Must be switch_to_existing or keep_current."
PLAYER_ID = "Must be a player id."
RESOLVE_PAIR = "Send resolve and existing_player_id together."

# Every error key DRF's CharField, ChoiceField and UUIDField can raise.
KEYS = ("invalid", "invalid_choice", "blank", "max_length", "min_length")


def fixed(message: str) -> dict[str, str | _StrPromise]:
    """A field's error messages: `message` for any bad value, and the two fixed absences."""
    return {"required": REQUIRED, "null": NULL, **dict.fromkeys(KEYS, message)}
