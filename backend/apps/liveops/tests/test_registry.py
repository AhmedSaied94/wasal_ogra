"""The registry is the contract (B10 contracts/settings.md, research R2, R9)."""

from __future__ import annotations

import json
from datetime import UTC, datetime

import pytest
from django.conf import settings

from apps.liveops import registry

TUNABLES = settings.BASE_DIR.parent / "apps" / "mobile" / "assets" / "config" / "tunables.json"

BOTH = {"fuel_max", "fuel_max_subscriber", "fuel_regen_minutes", "ads_fuel_refill_daily_cap"}

SERVER_ONLY = {
    "fuel_overdraft_per_day": 2,
    "traffic_jam_ads_per_trip": 1,
    "name_min_length": 2,
    "name_max_length": 20,
    "content_max_age_days": 45,
    "min_duration_percent": 85,
    "fast_run_percent": 95,
    "trips_per_day_flag": 400,
    "clock_clamp_flag_minutes": 10,
    "session_gap_minutes": 30,
    "comeback_away_days": 7,
    "comeback_cooldown_days": 30,
}

VERSIONS = {
    "min_client_version_android": "1.0.0",
    "latest_client_version_android": "1.0.0",
    "min_client_version_ios": "1.0.0",
    "latest_client_version_ios": "1.0.0",
}


@pytest.fixture(scope="module")
def tunables() -> dict[str, object]:
    data: dict[str, object] = json.loads(TUNABLES.read_text(encoding="utf-8"))
    return data


def test_every_phone_key_is_in_the_registry(tunables: dict[str, object]) -> None:
    for key, default in tunables.items():
        spec = registry.get(key)
        assert spec.applied_by in (registry.PHONE, registry.BOTH)
        assert spec.default == default


def test_every_phone_facing_key_is_in_the_file(tunables: dict[str, object]) -> None:
    phone_facing = {
        spec.key
        for spec in registry.SPECS.values()
        if spec.applied_by in (registry.PHONE, registry.BOTH)
    }
    assert phone_facing == set(tunables)


def test_exactly_four_keys_are_applied_by_both() -> None:
    assert {
        spec.key for spec in registry.SPECS.values() if spec.applied_by == registry.BOTH
    } == BOTH


def test_the_server_only_keys_and_their_defaults() -> None:
    for key, default in SERVER_ONLY.items():
        spec = registry.get(key)
        assert spec.applied_by == registry.SERVER
        assert spec.default == default
    assert {
        spec.key for spec in registry.SPECS.values() if spec.applied_by == registry.SERVER
    } == set(SERVER_ONLY) | set(VERSIONS) | {"maintenance_enabled", "maintenance_until"}


def test_the_version_and_maintenance_keys() -> None:
    for key, default in VERSIONS.items():
        assert registry.get(key).kind == registry.VERSION
        assert registry.get(key).default == default
        assert registry.get(key).applied_by == registry.SERVER
    assert registry.get("maintenance_enabled").kind == registry.BOOL
    assert registry.get("maintenance_enabled").default is False
    assert registry.get("maintenance_until").kind == registry.DATETIME
    assert registry.get("maintenance_until").default is None


def test_every_default_passes_its_own_kind_and_range() -> None:
    for spec in registry.SPECS.values():
        assert registry.validate(spec, spec.default) == spec.default


@pytest.mark.parametrize("raw", [1001, 1025, 1999])
def test_piaster_settings_refuse_a_value_that_is_not_a_multiple_of_50(raw: int) -> None:
    for key in ("trip_break_min_piasters", "trip_tip_piasters_regular_customer"):
        with pytest.raises(ValueError, match="multiple of 50"):
            registry.validate(registry.get(key), raw)


@pytest.mark.parametrize("key", [f"trip_hints_mode_{line}" for line in registry.LINE_IDS])
def test_hint_modes_are_a_closed_choice(key: str) -> None:
    assert registry.get(key).choices == ("off", "first_time", "always")
    with pytest.raises(ValueError, match="must be one of"):
        registry.validate(registry.get(key), "sometimes")


def test_the_pre_trip_card_mode_choice() -> None:
    spec = registry.get("pre_trip_card_mode")
    assert spec.choices == ("always", "new_only")
    with pytest.raises(ValueError, match="must be one of"):
        registry.validate(spec, "often")


@pytest.mark.parametrize("raw", ["1.0", "1.0.0.0", "one.two.three", "1.0.0+1", ""])
def test_a_version_key_accepts_only_major_minor_patch(raw: str) -> None:
    with pytest.raises(ValueError, match=r"MAJOR\.MINOR\.PATCH"):
        registry.validate(registry.get("min_client_version_android"), raw)


@pytest.mark.parametrize(
    ("values", "text"),
    [
        (
            {"fuel_max": 5, "fuel_max_subscriber": 3},
            "The subscriber's tank can't be smaller than the normal tank.",
        ),
        (
            {"min_duration_percent": 90, "fast_run_percent": 80},
            "The fast-run flag must be at or above the minimum duration.",
        ),
        (
            {"name_min_length": 10, "name_max_length": 8},
            "The longest name can't be shorter than the shortest.",
        ),
        (
            {"min_client_version_android": "1.3.0", "latest_client_version_android": "1.2.0"},
            "The minimum version can't be above the latest.",
        ),
        (
            {"min_client_version_ios": "1.3.0", "latest_client_version_ios": "1.2.0"},
            "The minimum version can't be above the latest.",
        ),
        (
            {"maintenance_enabled": False, "maintenance_until": datetime(2030, 1, 1, tzinfo=UTC)},
            "Set an end time in the future, or leave it empty.",
        ),
        (
            {"maintenance_enabled": True, "maintenance_until": datetime(2020, 1, 1, tzinfo=UTC)},
            "Set an end time in the future, or leave it empty.",
        ),
    ],
)
def test_each_rule_refuses_with_its_exact_text(values: dict[str, object], text: str) -> None:
    candidate = registry.defaults()
    candidate.update(values)
    with pytest.raises(registry.RuleBroken) as raised:
        registry.check_rules(candidate)
    assert str(raised.value) == text


def test_the_rules_accept_the_defaults_and_a_valid_end_time() -> None:
    registry.check_rules(registry.defaults())
    candidate = registry.defaults()
    candidate.update(
        {"maintenance_enabled": True, "maintenance_until": datetime(2999, 1, 1, tzinfo=UTC)}
    )
    registry.check_rules(candidate)


def test_an_unknown_key_raises_key_error() -> None:
    with pytest.raises(KeyError):
        registry.get("fuel_maxx")
