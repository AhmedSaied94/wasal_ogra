"""`manage.py sentry_test [--task]`: send a test error to Sentry (FR-035, quickstart scenario 16).

A management command, so no test endpoint is ever exposed.
"""

from __future__ import annotations

from typing import Any

import sentry_sdk
from django.core.management.base import BaseCommand, CommandError, CommandParser

from apps.common.tasks import SentryTestError, sentry_test


class Command(BaseCommand):
    help = "Send a test error to Sentry from this process, or with --task from a worker."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--task", action="store_true", help="Queue a failing task on the default queue."
        )

    def handle(self, *args: Any, **options: Any) -> None:
        if options["task"]:
            sentry_test.apply_async(queue="default")
            self.stdout.write("Queued common.tasks.sentry_test on the default queue.")
            return
        error = SentryTestError("sentry_test: a test error from manage.py")
        event_id = sentry_sdk.capture_exception(error, tags={"sentry_test": "command"})
        if event_id is None:
            raise CommandError("Sentry isn't configured here (SENTRY_DSN is empty).")
        sentry_sdk.flush(timeout=10)
        self.stdout.write(f"Sent a test error to Sentry, event {event_id}.")
