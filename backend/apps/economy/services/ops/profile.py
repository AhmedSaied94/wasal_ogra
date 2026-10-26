"""`settings_update` (contracts/operations.md `settings_update`, research R10, FR-023).

The display name follows `accounts.services.names`; the settings are a closed set of the app's
keys, merged into what is stored. A refusal names the field and never echoes the value.
"""

from __future__ import annotations

import json
from typing import Any

from apps.accounts.services import names
from apps.economy.services.batch import BatchState
from apps.economy.services.payloads import OBJECT, STR, Field, PayloadError
from apps.economy.services.sync import Ctx, Rejected, register

MAX_SETTINGS_BYTES = 2048
# Each key's allowed values: a tuple of strings, or `bool`.
SETTINGS: dict[str, tuple[str, ...] | type[bool]] = {
    "digits": ("arabic", "western"),
    "sound": bool,
    "music": bool,
    "haptics": bool,
    "pre_trip_card_mode": ("always", "new_only"),
    "notif_daily": bool,
    "notif_story": bool,
    "notif_comeback": bool,
    "notif_league": bool,
}


def _settings(value: dict[str, Any]) -> dict[str, Any]:
    for key, setting in value.items():
        allowed = SETTINGS.get(key)
        if allowed is None:
            raise PayloadError("settings")
        valid = setting in allowed if isinstance(allowed, tuple) else type(setting) is bool
        if not valid:
            raise PayloadError("settings")
    return dict(value)


@register(
    "settings_update",
    payload={
        "display_name": Field(STR, required=False),
        "settings": Field(OBJECT, required=False, check=_settings),
    },
)
def settings_update(state: BatchState, ctx: Ctx) -> None:
    name: str | None = ctx.payload.get("display_name")
    changes: dict[str, Any] | None = ctx.payload.get("settings")
    if name is None and changes is None:
        raise Rejected("validation_error", {"field": "payload"})
    if name is not None:
        try:
            name = names.validate_display_name(name, state.name_filter())
        except names.NameRefused:
            raise Rejected("validation_error", {"field": "display_name"}) from None
    merged = None
    if changes is not None:
        merged = {**state.settings_stored, **changes}
        size = len(json.dumps(merged, separators=(",", ":")).encode())
        if size > MAX_SETTINGS_BYTES:
            raise Rejected("validation_error", {"field": "settings"})
    state.set_profile(display_name=name, settings=merged)
