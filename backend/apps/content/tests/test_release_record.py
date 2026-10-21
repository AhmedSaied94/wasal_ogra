"""The release record's `solver` object (B05 data-model.md "Release record addition", FR-030;
T086)."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any

from apps.content.models import ContentPack
from apps.content.services import release
from apps.content.services.promote import MAX_RELEASE_BYTES

PUBLISHED_AT = datetime(2026, 11, 2, 10, 5, tzinfo=UTC)
FINGERPRINT = "0123456789abcdef"
RECORD_TRIP_FIELDS = {
    "trip_id",
    "rev",
    "verdict",
    "stars",
    "score",
    "band",
    "params_fingerprint",
    "run_hash",
}


def summary(trip_id: str, score: int = 12) -> dict[str, Any]:
    """One trip of `stages.solver.trips`, as the real stage writes it."""
    return {
        "trip_id": trip_id,
        "rev": 3,
        "verdict": "solved",
        "end": "found",
        "stars": 3,
        "score": score,
        "inputs": {"owed_at_once": 2, "change_pieces": 7, "variety": 4},
        "band": [0, 30],
        "in_band": True,
        "run_hash": "a" * 64,
        "reused": False,
        "params_fingerprint": FINGERPRINT,
    }


def a_pack(solver: dict[str, Any], findings: list[dict[str, Any]] | None = None) -> ContentPack:
    stages = {s: {"result": "passed"} for s in ("schema", "references", "content_rules", "review")}
    return ContentPack(
        pack_id="core",
        version=7,
        schema_version="1.0",
        sha256="b" * 64,
        size=1234,
        min_client_version="1.0.0",
        built_at=datetime(2026, 11, 2, 10, 0, tzinfo=UTC),
        built_by="author1",
        validation_report={
            "stages": {**stages, "solver": solver},
            "findings": findings or [],
        },
    )


def record_of(pack: ContentPack) -> dict[str, Any]:
    document: dict[str, Any] = json.loads(release.release_record(pack, PUBLISHED_AT))
    return document


def real_stage(trips: list[dict[str, Any]], result: str = "passed") -> dict[str, Any]:
    meta = {
        "solver_fingerprint": FINGERPRINT,
        "settings_version": "fedcba9876543210",
        "solved": 1,
        "reused": len(trips) - 1,
    }
    return {"result": result, "trips": trips, "meta": meta}


def test_the_solver_object_names_the_solver_and_settings_and_each_trip() -> None:
    record = record_of(a_pack(real_stage([summary("line_hay.01"), summary("line_hay.02", 19)])))

    solver = record["solver"]
    assert set(solver) == {"solver_fingerprint", "settings_version", "trips"}
    assert solver["solver_fingerprint"] == FINGERPRINT
    assert solver["settings_version"] == "fedcba9876543210"
    assert [trip["trip_id"] for trip in solver["trips"]] == ["line_hay.01", "line_hay.02"]
    assert solver["trips"][1] == {
        "trip_id": "line_hay.02",
        "rev": 3,
        "verdict": "solved",
        "stars": 3,
        "score": 19,
        "band": [0, 30],
        "params_fingerprint": FINGERPRINT,
        "run_hash": "a" * 64,
    }
    assert record["stages"]["solver"] == "passed"


def test_the_record_has_no_runs_timelines_inputs_or_staff_names() -> None:
    stage = real_stage([summary("line_hay.01")])
    stage["trips"][0]["timeline"] = [{"t_ms": 0, "decision": "pick"}]
    stage["trips"][0]["run"] = [{"t_ms": 0, "command": {"type": "tap"}}]

    record = record_of(a_pack(stage))

    assert set(record["solver"]["trips"][0]) == RECORD_TRIP_FIELDS
    text = json.dumps(record)
    for absent in ("inputs", "owed_at_once", "timeline", '"run"', "reused", "author1"):
        assert absent not in text


def test_the_v_z5_findings_are_the_warnings() -> None:
    warning = {
        "code": "V-Z5",
        "entity": "trip",
        "id": "line_hay.02",
        "path": "$.trips[1]",
        "message": "difficulty 31 is outside the line's band 0\N{EN DASH}30; most from variety",
        "severity": "warning",
        "stage": "solver",
    }
    stage = real_stage([summary("line_hay.01"), summary("line_hay.02", 31)], result="warning")

    record = record_of(a_pack(stage, [warning]))

    assert record["stages"]["solver"] == "warning"
    assert record["warnings"] == [{k: warning[k] for k in release.WARNING_FIELDS}]


def test_the_stand_in_is_named_and_lists_no_trips() -> None:
    stand_in = {"result": "passed", "trips": [], "meta": {"stand_in": True}}
    assert record_of(a_pack(stand_in))["solver"] == {"stand_in": True, "trips": []}


def test_a_200_trip_summary_stays_under_the_release_cap() -> None:
    trips = [summary(f"line_l{n // 20:02d}.{n % 20 + 1:02d}", n % 101) for n in range(200)]

    record = release.release_record(a_pack(real_stage(trips)), PUBLISHED_AT)

    assert len(json.loads(record)["solver"]["trips"]) == 200
    assert len(record) < MAX_RELEASE_BYTES
