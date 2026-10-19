"""`python manage.py restore_drill fetch|check <dir>` (contracts/operations.md "Restore drill").

- `fetch <dir>` needs the drill key variables and no database.
- `check <dir>` needs only `DATABASE_URL` and `DRILL_ROWCOUNT_TOLERANCE`. It prints the result line
  as one JSON line on stdout, and exits non-zero (after printing it) when the outcome is `fail`.

Both exit non-zero with a short reason, and no result line, when they can't finish.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.core.management.base import BaseCommand, CommandError, CommandParser
from django.db import connection

from apps.common.management.commands._b2 import read_storage
from apps.common.services import restore_drill
from config.env import Env, settings_name


def read_fetch_config(env: Env) -> restore_drill.FetchConfig:
    storage = read_storage(env)
    return restore_drill.FetchConfig(
        s3_endpoint=storage.endpoint,
        s3_region=storage.region,
        daily_bucket=storage.daily_bucket,
        weekly_bucket=storage.weekly_bucket,
        key_id=env.secret("B2_DRILL_KEY_ID"),
        app_key=env.secret("B2_DRILL_APP_KEY"),
        prefix=storage.prefix,
    )


class Command(BaseCommand):
    help = "Fetch the newest complete backup, or restore and check a fetched one."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("step", choices=["fetch", "check"])
        parser.add_argument("directory", type=Path)

    def handle(self, *args: Any, **options: Any) -> None:
        directory: Path = options["directory"]
        if not directory.is_dir():
            raise CommandError("the drill directory doesn't exist")
        env = Env(settings_name())
        try:
            if options["step"] == "fetch":
                self.run_fetch(env, directory)
            else:
                self.run_check(env, directory)
        except ImproperlyConfigured as exc:
            raise CommandError(str(exc)) from None
        except restore_drill.DrillError as exc:
            raise CommandError(str(exc)) from None

    def run_fetch(self, env: Env, directory: Path) -> None:
        meta = restore_drill.fetch(read_fetch_config(env), directory)
        self.stdout.write(f"fetched {meta['dump']['key']}")

    def run_check(self, env: Env, directory: Path) -> None:
        tolerance = env.integer("DRILL_ROWCOUNT_TOLERANCE", 0)
        result = restore_drill.check(
            directory,
            connection.settings_dict,
            tolerance=tolerance,
            release=str(settings.RELEASE),
        )
        self.stdout.write(json.dumps(result, separators=(",", ":")))
        if result["outcome"] != restore_drill.PASS:
            raise CommandError("the drill failed", returncode=1)
