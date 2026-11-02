"""The maintenance switch (B10 research R7, contracts/admin.md "Maintenance")."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from apps.accounts.models import User
from apps.liveops import settings as live
from apps.liveops.models import LiveopsChange
from apps.liveops.services import settings_admin


@dataclass(frozen=True)
class MaintenanceState:
    enabled: bool
    until: datetime | None


def state() -> MaintenanceState:
    snapshot = live.current()
    return MaintenanceState(
        enabled=snapshot["maintenance_enabled"], until=snapshot["maintenance_until"]
    )


def switch(
    enabled: bool,
    until: datetime | None = None,
    *,
    actor: User | None,
    note: str = "",
    source: str = LiveopsChange.Source.ADMIN,
) -> MaintenanceState:
    """Turn maintenance on (with an optional end) or off, in one recorded transaction."""
    values: dict[str, Any] = {
        "maintenance_enabled": enabled,
        "maintenance_until": until if enabled else None,
    }
    settings_admin.change_many(values, actor, note=note, source=source)
    # The values just written, not a snapshot another process may still be refreshing.
    return MaintenanceState(enabled=bool(enabled), until=until if enabled else None)
