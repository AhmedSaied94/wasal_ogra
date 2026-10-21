"""The bundled tunables: a byte-for-byte copy of `apps/mobile/assets/config/tunables.json`,
written by `wassal-solver sync` and drift-checked in CI (research R5).

The backend image has no `apps/`, so the solver reads its packaged copy.
"""

from __future__ import annotations

from functools import cache
from importlib import resources
from typing import Any

from wassal_content.loader import load_json_bytes

from wassal_solver.engine.params import TripParams

TUNABLES_FILE = "tunables.json"
APP_TUNABLES = ("apps", "mobile", "assets", "config", TUNABLES_FILE)
"""The app's file, from the repository root."""
PACKAGED_TUNABLES = ("tools", "solver", "src", "wassal_solver", "data", TUNABLES_FILE)
"""The packaged copy, from the repository root."""


@cache
def _bundled_bytes() -> bytes:
    return resources.files("wassal_solver").joinpath("data", TUNABLES_FILE).read_bytes()


def bundled_tunables() -> dict[str, Any]:
    """The packaged tunables, as a fresh dict."""
    values: dict[str, Any] = load_json_bytes(_bundled_bytes())
    return values


def bundled_params(line_id: str) -> TripParams:
    """The params every solve and fixture uses for a trip of `line_id`."""
    return TripParams.from_tunables(bundled_tunables(), line_id)
