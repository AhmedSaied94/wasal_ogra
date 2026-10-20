"""`content_build --actor <staff> [--dry-run] [--version N]` (contracts/admin.md).

A build runs synchronously, with the admin's checks. `--dry-run` builds in memory and prints the
checksums, even with findings, and saves nothing. `--version N` is for a dry run only (quickstart
§3): a real build always gets the next version.
"""

from __future__ import annotations

from typing import Any

from django.core.exceptions import PermissionDenied
from django.core.management.base import CommandError, CommandParser

from apps.content.management.actor import PackVersionCommand, add_actor_argument, resolve_actor
from apps.content.models import ContentPack
from apps.content.models.packs import Status
from apps.content.services import build, exporter, versioning
from apps.content.services.snapshot import snapshot


class Command(PackVersionCommand):
    help = "Build a draft pack from the current content, or with --dry-run only print the result."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--dry-run", action="store_true", help="Build in memory, print, save nothing."
        )
        parser.add_argument("--version", type=int, help="The version a dry run builds as.")
        add_actor_argument(parser)

    def handle(self, *args: Any, **options: Any) -> None:
        actor = resolve_actor(options["actor"])
        version, dry_run = options["version"], options["dry_run"]
        if version is not None and not dry_run:
            raise CommandError("--version is only for --dry-run: a build gets the next version.")
        if version is not None and version < 1:
            raise CommandError("--version must be at least 1.")
        try:
            build.require_builder(actor)
        except PermissionDenied as error:
            raise CommandError(str(error)) from None
        if dry_run:
            self._dry_run(version)
        else:
            self._build(build.new_draft(actor))

    def _dry_run(self, version: int | None) -> None:
        try:
            number = version or versioning.peek_next_version()
        except versioning.VersionFloorUnavailable as error:
            raise CommandError(str(error)) from None
        parts = snapshot(exporter.schema_version())
        output = build.produce(parts, number, build.current_pack(), review=True)
        self.stdout.write(f"version {output.version} (dry run, nothing saved)")
        self._summary(output.sha256, output.canonical_sha256, output.size, output.report)

    def _build(self, pack: ContentPack) -> None:
        pack = build.run_build(str(pack.pk))
        if pack.failure_reason:
            raise CommandError(f"The build failed: {pack.failure_reason}")
        self.stdout.write(f"version {pack.version}: {pack.status}")
        self._summary(pack.sha256, pack.canonical_sha256, pack.size, pack.validation_report)
        if pack.status != Status.VALIDATED:
            raise CommandError(f"Pack {pack.version} stays draft: see the findings above.")

    def _summary(self, sha256: str, canonical: str, size: int, report: dict[str, Any]) -> None:
        self.stdout.write(f"sha256 {sha256}")
        self.stdout.write(f"canonical_sha256 {canonical}")
        self.stdout.write(f"size {size}")
        stages = report["stages"]
        for stage in sorted(stages, key=build.stage_order):
            self.stdout.write(f"  {stage}: {stages[stage]['result']}")
        for finding in report["findings"]:
            self.stdout.write(
                f"  {finding['severity']} {finding['code']} {finding['entity']} {finding['id']} "
                f"{finding['path']}: {finding['message']}"
            )
