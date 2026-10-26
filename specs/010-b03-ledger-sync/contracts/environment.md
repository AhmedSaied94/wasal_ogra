# Contract: Environment

New settings, all read in `config/env.py` (`env.economy()`), validated at startup, and listed in
`backend/.env.example`. None is a secret, so no placeholder refusal applies; a value outside its
range stops the process at startup in every environment (like B02's rates). Integers only: a
percentage is an integer percent.

## Economy and fuel

| Variable | Default | Range | Meaning |
| --- | --- | --- | --- |
| `ECONOMY_FUEL_MAX` | `5` | 1–20 | the tank. Equals `fuel_max` in `tunables.json` (checked in CI) |
| `ECONOMY_FUEL_MAX_SUBSCRIBER` | `7` | ≥ `ECONOMY_FUEL_MAX`, ≤ 20 | the subscriber's tank (`fuel_max_subscriber`) |
| `ECONOMY_FUEL_REGEN_MINUTES` | `20` | 1–240 | minutes per liter (`fuel_regen_minutes`) |
| `ECONOMY_FUEL_REFILL_DAILY_CAP` | `3` | 0–50 | `fuel_refill` ads a game day (`ads_fuel_refill_daily_cap`) |
| `ECONOMY_FUEL_OVERDRAFT_PER_DAY` | `2` | 0–20 | overdrafts a game day that are accepted; the next is `cap_reached` |
| `ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP` | `1` | 0–10 | glossary §3.4 |
| `ECONOMY_NAME_MIN_LENGTH` / `ECONOMY_NAME_MAX_LENGTH` | `2` / `20` | 1–32, max ≥ min | display name length (`Player.display_name` holds 32) |

## Sync

| Variable | Default | Range | Meaning |
| --- | --- | --- | --- |
| `SYNC_GAME_TIMEZONE` | `Africa/Cairo` | a valid IANA zone | the game day (R3) |
| `SYNC_OP_RETENTION_DAYS` | `180` | 30–730 | how long `ProcessedOp` is kept, and the age at which an id is `op_expired` |
| `SYNC_CONTENT_MAX_AGE_DAYS` | `45` | 1–365 | the content version support window (R2) |
| `SYNC_MIN_DURATION_PERCENT` | `85` | 1–100 | hard lower bound of a finished trip's duration |
| `SYNC_FAST_RUN_PERCENT` | `95` | 1–100 | below this a 3-star run is flagged `fast_three_star`. Must be ≥ the hard bound |
| `SYNC_TRIPS_PER_DAY_FLAG` | `400` | 10–5000 | trip starts a game day that raise `trip_rate` |
| `SYNC_CLOCK_CLAMP_FLAG_MINUTES` | `10` | 1–1440 | a clamp this large raises `clock_clamped` |
| `SYNC_SESSION_GAP_MINUTES` | `30` | 1–1440 | idle time that starts a new session |
| `SYNC_COMEBACK_AWAY_DAYS` | `7` | 1–365 | a gap this long offers the comeback gift |
| `SYNC_COMEBACK_COOLDOWN_DAYS` | `30` | 0–365 | the least time between comeback gifts |
| `THROTTLE_SYNC_RATE` | `60/min` | the rate pattern | `POST /v1/sync` per player |
| `CLIENT_MIN_VERSION` / `CLIENT_LATEST_VERSION` | `1.0.0` / `1.0.0` | `MAJOR.MINOR.PATCH`, min ≤ latest | bootstrap's `client` block until B10 |

## Content

| Variable | Default | Range | Meaning |
| --- | --- | --- | --- |
| `CONTENT_INDEX_KEEP` | `10` | 5–50 | published versions whose trip, price and rules rows are kept (B04 kept 5) |

## Checks

- `ECONOMY_FUEL_MAX_SUBSCRIBER ≥ ECONOMY_FUEL_MAX`, `ECONOMY_NAME_MAX_LENGTH ≥ ECONOMY_NAME_MIN_LENGTH`,
  `SYNC_FAST_RUN_PERCENT ≥ SYNC_MIN_DURATION_PERCENT`,
  `CLIENT_MIN_VERSION ≤ CLIENT_LATEST_VERSION`, the zone name resolves, and every integer parses.
  Failures stop the process with the variable's name, never its value being a secret.
- `apps/economy/tests/test_tunables_parity.py` compares the four defaults that exist in
  `apps/mobile/assets/config/tunables.json` (`ECONOMY_FUEL_MAX`, `ECONOMY_FUEL_MAX_SUBSCRIBER`,
  `ECONOMY_FUEL_REGEN_MINUTES`, `ECONOMY_FUEL_REFILL_DAILY_CAP`) with those values and fails CI on a
  difference. Setting a different value in a host's env file is allowed (and is how B10 will start),
  but then the app's bundled value is the one to change next.
- `.env.example` lists every variable with its default and a one-line comment. Dev and test use the
  defaults.

## Where each is read

Settings are read from `django.conf.settings` by `economy/services/settings.py`, which returns a
frozen dataclass per request or batch, so a test can override one value with `settings` and a
deploy changes it with a restart.
