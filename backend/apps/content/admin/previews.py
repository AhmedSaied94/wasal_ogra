"""The "Solver preview" panel on a trip's page (B05 contracts/content-pipeline.md §6).

The band is the trip's line as it is now, never one stored with the run, and the panel says when
the trip changed since its preview. Amounts are integer piasters, and the text is English.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from wassal_solver import Band, in_band
from wassal_solver.settings import SCORE_INPUTS

from apps.content.models import SolverRun, Trip
from apps.content.services import preview
from apps.content.services.solver_stage import EN_DASH, seconds

RUNNING = "The solver is running. Reload this page in a minute."
ALREADY = "A preview is already running."
STOPS = {
    "safety_cap": "the solver stopped at its safety cap",
    "internal_error": "internal solver error; see the error monitor",
}


def latest_preview(trip: Trip) -> SolverRun | None:
    return (
        SolverRun.objects.filter(trip=trip, kind=SolverRun.Kind.PREVIEW)
        .order_by("-created_at")
        .first()
    )


def _pieces(pieces: Mapping[str, int] | None) -> str:
    """`{"50": 1, "100": 2}` → `100+100+50`."""
    if not pieces:
        return ""
    ordered = sorted(((int(d), n) for d, n in pieces.items()), reverse=True)
    return "+".join(str(d) for d, n in ordered for _ in range(n))


def _loss(loss: Mapping[str, Any] | None) -> str:
    if not loss:
        return ""
    names = ", ".join(str(loss[k]) for k in ("passenger_id", "station_id") if loss.get(k))
    place = f" ({names})" if names else ""
    return f"First {loss['kind']} at {seconds(int(loss['t_ms']))} s{place}: {loss['detail']}"


def _score(result: Mapping[str, Any], band: Band) -> dict[str, Any]:
    score = result.get("score")
    if not isinstance(score, Mapping):
        return {"score": None, "inputs": [], "in_band": None}
    inputs = score["inputs"]
    return {
        "score": score["value"],
        "inputs": [
            (name, inputs[name]["value"], inputs[name]["points"])
            for name in SCORE_INPUTS
            if name in inputs
        ],
        "in_band": in_band(int(score["value"]), band),
    }


def preview_panel(trip: Trip) -> dict[str, Any] | None:
    """What the panel shows of the trip's latest preview, or None when there is none."""
    run = latest_preview(trip)
    if run is None:
        return None
    result: Mapping[str, Any] = run.result or {}
    band = Band(trip.line.difficulty_min, trip.line.difficulty_max)
    stop = result.get("error") or STOPS.get(str(result.get("end")), "")
    return {
        "run": run,
        "active": run.status in SolverRun.ACTIVE,
        "earlier": run.input_key != preview.current_key(trip),
        "verdict": result.get("verdict"),
        "end": result.get("end"),
        "stars": result.get("stars"),
        "band": f"{band.min}{EN_DASH}{band.max}",
        **_score(result, band),
        "settings_version": result.get("settings_version", ""),
        "first_loss": _loss(result.get("first_loss")),
        "timeline": [
            {
                "t": f"{seconds(int(entry['t_ms']))} s",
                "decision": entry["decision"],
                "passenger": entry.get("passenger_id", ""),
                "amount": entry.get("amount_piasters", ""),
                "pieces": _pieces(entry.get("pieces")),
                "note": entry.get("note", ""),
            }
            for entry in result.get("timeline", [])
        ],
        "refusals": result.get("refusals", []),
        "findings": result.get("findings", []),
        "stop": stop,
    }
