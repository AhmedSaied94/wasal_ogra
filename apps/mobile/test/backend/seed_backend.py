"""Seeds the dev stack for the app's backend tests (specs/011-m06-identity-sync, contracts/
ci-checks.md "The `sync-e2e` job").

Run from `backend/`, on the host, against the dev compose stack:

    uv run manage.py shell < ../apps/mobile/test/backend/seed_backend.py

It creates the staff user `ci` and puts `FILTERED` in the name filter (specs/012-m07-onboarding
T088: a name the phone lets through and the server refuses). It imports `content/examples/sample`,
reviews its speech lines (an import leaves them unreviewed, and the build's review stage refuses
those), builds it and publishes it as version 1, the version dev builds bundle, through
`apps.content.services` (publishing has no command of its own), and writes the rules index. Dev's
solver stage is the stand-in. A stack that already has a current pack is left as it is. It prints
the current version, and exits 1 unless it is 1.

The pack files go to the host's packs directory (`backend/var/packs` by default), which it creates,
not to the containers' `packs` volume. The server reads packs from the database, so the tests don't
need the files; only an app downloading a pack would.
"""

import sys
from pathlib import Path

from django.contrib.auth.models import Group
from django.db import transaction

from apps.accounts.models import NameFilterEntry, User
from apps.content.models import SpeechLine
from apps.content.models.packs import Status
from apps.content.services import build, files, importer, lookups, publish, review

STAFF = "ci"
# `first_session_sync_test.dart`'s refused name.
FILTERED = "ممنوع"
SAMPLE = Path.cwd().parent / "content" / "examples" / "sample"


def seed() -> int:
    user, _ = User.objects.get_or_create(username=STAFF, defaults={"is_staff": True})
    user.set_unusable_password()
    user.save()
    user.groups.add(*Group.objects.filter(name__in=["content_author", "content_publisher"]))
    # A fresh read: the permission cache predates the groups.
    user = User.objects.get(pk=user.pk)

    if not NameFilterEntry.objects.filter(term=FILTERED).exists():
        NameFilterEntry.objects.create(term=FILTERED, added_by=user)

    if build.current_pack() is None:
        importer.import_dir(SAMPLE, user)
        review.review_lines(SpeechLine.objects.order_by("pool", "order"), user)
        pack = build.run_build(str(build.new_draft(user).pk))
        if pack.failure_reason or pack.status != Status.VALIDATED:
            print(f"build failed: {pack.failure_reason or pack.status}", file=sys.stderr)
            for finding in (pack.validation_report or {}).get("findings", []):
                if finding.get("severity") == "error":
                    print(f"  {finding.get('code')} {finding.get('path')}", file=sys.stderr)
            return 1
        files.packs_dir().mkdir(parents=True, exist_ok=True)
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
