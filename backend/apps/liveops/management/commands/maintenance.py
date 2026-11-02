"""`maintenance status|on|off` (B10 contracts/admin.md "Command", FR-033).

`--actor` must name an active staff user holding `liveops.switch_maintenance`; otherwise the command
exits 2 with the reason and nothing changes. It writes through the same service as the admin, so the
switch is in the same history.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser
from django.utils import timezone

from apps.accounts.models import User
from apps.liveops.models import LiveopsChange
from apps.liveops.services import maintenance

APPLIES = "applies within 60 s"


def _actor(username: str) -> User:
    user = User.objects.filter(username=username).first()
    if user is None:
        raise CommandError(f"actor {username!r} doesn't exist", returncode=2)
    if not (user.is_active and user.is_staff):
        raise CommandError(f"actor {username!r} isn't an active staff user", returncode=2)
    if not user.has_perm("liveops.switch_maintenance"):
        raise CommandError(f"actor {username!r} lacks liveops.switch_maintenance", returncode=2)
    return user


def _until(raw: str) -> datetime:
    try:
        instant = datetime.fromisoformat(raw)
    except ValueError:
        raise CommandError(
            "--until must be ISO-8601 with a zone, such as 2026-11-03T15:30Z", returncode=2
        ) from None
    if instant.tzinfo is None:
        raise CommandError("--until must name a time zone", returncode=2)
    if instant <= timezone.now():
        raise CommandError("--until must be in the future", returncode=2)
    return instant.astimezone(UTC)


class Command(BaseCommand):
    help = "Turn maintenance on or off, or show its state."

    def add_arguments(self, parser: CommandParser) -> None:
        sub = parser.add_subparsers(dest="action", required=True)
        sub.add_parser("status")
        on = sub.add_parser("on")
        on.add_argument("--actor", required=True, help="A staff user with the permission.")
        on.add_argument("--until", help="ISO-8601 with a zone; empty means no end.")
        on.add_argument("--note", default="")
        off = sub.add_parser("off")
        off.add_argument("--actor", required=True, help="A staff user with the permission.")
        off.add_argument("--note", default="")

    def handle(self, *args: Any, **options: Any) -> None:
        action = options["action"]
        if action == "status":
            self._print(maintenance.state())
            return
        actor = _actor(options["actor"])
        if action == "on":
            until = _until(options["until"]) if options.get("until") else None
            state = maintenance.switch(
                True,
                until,
                actor=actor,
                note=options.get("note", ""),
                source=LiveopsChange.Source.COMMAND,
            )
        else:
            state = maintenance.switch(
                False,
                actor=actor,
                note=options.get("note", ""),
                source=LiveopsChange.Source.COMMAND,
            )
        self._print(state)

    def _print(self, state: maintenance.MaintenanceState) -> None:
        if not state.enabled:
            self.stdout.write("Maintenance is off.")
            return
        until = state.until.isoformat().replace("+00:00", "Z") if state.until else "no end"
        self.stdout.write(f"Maintenance is on until {until}; {APPLIES}.")
