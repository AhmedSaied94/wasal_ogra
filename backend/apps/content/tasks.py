"""Background tasks of the content pipeline, all on the `content` queue (research R10)."""

from __future__ import annotations

from celery import Task, shared_task
from django.db import OperationalError

from apps.accounts.models import User
from apps.content.services import build, files, preview, promote, publish


@shared_task(
    name="content.tasks.build_pack",
    bind=True,
    queue="content",
    acks_late=True,
    reject_on_worker_lost=True,
    autoretry_for=(OperationalError,),
    retry_backoff=True,
    max_retries=3,
)
def build_pack(self: Task[[str], None], pack_pk: str) -> None:
    """Build one queued draft. A redelivered or repeated job changes nothing once it finished."""
    build.run_build(pack_pk)


@shared_task(name="content.tasks.sweep_stuck_builds", bind=True, queue="content", max_retries=0)
def sweep_stuck_builds(self: Task[[], int]) -> int:
    """Every 10 minutes: builds still `running` after 30 minutes become `failed`."""
    return build.sweep_stuck_builds()


@shared_task(
    name="content.tasks.publish_pack",
    bind=True,
    queue="content",
    acks_late=True,
    reject_on_worker_lost=True,
    autoretry_for=(OperationalError,),
    retry_backoff=True,
    max_retries=3,
)
def publish_pack(self: Task[[str, str], None], pack_pk: str, username: str) -> None:
    """Publish one validated pack. The actor's permissions are checked again here."""
    actor = User.objects.filter(username=username).first()
    publish.publish(pack_pk, actor)


@shared_task(name="content.tasks.sync_files", bind=True, queue="content", max_retries=0)
def sync_files(self: Task[[bool], None], verify: bool = False) -> None:
    """Daily with `verify`: rewrite missing pack files and check the present ones."""
    files.sync_files(verify=verify)


# Network errors are retried inside each fetch (services/http.py), and a failed promotion is
# audited, so the job itself only retries a lost database connection.
@shared_task(
    name="content.tasks.promote_pack",
    bind=True,
    queue="content",
    acks_late=True,
    reject_on_worker_lost=True,
    autoretry_for=(OperationalError,),
    retry_backoff=True,
    max_retries=3,
)
def promote_pack(self: Task[[str, str], None], code: str, username: str) -> None:
    """Promote the pack a pasted code names. The actor's permissions are checked again here."""
    actor = User.objects.filter(username=username).first()
    promote.promote(code, actor)


@shared_task(
    name="content.tasks.solve_trip",
    bind=True,
    queue="content",
    acks_late=True,
    reject_on_worker_lost=True,
    autoretry_for=(OperationalError,),
    retry_backoff=True,
    max_retries=3,
)
def solve_trip(self: Task[[str], None], run_pk: str) -> None:
    """Solve one queued trip preview (B05). A redelivered job finds the run running or finished
    and changes nothing."""
    preview.run_preview(run_pk)
