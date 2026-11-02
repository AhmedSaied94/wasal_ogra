# Contract: The Live Settings Registry

`apps/liveops/registry.py` declares each setting (research R2). This table is the contract: the
registry, the seed migration and `tunables.json` must agree with it, and the parity test (R9)
checks the phone-facing part.

`applied_by`: **phone** (the server keeps a copy and applies nothing), **server** (no Remote Config
key; the phone never reads it), **both** (Remote Config edits the phone's copy; the drift check
alerts on a difference, R8).

## Phone-facing (every key in `apps/mobile/assets/config/tunables.json`)

Defaults are the file's. Ranges are the server's sanity bounds against typos; the phone accepts any
integer of the right type.

| Keys | Kind | Range | `applied_by` |
| --- | --- | --- | --- |
| `trip_hop_ms_<line_id>` (5) | int | 200–10000 | phone |
| `trip_bubble_min_ms_<line_id>` (5) | int | 500–20000 | phone |
| `trip_hints_mode_<line_id>` (5) | choice | `off`, `first_time`, `always` | phone |
| `trip_undo_window_ms`, `trip_station_warning_ms`, `trip_group_redirect_hop_ms`, `trip_wake_ms`, `trip_sleeper_awake_ms`, `trip_headphones_attentive_ms`, `trip_patience_ms`, `trip_bump_collect_ms`, `trip_break_delay_ms` | int | 0–120000 | phone |
| `trip_hop_pct_hajja`, `trip_hop_pct_chatty_row`, `trip_patience_pct_hurry`, `trip_patience_drain_pct_traffic` | int | 1–1000 | phone |
| `trip_break_min_piasters`, `trip_tip_piasters_regular_customer` | int, multiple of 50 | 0–100000 | phone |
| `rep_fight`, `rep_false_accusation`, `rep_missed_stop`, `rep_liar_caught`, `rep_exact_change`, `rep_revive_to`, `rep_short_change`, `rep_impatient`, `rep_change_request_declined` | int | 0–100 | phone |
| `booster_ledger_peek_ms` | int | 1000–60000 | phone |
| `booster_traffic_jam_ms` | int | 1000–60000 | phone |
| `booster_traffic_jam_max_per_trip` | int | 0–5 | phone |
| `fuel_max` | int | 1–20 | **both** |
| `fuel_max_subscriber` | int | 1–20 | **both** |
| `fuel_regen_minutes` | int | 1–240 | **both** |
| `ads_fuel_refill_daily_cap` | int | 0–50 | **both** |
| `ads_interstitial_every_n_trips` | int | 1–50 | phone |
| `ads_interstitial_grace_trips` | int | 0–100 | phone |
| `pre_trip_card_mode` | choice | `always`, `new_only` | phone |
| `notif_daily_max` | int | 0–10 | phone |

## Server-only (formerly env settings, research R4)

| Key | Was | Default | Range |
| --- | --- | --- | --- |
| `fuel_overdraft_per_day` | `ECONOMY_FUEL_OVERDRAFT_PER_DAY` | 2 | 0–20 |
| `traffic_jam_ads_per_trip` | `ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP` | 1 | 0–10 |
| `name_min_length` | `ECONOMY_NAME_MIN_LENGTH` | 2 | 1–32 |
| `name_max_length` | `ECONOMY_NAME_MAX_LENGTH` | 20 | 1–32 |
| `content_max_age_days` | `SYNC_CONTENT_MAX_AGE_DAYS` | 45 | 1–365 |
| `min_duration_percent` | `SYNC_MIN_DURATION_PERCENT` | 85 | 1–100 |
| `fast_run_percent` | `SYNC_FAST_RUN_PERCENT` | 95 | 1–100 |
| `trips_per_day_flag` | `SYNC_TRIPS_PER_DAY_FLAG` | 400 | 10–5000 |
| `clock_clamp_flag_minutes` | `SYNC_CLOCK_CLAMP_FLAG_MINUTES` | 10 | 1–1440 |
| `session_gap_minutes` | `SYNC_SESSION_GAP_MINUTES` | 30 | 1–1440 |
| `comeback_away_days` | `SYNC_COMEBACK_AWAY_DAYS` | 7 | 1–365 |
| `comeback_cooldown_days` | `SYNC_COMEBACK_COOLDOWN_DAYS` | 30 | 0–365 |
| `min_client_version_android` | `CLIENT_MIN_VERSION` | `1.0.0` | `MAJOR.MINOR.PATCH` |
| `latest_client_version_android` | `CLIENT_LATEST_VERSION` | `1.0.0` | `MAJOR.MINOR.PATCH` |
| `min_client_version_ios` | `CLIENT_MIN_VERSION` | `1.0.0` | `MAJOR.MINOR.PATCH` |
| `latest_client_version_ios` | `CLIENT_LATEST_VERSION` | `1.0.0` | `MAJOR.MINOR.PATCH` |
| `maintenance_enabled` | new | `false` | bool |
| `maintenance_until` | new | null | UTC datetime or null |

`ECONOMY_FUEL_MAX`, `ECONOMY_FUEL_MAX_SUBSCRIBER`, `ECONOMY_FUEL_REGEN_MINUTES` and
`ECONOMY_FUEL_REFILL_DAILY_CAP` become the four **both** keys above; the env import (R5) maps them
too. The version pair imports into both platforms.

## Rules checked on every save

A save that breaks one is refused with the rule's text; the old value stays (FR-004).

| Rule | Text |
| --- | --- |
| `fuel_max_subscriber ≥ fuel_max` | "The subscriber's tank can't be smaller than the normal tank." |
| `fast_run_percent ≥ min_duration_percent` | "The fast-run flag must be at or above the minimum duration." |
| `name_max_length ≥ name_min_length` | "The longest name can't be shorter than the shortest." |
| `min_client_version_<p> ≤ latest_client_version_<p>` | "The minimum version can't be above the latest." |
| `maintenance_until` only with `maintenance_enabled`, and not in the past when set | "Set an end time in the future, or leave it empty." |

A rule is checked against the snapshot with the new value in it, so saving two related keys works
in either order as long as each step is valid; the admin's "edit several" form saves them in one
transaction and checks the rules once.

## Reading

- `apps.liveops.settings.current() -> Snapshot`; `snapshot["fuel_max"]` returns the typed value.
  A key the registry lacks raises `KeyError` (a typo fails in tests, not in production).
- Refreshed by age, at most every `LIVEOPS_REFRESH_SECONDS` (30) per process (R3).
- Tests use the `live_settings` fixture: `live_settings(fuel_overdraft_per_day=1)`.
