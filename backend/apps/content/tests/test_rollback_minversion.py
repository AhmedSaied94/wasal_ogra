"""Rollback and the minimum app version (tasks.md T079, FR-028, FR-032)."""

from __future__ import annotations

from pathlib import Path

import pytest
from django.core.exceptions import PermissionDenied, ValidationError
from django.test import Client
from pytest_django import DjangoCaptureOnCommitCallbacks, Settings

from apps.accounts.models import User
from apps.content import tasks
from apps.content.models import ContentAuditRecord, ContentPack, Trip
from apps.content.models.packs import Status
from apps.content.services import build, exporter, manifest, rollback
from apps.content.tests.factories import pack
from apps.content.tests.test_build import built
from apps.content.tests.test_publish import published

pytestmark = pytest.mark.django_db

Action = ContentAuditRecord.Action
Outcome = ContentAuditRecord.Outcome


@pytest.fixture(autouse=True)
def _packs(packs_dir: Path) -> Path:
    return packs_dir


def audit_rows(action: str) -> list[tuple[str, int | None, dict[str, object]]]:
    rows = ContentAuditRecord.objects.filter(action=action).order_by("at")
    return [(row.outcome, row.version, row.details) for row in rows]


def trips_of(stored: ContentPack) -> dict[str, dict[str, object]]:
    return {trip["trip_id"]: trip for trip in exporter.stored_pack(stored)["trips"]}


# -- rollback (US4-5, FR-028) ---------------------------------------------------------------------


def test_a_rollback_rebuilds_the_earlier_content_as_a_new_version(
    sample_reviewed: User,
    publisher: User,
    monkeypatch: pytest.MonkeyPatch,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    first = published(built(sample_reviewed), publisher)
    changed = Trip.objects.select_related("line").order_by("line__line_id", "number").first()
    assert changed is not None
    Trip.objects.filter(pk=changed.pk).update(seed=changed.seed + 1)
    second = published(built(sample_reviewed), publisher)
    changed_id = changed.permanent_identifier()
    queued: list[str] = []
    monkeypatch.setattr(tasks.build_pack, "delay", queued.append)

    with django_capture_on_commit_callbacks(execute=True):
        draft = rollback.request_rollback(first, publisher)
    assert queued == [str(draft.pk)]
    rolled = build.run_build(queued[0])

    assert (rolled.version, rolled.status, rolled.rollback_of) == (3, Status.VALIDATED, first)
    old, new, back = trips_of(first), trips_of(second), trips_of(rolled)
    assert back[changed_id]["seed"] == old[changed_id]["seed"]
    assert back[changed_id]["rev"] == int(new[changed_id]["rev"]) + 1  # type: ignore[call-overload]
    for trip_id in old:
        if trip_id != changed_id:
            assert back[trip_id] == new[trip_id]
    # The authoring tables still hold the later edit.
    assert Trip.objects.get(pk=changed.pk).seed == changed.seed + 1

    published(rolled, publisher)
    assert [(o, v, d["stage"]) for o, v, d in audit_rows(Action.ROLLBACK)] == [
        (Outcome.SUCCEEDED, 1, "queued"),
        (Outcome.SUCCEEDED, 3, "published"),
    ]
    assert audit_rows(Action.ROLLBACK)[1][2]["rollback_of"] == 1


def test_a_rollback_needs_rollback_pack_on_the_source(
    sample_reviewed: User, publisher: User, settings: Settings
) -> None:
    first = published(built(sample_reviewed), publisher)
    with pytest.raises(PermissionDenied):
        rollback.request_rollback(first, sample_reviewed)  # an author, not a publisher
    settings.CONTENT_ROLE = "target"
    with pytest.raises(PermissionDenied):
        rollback.request_rollback(first, publisher)

    assert ContentPack.objects.count() == 1
    assert [outcome for outcome, _, _ in audit_rows(Action.ROLLBACK)] == [Outcome.FAILED] * 2


def test_only_a_stored_pack_can_be_rolled_back_to(sample_reviewed: User, publisher: User) -> None:
    draft = built(sample_reviewed)
    with pytest.raises(ValidationError):
        rollback.request_rollback(draft, publisher)
    assert audit_rows(Action.ROLLBACK)[0][0] == Outcome.FAILED


# -- the minimum app version (US4-11, FR-032) -----------------------------------------------------


def test_raising_and_lowering_are_audited_and_offered(client: Client, publisher: User) -> None:
    older = pack(1, Status.PUBLISHED, min_client_version="1.0.0")
    current = pack(2, Status.PUBLISHED, min_client_version="1.0.0")

    manifest.change_min_client_version(current, "1.4.0", publisher)
    assert client.get("/v1/content/manifest", HTTP_X_CLIENT_VERSION="1.3.0").json()["version"] == 1
    manifest.change_min_client_version(current, "1.1.0", publisher)
    assert client.get("/v1/content/manifest", HTTP_X_CLIENT_VERSION="1.3.0").json()["version"] == 2

    assert [(o, v, d) for o, v, d in audit_rows(Action.MIN_CLIENT_VERSION_CHANGE)] == [
        (Outcome.SUCCEEDED, 2, {"old": "1.0.0", "new": "1.4.0"}),
        (Outcome.SUCCEEDED, 2, {"old": "1.4.0", "new": "1.1.0"}),
    ]
    assert older.min_client_version == "1.0.0"


@pytest.mark.parametrize("value", ["0.9.9", "1.4", "1.4.0+5", "v1.4.0", ""])
def test_values_below_the_floor_or_malformed_are_refused(publisher: User, value: str) -> None:
    current = pack(1, Status.PUBLISHED, min_client_version="1.2.0")

    with pytest.raises(ValidationError):
        manifest.change_min_client_version(current, value, publisher)

    assert ContentPack.objects.get(pk=current.pk).min_client_version == "1.2.0"
    [(outcome, _, details)] = audit_rows(Action.MIN_CLIENT_VERSION_CHANGE)
    assert outcome == Outcome.FAILED
    assert details["old"] == "1.2.0"
    assert details["new"] == value


def test_the_minimum_changes_on_both_roles_with_the_permission(
    publisher: User, sample_reviewed: User, settings: Settings
) -> None:
    current = pack(1, Status.PUBLISHED)
    settings.CONTENT_ROLE = "target"
    manifest.change_min_client_version(current, "1.3.0", publisher)
    with pytest.raises(PermissionDenied):
        manifest.change_min_client_version(current, "1.4.0", sample_reviewed)
    assert ContentPack.objects.get(pk=current.pk).min_client_version == "1.3.0"


def test_only_a_stored_pack_has_its_minimum_changed(publisher: User) -> None:
    validated = pack(1, Status.VALIDATED)
    with pytest.raises(ValidationError, match="published or retired"):
        manifest.change_min_client_version(validated, "1.3.0", publisher)
