"""The shared fuel cases (fixtures/economy/fuel.json, contracts/fuel.md "Shared fixtures", SC-005).

Every case replays through `economy.services.fuel`; the `server` cases also through the effective
time clamp and the per game day counts. The app replays the `both` cases through M05's functions
(apps/mobile/test/core/economy/fuel_fixtures_test.dart).
"""

from __future__ import annotations

import json
from collections import Counter
from datetime import date, datetime
from typing import Any

import pytest
from django.conf import settings

from apps.economy.services import fuel
from apps.economy.services.gameday import game_date
from apps.economy.services.timeline import effective, from_ms, to_ms

FIXTURES = settings.BASE_DIR.parent / "fixtures" / "economy" / "fuel.json"
CASES: list[dict[str, Any]] = json.loads(FIXTURES.read_text())["cases"]


def ms(stamp: str | None) -> int | None:
    return None if stamp is None else to_ms(datetime.fromisoformat(stamp))


def stamp(value: int | None) -> str | None:
    return None if value is None else from_ms(value).strftime("%Y-%m-%dT%H:%M:%SZ")


def replay(case: dict[str, Any]) -> list[dict[str, Any]]:
    server = case["scope"] == "server"
    config = case["settings"]
    max_liters = config["max"]
    regen = fuel.regen_ms_of(config["regen_minutes"])
    initial = case["initial"]
    s = fuel.FuelState(
        initial["liters"], ms(initial["counted_from"]) or 0, ms(initial["unlimited_until"])
    )
    timeline = datetime.fromisoformat(case["timeline_at"]) if server else None
    now = datetime.fromisoformat(case["server_now"]) if server else None
    counts: Counter[tuple[date, str]] = Counter()
    results = []
    for step in case["steps"]:
        t_at = datetime.fromisoformat(step["t"])
        if server:
            assert timeline is not None
            assert now is not None
            t_at = effective(t_at, timeline, now)
        t = to_ms(t_at)
        day = game_date(t_at)
        accepted, reason, overdraft = True, None, False
        shown = s
        op = step["op"]
        if op == "trip_start":
            start = fuel.start(
                s,
                t,
                mode=step["mode"],
                max_liters=max_liters,
                regen_ms=regen,
                overdrafts_today=counts[(day, "overdraft")],
                overdraft_cap=config.get("overdraft_per_day", 0),
            )
            accepted, reason, overdraft = start.reason is None, start.reason, start.overdraft
            if accepted:
                s = shown = start.state
                if overdraft:
                    counts[(day, "overdraft")] += 1
        elif op in ("refill", "ad_refill"):
            filled = fuel.fill_to_max(
                fuel.regenerate(s, t, max_liters=max_liters, regen_ms=regen),
                t,
                max_liters=max_liters,
            )
            if filled is None:
                accepted, reason = False, "tank_full"
            elif op == "ad_refill" and counts[(day, "refill")] >= config["refill_daily_cap"]:
                accepted, reason = False, "cap_reached"
            else:
                s = shown = filled
                if op == "ad_refill":
                    counts[(day, "refill")] += 1
        elif op == "unlimited_1h":
            s = shown = fuel.extend_unlimited(
                fuel.regenerate(s, t, max_liters=max_liters, regen_ms=regen), t
            )
        elif op == "set_max":
            max_liters = step["max"]
        elif op == "read":
            shown = fuel.regenerate(s, t, max_liters=max_liters, regen_ms=regen)
        else:  # pragma: no cover - a fixture typo
            raise AssertionError(f"unknown step {op}")
        if server and accepted:
            timeline = t_at
        result: dict[str, Any] = {
            "liters": shown.liters,
            "counted_from": stamp(shown.counted_from_ms),
            "unlimited_until": stamp(shown.unlimited_until_ms),
            "accepted": accepted,
        }
        if reason is not None:
            result["reason"] = reason
        if overdraft:
            result["overdraft"] = True
        if server:
            result["effective_t"] = stamp(t)
        results.append(result)
    return results


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
def test_the_case_replays_to_its_expected_states(case: dict[str, Any]) -> None:
    assert replay(case) == case["expected"]


def test_the_cases_cover_both_scopes_and_every_step() -> None:
    assert CASES[0]["name"] == "start from a full tank counts from the start"
    assert {c["scope"] for c in CASES} == {"both", "server"}
    steps = {step["op"] for case in CASES for step in case["steps"]}
    assert steps == {"trip_start", "refill", "ad_refill", "unlimited_1h", "set_max", "read"}
    # The app replays only M05's rules: no server step in a "both" case.
    for case in CASES:
        if case["scope"] == "both":
            assert {s["op"] for s in case["steps"]} <= {
                "trip_start",
                "refill",
                "unlimited_1h",
                "set_max",
                "read",
            }
            assert "server_now" not in case
            assert all(len(e) == 4 + ("reason" in e) for e in case["expected"])
