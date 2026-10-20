"""`content_export <dir> [--version N] --actor <staff>` (contracts/content-source.md)."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.exceptions import PermissionDenied
from django.core.management.base import CommandError, CommandParser

from apps.content.management.actor import (
    PackVersionCommand,
    add_actor_argument,
    resolve_actor,
)
from apps.content.models import ContentPack
from apps.content.models.packs import STORED
from apps.content.services import exporter


class Command(PackVersionCommand):
    help = (
        "Write the current content, or a published pack with --version, as a content/source "
        "layout into a new or empty directory."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("directory", help="Where to write the layout: new, or empty.")
        parser.add_argument("--version", type=int, help="A published or retired pack's version.")
        add_actor_argument(parser)

    def handle(self, *args: Any, **options: Any) -> None:
        actor = resolve_actor(options["actor"])
        root = Path(options["directory"])
        if root.exists() and (not root.is_dir() or any(root.iterdir())):
            raise CommandError(f"{root} is not an empty directory.")
        try:
            files = self._files(actor, options["version"])
        except PermissionDenied as error:
            raise CommandError(str(error)) from None
        for relative, data in sorted(files.items()):
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        self.stdout.write(f"Wrote {len(files)} files to {root}.")

    def _files(self, actor: Any, version: int | None) -> dict[str, bytes]:
        if version is None:
            return exporter.current_files(actor)
        pack = ContentPack.objects.filter(
            pack_id="core", version=version, status__in=sorted(STORED)
        ).first()
        if pack is None:
            raise CommandError(f"There is no published or retired pack {version}.")
        return exporter.pack_files(pack, actor)
