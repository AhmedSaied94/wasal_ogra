"""`content_index --rebuild` (B03 research R2, quickstart B1).

Writes the missing trip, price and rules rows of every published pack inside the support window,
from the packs' stored files. Packs published before B03 have no rules row, and sync answers
`content_version_unsupported` for them until this runs: it is a deploy step. Idempotent. Like
`content_files`, it changes no content and makes nothing current, so it takes no `--actor`.
"""

from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser
from django.db import transaction

from apps.content.services import lookups


class Command(BaseCommand):
    help = "Write the missing index rows of the published packs inside the support window."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--rebuild", action="store_true", help="Write the missing rows (the only action)."
        )

    def handle(self, *args: Any, **options: Any) -> None:
        if not options["rebuild"]:
            raise CommandError("Say --rebuild to write the missing index rows.")
        with transaction.atomic():
            results = lookups.rebuild_index()
        for r in results:
            wrote = (
                f"wrote {r.trips_written} trips, {r.prices_written} prices"
                f"{', rules' if r.rules_written else ''}"
            )
            self.stdout.write(
                f"version {r.version}: {r.trips} trips, {r.prices} prices, rules ({wrote})"
            )
        if not results:
            self.stdout.write("no published pack inside the support window")
