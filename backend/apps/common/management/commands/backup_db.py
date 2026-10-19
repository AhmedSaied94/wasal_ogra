"""`python manage.py backup_db`: the nightly backup (contracts/operations.md "Backup job").

Only this command reads the B2 backup variables (contracts/environment.md), so the API and worker
settings never need them. A bad value is refused by name, never by value, and pings `/fail`.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.core.management.base import BaseCommand, CommandError
from django.db import connection

from apps.common.management.commands._b2 import read_storage
from apps.common.services import backups
from config.env import Env, settings_name

# Inside the container. The compose `backup` service mounts /var/lib/wassal/<env>/backup here.
DEFAULT_STATE_FILE = "/var/lib/wassal/backup/last-backup.json"


def read_config(env: Env) -> backups.BackupConfig:
    storage = read_storage(env)
    weekday = env.integer("BACKUP_WEEKLY_WEEKDAY", 6)
    if weekday > 6:
        raise ImproperlyConfigured("BACKUP_WEEKLY_WEEKDAY is invalid")
    environment = str(settings.WASSAL_ENV)
    state_file = env.string("BACKUP_STATE_FILE", DEFAULT_STATE_FILE)
    return backups.BackupConfig(
        environment=environment,
        release=str(settings.RELEASE),
        s3_endpoint=storage.endpoint,
        s3_region=storage.region,
        daily_bucket=storage.daily_bucket,
        weekly_bucket=storage.weekly_bucket,
        key_id=env.secret("B2_BACKUP_KEY_ID"),
        app_key=env.secret("B2_BACKUP_APP_KEY"),
        prefix=storage.prefix,
        weekly_weekday=weekday,
        ping_url=env.secret("HC_PING_BACKUP_URL"),
        state_file=Path(state_file),
    )


class Command(BaseCommand):
    help = "Dump the database to the B2 backup buckets and ping Healthchecks.io."

    def handle(self, *args: Any, **options: Any) -> None:
        env = Env(settings_name())
        try:
            config = read_config(env)
        except ImproperlyConfigured as exc:
            # The ping URL may be the very value that's missing.
            ping_url = env.string("HC_PING_BACKUP_URL", "")
            backups.notify(ping_url, kind="fail", body=f"configuration: {exc}")
            raise CommandError(str(exc)) from None
        try:
            database = backups.Database.from_settings(connection.settings_dict)
            meta = backups.run_backup(config, database)
        except backups.BackupError as exc:
            raise CommandError(str(exc)) from None
        self.stdout.write(f"backup {meta['dump'].get('key', '')} complete")
