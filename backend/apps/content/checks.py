"""The worker's startup check (contracts/environment.md): `CONTENT_PACKS_DIR` is writable.

Only the worker writes pack files, so only the worker checks. The API, admin and beat containers
don't mount the directory, and neither does the deploy's `check --deploy`. On production the
worker then creates a missing floor file (contracts/pack-delivery.md "The floor file").
"""

from __future__ import annotations

import contextlib
import logging
import tempfile
from pathlib import Path
from typing import Any

from django.conf import settings

logger = logging.getLogger(__name__)


def packs_dir_problem(path: Path) -> str | None:
    """Why the worker can't write pack files to `path`, or `None`."""
    if not path.is_dir():
        return "CONTENT_PACKS_DIR doesn't exist or isn't a directory"
    try:
        with tempfile.TemporaryFile(dir=path):
            pass
    except OSError:
        return "CONTENT_PACKS_DIR isn't writable by the worker"
    return None


def check_packs_dir_on_worker_start(**kwargs: Any) -> None:
    """A `worker_init` receiver. Celery logs and ignores a receiver's `Exception`, so a problem
    stops the worker with `SystemExit` instead."""
    path = Path(settings.CONTENT_PACKS_DIR)
    if settings.WASSAL_ENV == "dev":
        # backend/var/packs, gitignored, when the worker runs on the host. A failure is reported
        # below, as on the hosts: an OSError here would only be logged by Celery.
        with contextlib.suppress(OSError):
            path.mkdir(parents=True, exist_ok=True)
    problem = packs_dir_problem(path)
    if problem is not None:
        logger.critical(problem)
        raise SystemExit(problem)
    from apps.content.services import files  # models are loaded once the worker starts

    files.ensure_floor()
