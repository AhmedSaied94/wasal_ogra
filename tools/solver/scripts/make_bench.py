"""Writes the bench corpus: 50 trips derived from the sample pack (research R17).

Run from `tools/solver` with `uv run python scripts/make_bench.py`. It isn't packaged: only its
output, `src/wassal_solver/data/bench/*.json`, is. The variations are seeded by each new trip's
id, so running it again rewrites identical bytes.

Each trip starts from a sample trip of its line and changes, by a seeded draw:
- the tray counts;
- the station times, kept in order;
- up to three more passengers, in seats nobody else uses;
- the seed.

A draw that the content kit refuses is drawn again, from the same generator.
"""

from __future__ import annotations

import copy
import json
import random
import sys
from pathlib import Path
from typing import Any

from wassal_content.validate import document_findings

PACKAGE = Path(__file__).resolve().parents[1]
SAMPLE = PACKAGE.parents[1] / "content" / "examples" / "sample" / "trips"
OUT = PACKAGE / "src" / "wassal_solver" / "data" / "bench"
LINES = ("line_hay", "line_gamaa")
NUMBERS = range(51, 76)
"""Clear of the sample's ids (`<line_id>.<nn>`, TripId in content/schemas/common.schema.json)."""
TRAY_DENOMINATIONS = ("50", "100", "500", "1000", "2000")
PAYMENTS = ([1000], [500, 500], [500, 100, 100, 100], [2000], [500, 500, 100])
ADDED_ARCHETYPES = ("regular", "student", "hurry", "sleeper", "headphones")
MAX_TRIES = 50


def sample_trips(line_id: str) -> list[dict[str, Any]]:
    paths = sorted((SAMPLE / line_id).glob("*.json"))
    return [json.loads(path.read_text(encoding="utf-8")) for path in paths]


def vary(base: dict[str, Any], trip_id: str, rng: random.Random) -> dict[str, Any]:
    trip = copy.deepcopy(base)
    trip["trip_id"] = trip_id
    trip["rev"] = 1
    trip["seed"] = rng.randint(1, 2**31 - 1)
    tray = {
        key: max(0, base["initial_tray"].get(key, 0) + rng.randint(-3, 1))
        for key in TRAY_DENOMINATIONS
    }
    trip["initial_tray"] = {key: count for key, count in tray.items() if count > 0} or {"100": 1}
    shift = rng.randint(-3, 6)
    for station in trip["stations"]:
        station["at_seconds"] = min(600, max(1, station["at_seconds"] + shift))
    used = {p["seat_id"] for p in trip["passengers"]}
    free = [seat["seat_id"] for seat in trip["seats"] if seat["seat_id"] not in used]
    stations = [station["station_id"] for station in trip["stations"]]
    for n in range(rng.randint(0, 3)):
        if not free:
            break
        seat = free.pop(rng.randrange(len(free)))
        trip["passengers"].append(
            {
                "passenger_id": f"b{n + 1}",
                "archetype": rng.choice(ADDED_ARCHETYPES),
                "skin": "worker_blue",
                "seat_id": seat,
                "dest_station_id": rng.choice(stations),
                "payment": list(rng.choice(PAYMENTS)),
                "pays_at_seconds": rng.randint(0, 20),
            }
        )
    return trip


def valid(trip: dict[str, Any]) -> bool:
    return not [f for f in document_findings("trip", trip) if f.severity == "error"]


def make() -> dict[str, bytes]:
    """File name → bytes of every bench trip."""
    files: dict[str, bytes] = {}
    for line_id in LINES:
        bases = sample_trips(line_id)
        for number in NUMBERS:
            trip_id = f"{line_id}.{number}"
            rng = random.Random(trip_id)
            base = bases[(number - NUMBERS.start) % len(bases)]
            for _ in range(MAX_TRIES):
                trip = vary(base, trip_id, rng)
                if valid(trip):
                    break
            else:
                raise SystemExit(f"no valid variation of {base['trip_id']} for {trip_id}")
            text = json.dumps(trip, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
            files[f"{trip_id}.json"] = text.encode("utf-8")
    return files


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.json"):
        old.unlink()
    for name, data in make().items():
        (OUT / name).write_bytes(data)
    print(f"wrote {len(list(OUT.glob('*.json')))} trips to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
