"""`content_files sync [--verify]` (contracts/pack-delivery.md "Keeping files and records").

The one content command without `--actor`: it changes no content, makes nothing current, and only
writes files already published, plus production's floor file (contracts/admin.md).
"""

from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from apps.content.services import files


class Command(BaseCommand):
    help = "Rewrite missing pack files from the database, and with --verify hash the present ones."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("action", choices=["sync"])
        parser.add_argument(
            "--verify", action="store_true", help="Hash every present file against its record."
        )

    def handle(self, *args: Any, **options: Any) -> None:
        result = files.sync_files(verify=options["verify"])
        for name in result.written:
            self.stdout.write(f"wrote {name}")
        if options["verify"]:
            self.stdout.write(f"{result.verified} files match their records")
        for problem in result.problems:
            self.stderr.write(problem)
        if result.problems:
            raise CommandError(f"{len(result.problems)} problems: see above.")
        self.stdout.write("files in sync")
