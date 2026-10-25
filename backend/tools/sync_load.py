"""The sync endpoints' latency on a live server (B03 quickstart B4, SC-008). Never run in CI.

Run on the operator's machine, from `backend/`, against staging (or production, briefly):

    uv run python tools/sync_load.py --base https://<api host> [--players 50] [--batches 20] \
        [--concurrency 10] [--trip line_hay.01]

It signs in `--players` new anonymous players (they show in the admin as anonymous players with
no progress worth keeping), and for each one times `GET /v1/bootstrap`, `GET /v1/state` and
`--batches` batches of 100 operations, then prints p50 and p95 per call. The targets (SC-008):
p95 under 200 ms for bootstrap, 400 ms for state and 1 s for a batch of 100.

Each batch holds ten starts and results of `--trip` (from the second batch on, most starts are
refused for fuel, which is still the full path) and 80 `settings_update` operations. A 429 is
waited out (its `Retry-After`) and counted, not timed: the per-address and anonymous sign-in
limits (`THROTTLE_ADDRESS_RATE`, `THROTTLE_ANONYMOUS_RATE`) cap a run from one address, so raise
them in the environment for the run or use fewer players.
"""

from __future__ import annotations

import argparse
import statistics
import sys
import time
import uuid
from collections.abc import Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from urllib.parse import urlsplit

import requests
from uuid_utils import compat

TIMEOUT_S = 30
HEADERS = {"X-Client-Version": "1.0.0", "X-Platform": "android"}
OPS_PER_BATCH = 100
TRIPS_PER_BATCH = 10
LOCAL_HOSTS = ("localhost", "127.0.0.1")
TARGET_P95_MS = {"bootstrap": 200, "state": 400, "sync": 1000}


@dataclass
class Timings:
    calls: dict[str, list[float]] = field(default_factory=dict)
    throttled: int = 0

    def add(self, name: str, ms: float) -> None:
        self.calls.setdefault(name, []).append(ms)


def now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def envelope(op_type: str, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "client_txn_id": str(compat.uuid7()),
        "op_type": op_type,
        "occurred_at": now_iso(),
        "payload": payload,
    }


def batch_of(version: int, trip: str, base: int) -> dict[str, Any]:
    ops: list[dict[str, Any]] = []
    for _ in range(TRIPS_PER_BATCH):
        start = envelope(
            "trip_start", {"trip_id": trip, "content_version": version, "fuel_mode": "fuel"}
        )
        result = {
            "trip_id": trip,
            "rev": 1,
            "outcome": "abandoned",
            "stars": 0,
            "earnings_jenehat": 0,
            "duration_ms": 1,
            "fights": 0,
            "mistakes": [],
            "boosters_used": [],
            "revived": False,
            "command_log_hash": "0" * 64,
        }
        ops += [
            start,
            envelope("trip_result", {"trip_start_txn": start["client_txn_id"], "result": result}),
        ]
    while len(ops) < OPS_PER_BATCH:
        digits = "arabic" if len(ops) % 2 else "western"
        ops.append(envelope("settings_update", {"settings": {"digits": digits}}))
    return {"base_state_version": base, "ops": ops}


def timed(
    session: requests.Session, timings: Timings, name: str, method: str, url: str, **kwargs: Any
) -> requests.Response:
    """One call, timed; a 429 is waited out and tried again, untimed."""
    while True:
        began = time.perf_counter()
        response = session.request(method, url, timeout=TIMEOUT_S, **kwargs)
        elapsed = (time.perf_counter() - began) * 1000
        if response.status_code != 429:
            response.raise_for_status()
            timings.add(name, elapsed)
            return response
        timings.throttled += 1
        time.sleep(float(response.headers.get("Retry-After", "5")))


def one_player(base: str, batches: int, trip: str) -> Timings:
    timings = Timings()
    with requests.Session() as session:
        session.headers.update(HEADERS)
        signed = timed(
            session,
            timings,
            "sign_in",
            "POST",
            f"{base}/v1/auth/anonymous",
            json={"install_id": str(uuid.uuid4()), "platform": "android", "locale": "ar-EG"},
        ).json()
        session.headers["Authorization"] = f"Bearer {signed['access']}"
        launch = timed(session, timings, "bootstrap", "GET", f"{base}/v1/bootstrap").json()
        version = launch["content"]["version"]
        if version is None:
            raise SystemExit("The server has no published pack: nothing to sync against.")
        state_version = launch["state_version"]
        timed(session, timings, "state", "GET", f"{base}/v1/state")
        for _ in range(batches):
            answer = timed(
                session,
                timings,
                "sync",
                "POST",
                f"{base}/v1/sync",
                json=batch_of(version, trip, state_version),
            ).json()
            state_version = answer["state_version"]
    return timings


def report(all_timings: list[Timings]) -> bool:
    """Print p50/p95 per call; True when every target of SC-008 is met."""
    merged = Timings()
    for timings in all_timings:
        merged.throttled += timings.throttled
        for name, values in timings.calls.items():
            merged.calls.setdefault(name, []).extend(values)
    met = True
    print(f"{'call':<10} {'n':>6} {'p50 ms':>8} {'p95 ms':>8}  target p95")
    for name, values in sorted(merged.calls.items()):
        cuts = (
            statistics.quantiles(values, n=100, method="inclusive")
            if len(values) > 1
            else values * 99
        )
        p50, p95 = cuts[49], cuts[94]
        target = TARGET_P95_MS.get(name)
        verdict = "" if target is None else f"{target} {'ok' if p95 <= target else 'MISSED'}"
        met = met and (target is None or p95 <= target)
        print(f"{name:<10} {len(values):>6} {p50:>8.0f} {p95:>8.0f}  {verdict}")
    print(f"throttled (429, waited out): {merged.throttled}")
    return met


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", required=True, help="The API's base URL, such as https://api…")
    parser.add_argument("--players", type=int, default=50)
    parser.add_argument("--batches", type=int, default=20, help="Batches of 100 per player.")
    parser.add_argument("--concurrency", type=int, default=10)
    parser.add_argument("--trip", default="line_hay.01", help="A trip id of the current pack.")
    args = parser.parse_args(argv)
    base = args.base.rstrip("/")
    url = urlsplit(base)
    if url.scheme != "https" and not (url.scheme == "http" and url.hostname in LOCAL_HOSTS):
        parser.error("--base must be https:// (plain http only for a local stack)")
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        results = list(
            pool.map(lambda _: one_player(base, args.batches, args.trip), range(args.players))
        )
    return 0 if report(results) else 1


if __name__ == "__main__":
    sys.exit(main())
