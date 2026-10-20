"""`content_import <dir-or-zip> --actor <staff>` (contracts/content-source.md)."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.exceptions import PermissionDenied
from django.core.management.base import BaseCommand, CommandError, CommandParser

from apps.content.management.actor import add_actor_argument, resolve_actor
from apps.content.services import importer


class Command(BaseCommand):
    help = "Import a content/source layout (a directory or a zip) as --actor. All or nothing."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("source", help="A layout directory, or a .zip of one.")
        add_actor_argument(parser)

    def handle(self, *args: Any, **options: Any) -> None:
        actor = resolve_actor(options["actor"])
        source = Path(options["source"])
        try:
            if source.is_dir():
                result = importer.import_dir(source, actor)
            elif source.is_file():
                result = importer.import_zip(source.read_bytes()[: importer.MAX_UPLOAD + 1], actor)
            else:
                raise CommandError(f"{source} is neither a directory nor a file.")
        except PermissionDenied as error:
            raise CommandError(str(error)) from None
        except importer.ImportRefused as refused:
            for finding in refused.findings:
                self.stderr.write(
                    f"{finding.file or '-'}: {finding.path} [{finding.code}] {finding.message}"
                )
            raise CommandError(str(refused)) from None
        self.stdout.write(
            f"Imported: {len(result.added)} added, {len(result.changed)} changed, "
            f"{result.unchanged} unchanged."
        )
