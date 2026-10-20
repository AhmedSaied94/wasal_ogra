"""Speech-line reviews (FR-017): only this service sets one."""

from __future__ import annotations

from collections.abc import Iterable

from django.contrib.admin.models import CHANGE, LogEntry
from django.utils import timezone

from apps.accounts.models import User
from apps.content.models import SpeechLine
from apps.content.services import permissions

REVIEW_MESSAGE = "Marked reviewed."


def review_lines(lines: Iterable[SpeechLine], actor: User | None) -> int:
    """Mark the lines reviewed by `actor`, now. Needs `review_speech`, on `source` only.

    The writer may review their own lines. Returns how many lines changed.
    """
    user = permissions.require(actor, "content.review_speech")
    permissions.require_role(permissions.SOURCE)
    now = timezone.now()
    changed = []
    for line in lines:
        if line.reviewed_by == user.username:
            continue
        line.reviewed_by, line.reviewed_at = user.username, now
        line.save(update_fields=["reviewed_by", "reviewed_at", "updated_at"])
        changed.append(line)
    if changed:
        LogEntry.objects.log_actions(
            user_id=user.pk, queryset=changed, action_flag=CHANGE, change_message=REVIEW_MESSAGE
        )
    return len(changed)
