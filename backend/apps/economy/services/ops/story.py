"""The story's rewards (contracts/operations.md "Completion rewards", research R6).

`pay_completions` runs after an accepted `spend_jenehat` or `trip_result`: every room now complete
and every chapter whose goal is now met pays its `completion_bonat` once. BONAT the server grants
is the only BONAT a phone's operation can raise (the direction rule).
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime
from typing import Any

from apps.economy.models import Currency, GrantRecord, LedgerEntry
from apps.economy.services.batch import BatchState, StoryRow
from apps.economy.services.payloads import STR, Field
from apps.economy.services.sync import CONTENT_VERSION, Ctx, Rejected, register
from apps.progress.models import StoryState
from apps.progress.services import unlocks


@register(
    "story_progress",
    payload={
        "chapter_id": Field(STR, max_length=40),
        "scene_id": Field(STR, max_length=40),
        "content_version": CONTENT_VERSION,
    },
    content_version=True,
)
def story_progress(state: BatchState, ctx: Ctx) -> list[dict[str, Any]]:
    chapter_id: str = ctx.payload["chapter_id"]
    scene_id: str = ctx.payload["scene_id"]
    rules = ctx.pack_view().rules
    chapter = rules["chapters"].get(chapter_id)
    if chapter is None or scene_id not in chapter["scenes"]:
        raise Rejected("unknown_sku")
    if not unlocks.chapter_unlocked(rules, state.player_view(), chapter_id):
        raise Rejected("not_unlocked")
    row = state.story(chapter_id)
    if scene_id not in row.scenes_seen:
        state.set_story(
            chapter_id, StoryRow(row.status, [*row.scenes_seen, scene_id], row.completed_at)
        )
    return pay_completions(state, rules, ctx.t)


def pay_completions(
    state: BatchState, rules: Mapping[str, Any], at: datetime
) -> list[dict[str, Any]]:
    """Pay what the player's state now completes, rooms before chapters; the grants to answer."""
    granted: list[dict[str, Any]] = []
    for done in unlocks.newly_completed(rules, state.player_view(), state.granted_keys()):
        kind = GrantRecord.Kind.ROOM if done.kind == "room" else GrantRecord.Kind.CHAPTER
        state.credit(
            Currency.BONAT,
            done.bonat,
            LedgerEntry.Reason.STORY_REWARD,
            ref_type=done.kind,
            ref_id=done.id,
            source=LedgerEntry.Source.SYSTEM,
        )
        state.add_grant(kind, done.id, at)
        if kind == GrantRecord.Kind.CHAPTER:
            story = state.story(done.id)
            story.status = StoryState.Status.COMPLETED
            story.completed_at = at
            state.set_story(done.id, story)
        granted.append(
            {"kind": done.kind, "id": done.id, "currency": "BONAT", "amount": done.bonat}
        )
    return granted
