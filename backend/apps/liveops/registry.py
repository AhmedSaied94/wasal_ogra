"""The live settings registry: every setting's type, range, default and who applies it (B10
research R2, contracts/settings.md).

Only values are live-ops data; the table below is code review material. Cross-setting rules live
here too, so the admin, the command and the import all refuse the same values with the same text.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

INT = "int"
CHOICE = "choice"
VERSION = "version"
BOOL = "bool"
DATETIME = "datetime"

PHONE = "phone"
SERVER = "server"
BOTH = "both"

VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
# The five line ids of glossary §3.6. Their keys are generated, not typed twice.
LINE_IDS = ("line_hay", "line_gamaa", "line_souq", "line_masyaf", "line_safar")


class RuleBroken(ValueError):
    """A save that breaks one of the cross-setting rules (contracts/settings.md "Rules")."""


@dataclass(frozen=True)
class Spec:
    key: str
    kind: str
    default: Any
    applied_by: str
    meaning: str
    minimum: int | None = None
    maximum: int | None = None
    choices: tuple[str, ...] = ()
    multiple_of: int | None = None


@dataclass(frozen=True)
class Rule:
    keys: tuple[str, ...]
    text: str
    holds: Callable[[Mapping[str, Any]], bool]


def _int(
    key: str,
    default: int,
    minimum: int,
    maximum: int,
    *,
    applied_by: str = PHONE,
    meaning: str = "",
    multiple_of: int | None = None,
) -> Spec:
    return Spec(
        key,
        INT,
        default,
        applied_by,
        meaning or key.replace("_", " "),
        minimum=minimum,
        maximum=maximum,
        multiple_of=multiple_of,
    )


def _choice(key: str, default: str, choices: tuple[str, ...], *, meaning: str = "") -> Spec:
    return Spec(key, CHOICE, default, PHONE, meaning or key.replace("_", " "), choices=choices)


def _version(key: str) -> Spec:
    return Spec(
        key,
        VERSION,
        "1.0.0",
        SERVER,
        key.replace("_", " "),
    )


# -- the registry (contracts/settings.md) ----------------------------------------------------------

_SPECS: list[Spec] = []

# Phone-facing: every key in apps/mobile/assets/config/tunables.json, with the same default.
_SPECS += [
    _int(f"trip_hop_ms_{line}", default, 200, 10_000, meaning=f"Hop time on {line}")
    for line, default in zip(LINE_IDS, (1300, 1100, 900, 900, 900), strict=True)
]
_SPECS += [
    _int(f"trip_bubble_min_ms_{line}", default, 500, 20_000, meaning=f"Bubble time on {line}")
    for line, default in zip(LINE_IDS, (4500, 4000, 3500, 3500, 3500), strict=True)
]
_SPECS += [
    _choice(
        f"trip_hints_mode_{line}",
        default,
        ("off", "first_time", "always"),
        meaning=f"Hints on {line}",
    )
    for line, default in zip(LINE_IDS, ("always", "first_time", "off", "off", "off"), strict=True)
]
_SPECS += [
    _int("trip_undo_window_ms", 1000, 0, 120_000, meaning="Undo window during a trip"),
    _int("trip_station_warning_ms", 8000, 0, 120_000, meaning="Station warning lead time"),
    _int("trip_group_redirect_hop_ms", 600, 0, 120_000, meaning="Group redirect hop time"),
    _int("trip_wake_ms", 1000, 0, 120_000, meaning="Passenger wake time"),
    _int("trip_sleeper_awake_ms", 15_000, 0, 120_000, meaning="Sleeper awake window"),
    _int("trip_headphones_attentive_ms", 15_000, 0, 120_000, meaning="Headphones attentive time"),
    _int("trip_patience_ms", 20_000, 0, 120_000, meaning="Passenger patience"),
    _int("trip_bump_collect_ms", 3000, 0, 120_000, meaning="Bump collect time"),
    _int("trip_break_delay_ms", 1500, 0, 120_000, meaning="Break delay"),
    _int("trip_hop_pct_hajja", 200, 1, 1000, meaning="Hop time for Hajja"),
    _int("trip_hop_pct_chatty_row", 150, 1, 1000, meaning="Hop time for the chatty row"),
    _int("trip_patience_pct_hurry", 50, 1, 1000, meaning="Patience of a hurried passenger"),
    _int("trip_patience_drain_pct_traffic", 150, 1, 1000, meaning="Patience drain in traffic"),
    _int(
        "trip_break_min_piasters",
        1000,
        0,
        100_000,
        meaning="Minimum break in piasters",
        multiple_of=50,
    ),
    _int(
        "trip_tip_piasters_regular_customer",
        200,
        0,
        100_000,
        meaning="Regular customer tip in piasters",
        multiple_of=50,
    ),
    _int("rep_fight", 30, 0, 100, meaning="Reputation: fight"),
    _int("rep_false_accusation", 20, 0, 100, meaning="Reputation: false accusation"),
    _int("rep_missed_stop", 15, 0, 100, meaning="Reputation: missed stop"),
    _int("rep_liar_caught", 10, 0, 100, meaning="Reputation: liar caught"),
    _int("rep_exact_change", 3, 0, 100, meaning="Reputation: exact change"),
    _int("rep_revive_to", 40, 0, 100, meaning="Reputation: revive to"),
    _int("rep_short_change", 5, 0, 100, meaning="Reputation: short change"),
    _int("rep_impatient", 5, 0, 100, meaning="Reputation: impatient"),
    _int(
        "rep_change_request_declined",
        5,
        0,
        100,
        meaning="Reputation: change request declined",
    ),
    _int("booster_ledger_peek_ms", 10_000, 1000, 60_000, meaning="Ledger peek booster window"),
    _int("booster_traffic_jam_ms", 10_000, 1000, 60_000, meaning="Traffic jam booster window"),
    _int("booster_traffic_jam_max_per_trip", 3, 0, 5, meaning="Traffic jam boosters per trip"),
    _int("fuel_max", 5, 1, 20, applied_by=BOTH, meaning="Tank size"),
    _int("fuel_max_subscriber", 7, 1, 20, applied_by=BOTH, meaning="Tank size for subscribers"),
    _int("fuel_regen_minutes", 20, 1, 240, applied_by=BOTH, meaning="Minutes per litre"),
    _int(
        "ads_fuel_refill_daily_cap",
        3,
        0,
        50,
        applied_by=BOTH,
        meaning="Fuel refill ads per game day",
    ),
    _int(
        "ads_morning_piggy_daily_cap",
        1,
        0,
        10,
        applied_by=BOTH,
        meaning="Morning piggy ads per game day",
    ),
    _int("ads_interstitial_every_n_trips", 3, 1, 50, meaning="Interstitial every N trips"),
    _int("ads_interstitial_grace_trips", 10, 0, 100, meaning="Interstitials' grace trips"),
    _choice("pre_trip_card_mode", "always", ("always", "new_only"), meaning="Pre-trip card mode"),
    _int("notif_daily_max", 2, 0, 10, meaning="Notifications per day"),
]

# Server-only (formerly env settings, research R4): no Remote Config key (Complexity Tracking).
_SPECS += [
    _int(
        "fuel_overdraft_per_day",
        2,
        0,
        20,
        applied_by=SERVER,
        meaning="Empty-tank starts per game day",
    ),
    _int(
        "traffic_jam_ads_per_trip",
        1,
        0,
        10,
        applied_by=SERVER,
        meaning="Traffic jam ads per trip",
    ),
    _int("name_min_length", 2, 1, 32, applied_by=SERVER, meaning="Shortest display name"),
    _int("name_max_length", 20, 1, 32, applied_by=SERVER, meaning="Longest display name"),
    _int("content_max_age_days", 45, 1, 365, applied_by=SERVER, meaning="Oldest usable content"),
    _int(
        "min_duration_percent",
        85,
        1,
        100,
        applied_by=SERVER,
        meaning="Shortest believable trip",
    ),
    _int("fast_run_percent", 95, 1, 100, applied_by=SERVER, meaning="Fast-run flag threshold"),
    _int("trips_per_day_flag", 400, 10, 5000, applied_by=SERVER, meaning="Trips a day flag"),
    _int(
        "clock_clamp_flag_minutes",
        10,
        1,
        1440,
        applied_by=SERVER,
        meaning="Clock clamp flag threshold",
    ),
    _int("session_gap_minutes", 30, 1, 1440, applied_by=SERVER, meaning="Session gap"),
    _int("comeback_away_days", 7, 1, 365, applied_by=SERVER, meaning="Comeback after N days"),
    _int("comeback_cooldown_days", 30, 0, 365, applied_by=SERVER, meaning="Comeback cooldown"),
    # B07: what the morning piggy grants; the phone learns it from the reward (FR-019).
    _int(
        "ads_morning_piggy_jenehat",
        30,
        0,
        10_000,
        applied_by=SERVER,
        meaning="Morning piggy JENEHAT",
    ),
    _int("ads_morning_piggy_bonat", 2, 0, 100, applied_by=SERVER, meaning="Morning piggy BONAT"),
    _version("min_client_version_android"),
    _version("latest_client_version_android"),
    _version("min_client_version_ios"),
    _version("latest_client_version_ios"),
    Spec(
        "maintenance_enabled",
        BOOL,
        False,
        SERVER,
        "Writes are paused",
    ),
    Spec(
        "maintenance_until",
        DATETIME,
        None,
        SERVER,
        "When maintenance is expected to end",
    ),
]

SPECS: dict[str, Spec] = {spec.key: spec for spec in _SPECS}
if len(SPECS) != len(_SPECS):
    raise RuntimeError("the registry has duplicate keys")

# -- the rules (contracts/settings.md "Rules checked on every save") ------------------------------


def _subscriber_tank(candidate: Mapping[str, Any]) -> bool:
    return bool(candidate["fuel_max_subscriber"] >= candidate["fuel_max"])


def _fast_run(candidate: Mapping[str, Any]) -> bool:
    return bool(candidate["fast_run_percent"] >= candidate["min_duration_percent"])


def _names(candidate: Mapping[str, Any]) -> bool:
    return bool(candidate["name_max_length"] >= candidate["name_min_length"])


def _versions(platform: str) -> Callable[[Mapping[str, Any]], bool]:
    def holds(candidate: Mapping[str, Any]) -> bool:
        minimum = candidate[f"min_client_version_{platform}"]
        latest = candidate[f"latest_client_version_{platform}"]
        return bool(_version_tuple(minimum) <= _version_tuple(latest))

    return holds


def _morning_piggy(candidate: Mapping[str, Any]) -> bool:
    return bool(candidate["ads_morning_piggy_jenehat"] or candidate["ads_morning_piggy_bonat"])


def _maintenance(candidate: Mapping[str, Any]) -> bool:
    until = candidate["maintenance_until"]
    if until is None:
        return True
    return bool(candidate["maintenance_enabled"]) and bool(until > datetime.now(UTC))


RULES: tuple[Rule, ...] = (
    Rule(
        ("fuel_max", "fuel_max_subscriber"),
        "The subscriber's tank can't be smaller than the normal tank.",
        _subscriber_tank,
    ),
    Rule(
        ("min_duration_percent", "fast_run_percent"),
        "The fast-run flag must be at or above the minimum duration.",
        _fast_run,
    ),
    Rule(
        ("name_min_length", "name_max_length"),
        "The longest name can't be shorter than the shortest.",
        _names,
    ),
    Rule(
        ("min_client_version_android", "latest_client_version_android"),
        "The minimum version can't be above the latest.",
        _versions("android"),
    ),
    Rule(
        ("min_client_version_ios", "latest_client_version_ios"),
        "The minimum version can't be above the latest.",
        _versions("ios"),
    ),
    Rule(
        ("maintenance_enabled", "maintenance_until"),
        "Set an end time in the future, or leave it empty.",
        _maintenance,
    ),
    Rule(
        ("ads_morning_piggy_jenehat", "ads_morning_piggy_bonat"),
        "The morning piggy must give something.",
        _morning_piggy,
    ),
)

_RULE_KEYS: dict[str, frozenset[str]] = {
    key: frozenset(rule.keys) for rule in RULES for key in rule.keys
}

# -- retired environment variables, imported once on migrate (research R5) -------------------------

ENV_IMPORTS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("ECONOMY_FUEL_MAX", ("fuel_max",)),
    ("ECONOMY_FUEL_MAX_SUBSCRIBER", ("fuel_max_subscriber",)),
    ("ECONOMY_FUEL_REGEN_MINUTES", ("fuel_regen_minutes",)),
    ("ECONOMY_FUEL_REFILL_DAILY_CAP", ("ads_fuel_refill_daily_cap",)),
    ("ECONOMY_FUEL_OVERDRAFT_PER_DAY", ("fuel_overdraft_per_day",)),
    ("ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP", ("traffic_jam_ads_per_trip",)),
    ("ECONOMY_NAME_MIN_LENGTH", ("name_min_length",)),
    ("ECONOMY_NAME_MAX_LENGTH", ("name_max_length",)),
    ("SYNC_CONTENT_MAX_AGE_DAYS", ("content_max_age_days",)),
    ("SYNC_MIN_DURATION_PERCENT", ("min_duration_percent",)),
    ("SYNC_FAST_RUN_PERCENT", ("fast_run_percent",)),
    ("SYNC_TRIPS_PER_DAY_FLAG", ("trips_per_day_flag",)),
    ("SYNC_CLOCK_CLAMP_FLAG_MINUTES", ("clock_clamp_flag_minutes",)),
    ("SYNC_SESSION_GAP_MINUTES", ("session_gap_minutes",)),
    ("SYNC_COMEBACK_AWAY_DAYS", ("comeback_away_days",)),
    ("SYNC_COMEBACK_COOLDOWN_DAYS", ("comeback_cooldown_days",)),
    ("CLIENT_MIN_VERSION", ("min_client_version_android", "min_client_version_ios")),
    ("CLIENT_LATEST_VERSION", ("latest_client_version_android", "latest_client_version_ios")),
)
RETIRED_ENV_VARIABLES: tuple[str, ...] = tuple(name for name, _ in ENV_IMPORTS)
IMPORT_NOTE = "from env on migrate"

# -- reading, validating and checking --------------------------------------------------------------


def get(key: str) -> Spec:
    """The spec of `key`. A typo raises `KeyError` in tests, not in production."""
    return SPECS[key]


def validate(spec: Spec, raw: Any) -> Any:
    """The value as stored in `LiveSetting.value`, or `ValueError` with the contract's text."""
    if spec.kind == INT:
        if isinstance(raw, bool) or not isinstance(raw, int):
            raise ValueError(f"{spec.key} must be a whole number.")
        if spec.minimum is not None and raw < spec.minimum:
            raise ValueError(f"{spec.key} must be at least {spec.minimum}.")
        if spec.maximum is not None and raw > spec.maximum:
            raise ValueError(f"{spec.key} must be at most {spec.maximum}.")
        if spec.multiple_of is not None and raw % spec.multiple_of:
            raise ValueError(f"{spec.key} must be a multiple of {spec.multiple_of}.")
        return raw
    if spec.kind == CHOICE:
        if raw not in spec.choices:
            raise ValueError(f"{spec.key} must be one of {', '.join(spec.choices)}.")
        return raw
    if spec.kind == VERSION:
        if not isinstance(raw, str) or not VERSION_PATTERN.match(raw):
            raise ValueError(f"{spec.key} must be MAJOR.MINOR.PATCH.")
        return raw
    if spec.kind == BOOL:
        if not isinstance(raw, bool):
            raise ValueError(f"{spec.key} must be true or false.")
        return raw
    if spec.kind == DATETIME:
        if raw is None or raw == "":
            return None
        try:
            instant = raw if isinstance(raw, datetime) else datetime.fromisoformat(str(raw))
        except ValueError:
            raise ValueError(f"{spec.key} must be an ISO-8601 datetime.") from None
        if instant.tzinfo is None:
            raise ValueError(f"{spec.key} must name a time zone.")
        return _iso(instant)
    raise AssertionError(f"unknown kind {spec.kind}")


def typed(spec: Spec, stored: Any) -> Any:
    """The value code reads: a `datetime` for a datetime setting, the stored value otherwise."""
    if spec.kind == DATETIME:
        return None if stored in (None, "") else datetime.fromisoformat(stored)
    return stored


def defaults() -> dict[str, Any]:
    """Every key with its code default, typed."""
    return {spec.key: spec.default for spec in SPECS.values()}


def rule_keys(key: str) -> frozenset[str]:
    """The keys whose save shares a rule with `key` (itself included)."""
    return _RULE_KEYS.get(key, frozenset({key}))


def check_rules(
    candidate: Mapping[str, Any], keys: frozenset[str] | set[str] | None = None
) -> None:
    """Refuse the candidate snapshot with the rule's exact text (contracts/settings.md).

    With `keys`, only the rules that share a key with those settings are checked: every other
    rule already holds in the table, and the save doesn't touch it.
    """
    touched = None if keys is None else set(keys)
    for rule in RULES:
        if touched is not None and not touched.intersection(rule.keys):
            continue
        if not rule.holds(candidate):
            raise RuleBroken(rule.text)


def _version_tuple(value: str) -> tuple[int, int, int]:
    major, minor, patch = value.split(".")
    return int(major), int(minor), int(patch)


def _iso(instant: datetime) -> str:
    return instant.astimezone(UTC).isoformat().replace("+00:00", "Z")
