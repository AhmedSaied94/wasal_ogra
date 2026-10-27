"""Seeds the dev stack for the app's backend tests (specs/011-m06-identity-sync, contracts/
ci-checks.md "The `sync-e2e` job").

Run from `backend/`, on the host, against the dev compose stack:

    uv run manage.py shell < ../apps/mobile/test/backend/seed_backend.py

It creates the staff user `ci`, imports `content/examples/sample`, builds it and publishes it as
version 1, the version dev builds bundle, through `apps.content.services` (publishing has no
command of its own), and writes the rules index. Dev's solver stage is the stand-in. A stack that
already has a current pack is left as it is. It prints the current version, and exits 1 unless it
is 1.
"""

import sys
from pathlib import Path

from django.contrib.auth.models import Group
from django.db import transaction

from apps.accounts.models import User
from apps.content.models.packs import Status
from apps.content.services import build, importer, lookups, publish

STAFF = "ci"
SAMPLE = Path.cwd().parent / "content" / "examples" / "sample"


def seed() -> int:
    user, _ = User.objects.get_or_create(username=STAFF, defaults={"is_staff": True})
    user.set_unusable_password()
    user.save()
    user.groups.add(*Group.objects.filter(name__in=["content_author", "content_publisher"]))
    # A fresh read: the permission cache predates the groups.
    user = User.objects.get(pk=user.pk)

    if build.current_pack() is None:
        importer.import_dir(SAMPLE, user)
        pack = build.run_build(str(build.new_draft(user).pk))
        if pack.failure_reason or pack.status != Status.VALIDATED:
            print(f"build failed: {pack.failure_reason or pack.status}", file=sys.stderr)
            return 1
        pack = publish.publish(str(pack.pk), user)
        if pack.failure_reason:
            print(f"publish failed: {pack.failure_reason}", file=sys.stderr)
            return 1

    with transaction.atomic():
        lookups.rebuild_index()
    current = build.current_pack()
    version = current.version if current else None
    print(f"published version {version}")
    return 0 if version == 1 else 1


sys.exit(seed())
