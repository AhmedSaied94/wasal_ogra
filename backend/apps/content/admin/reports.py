"""The validation report on a pack's page (contracts/admin.md "Validation report").

Stages in report order, errors first within each, and a link to the authoring object a finding
names when it still exists. The solver stage also lists its trips (B05).
"""

from __future__ import annotations

import re
from collections.abc import Callable, Mapping
from typing import Any

from django.db.models import Model, Q
from django.urls import reverse
from wassal_solver.settings import SCORE_INPUTS

from apps.content.admin.common import MAX_LISTED_FINDINGS, TRIP_ID
from apps.content.models import (
    Chapter,
    DailyRewardDay,
    FamilyRequest,
    Item,
    Line,
    Room,
    SpeechPool,
    TaskTemplate,
    Trip,
    Vehicle,
)
from apps.content.services.build import stage_order

ITEM_ID = re.compile(r"^([a-z0-9_]+)\.([a-z0-9_]+)$")


def _trip(identifier: str) -> Model | None:
    match = TRIP_ID.match(identifier)
    if match is None:
        return None
    return Trip.objects.filter(line__line_id=match[1], number=int(match[2])).first()


def _item(identifier: str) -> Model | None:
    match = ITEM_ID.match(identifier)
    if match is None:
        return None
    return Item.objects.filter(room__room_id=match[1], slug=match[2]).first()


def _day(identifier: str) -> Model | None:
    return DailyRewardDay.objects.filter(day_index=int(identifier)).first()


# Each entity a finding names, and how to find its authoring object from its identifier.
FINDERS: Mapping[str, Callable[[str], Model | None]] = {
    "line": lambda value: Line.objects.filter(line_id=value).first(),
    "vehicle": lambda value: Vehicle.objects.filter(vehicle_id=value).first(),
    "trip": _trip,
    "chapter": lambda value: Chapter.objects.filter(chapter_id=value).first(),
    "room": lambda value: Room.objects.filter(room_id=value).first(),
    "item": _item,
    "family_request": lambda value: FamilyRequest.objects.filter(request_id=value).first(),
    "speech_pool": lambda value: SpeechPool.objects.filter(speech_key=value).first(),
    "task": lambda value: TaskTemplate.objects.filter(task_id=value).first(),
    "daily_reward": _day,
}


def authoring_url(entity: str, identifier: str) -> str | None:
    """The admin page of the object a finding names, or None when there is none."""
    finder = FINDERS.get(entity)
    if finder is None or not identifier:
        return None
    try:
        found = finder(identifier)
    except ValueError:  # an identifier that isn't one of this entity's
        return None
    if found is None:
        return None
    meta = found._meta
    return reverse(f"admin:{meta.app_label}_{meta.model_name}_change", args=[found.pk])


def _trip_urls(trip_ids: list[str]) -> dict[str, str]:
    """The admin page of each trip named, in one query."""
    named = Q(pk__in=[])
    for trip_id in trip_ids:
        if match := TRIP_ID.match(trip_id):
            named |= Q(line__line_id=match[1], number=int(match[2]))
    found = Trip.objects.select_related("line").filter(named)
    return {
        trip.permanent_identifier(): reverse("admin:content_trip_change", args=[trip.pk])
        for trip in found
    }


def solver_rows(trips: list[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """`stages.solver.trips` as table rows, the inputs in SCORE_INPUTS order: `jsonb` doesn't
    keep key order."""
    urls = _trip_urls([str(trip.get("trip_id", "")) for trip in trips])
    rows = []
    for trip in trips:
        inputs = trip.get("inputs") or {}
        band = trip.get("band")
        rows.append(
            {
                **trip,
                "url": urls.get(str(trip.get("trip_id", ""))),
                "inputs": [inputs.get(name, "") for name in SCORE_INPUTS],
                "band": f"{band[0]}\N{EN DASH}{band[1]}" if band else "",
            }
        )
    return rows


def report_sections(report: Mapping[str, Any]) -> list[dict[str, Any]]:
    """One section per stage: its result, its findings (errors first), and how many are hidden.

    Stages follow `STAGES`: the stored report is `jsonb`, which doesn't keep key order.
    """
    findings = list(report.get("findings", []))
    stages = report.get("stages", {})
    sections = []
    for stage in sorted(stages, key=stage_order):
        outcome = stages[stage]
        own = sorted(
            (finding for finding in findings if finding.get("stage") == stage),
            key=lambda finding: finding.get("severity") != "error",
        )
        shown = [
            {**finding, "url": authoring_url(finding.get("entity", ""), finding.get("id", ""))}
            for finding in own[:MAX_LISTED_FINDINGS]
        ]
        sections.append(
            {
                "stage": stage,
                "result": outcome.get("result", ""),
                "bytes": outcome.get("bytes"),
                "findings": shown,
                "hidden": len(own) - len(shown),
                "trips": solver_rows(outcome.get("trips") or []),
                "meta": outcome.get("meta") or {},
                "input_names": SCORE_INPUTS,
            }
        )
    return sections
