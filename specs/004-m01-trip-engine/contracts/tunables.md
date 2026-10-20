# Contract: Tunables for the Trip Engine

Spec FR-067 to FR-069, research R12 and R19. This extends M03's
`specs/001-m03-app-shell/contracts/tunables.md`. The read interface (`ConfigSource`, the source
priority, bad overrides falling through) is unchanged.

## Where values live

| Place | Role |
| --- | --- |
| `apps/mobile/assets/config/tunables.json` | The only place defaults are written (constitution VIII). |
| `apps/mobile/lib/core/config/tunable.dart` | Typed registry: keys and types, no values. |
| `docs/architecture-mobile.md` §14.3 | The documented key table, updated in the same change. |
| `packages/trip_engine` `TripParams` | Receives the values as explicit params. No defaults in code. |
| `backend` `liveops.LiveSetting` | Arrives with B10, which copies every key (R19). |

## Keys added by M01 (20)

All are `int`.

| Key | Default | Rule (spec) |
| --- | --- | --- |
| `trip_station_warning_ms` | 8000 | FR-012, FR-013 |
| `trip_hop_pct_hajja` | 200 | FR-023 |
| `trip_hop_pct_chatty_row` | 150 | FR-023 |
| `trip_group_redirect_hop_ms` | 600 | FR-035 |
| `trip_wake_ms` | 1000 | FR-040 |
| `trip_sleeper_awake_ms` | 15000 | FR-040 |
| `trip_headphones_attentive_ms` | 15000 | FR-040 |
| `trip_patience_ms` | 20000 | FR-042 |
| `trip_patience_pct_hurry` | 50 | FR-042 |
| `trip_patience_drain_pct_traffic` | 150 | FR-042 |
| `trip_bump_collect_ms` | 3000 | FR-045 |
| `trip_break_min_piasters` | 1000 | FR-051 |
| `trip_break_delay_ms` | 1500 | FR-051 |
| `trip_tip_piasters_regular_customer` | 200 | FR-040 |
| `booster_ledger_peek_ms` | 10000 | FR-052 |
| `booster_traffic_jam_ms` | 10000 | FR-052 |
| `booster_traffic_jam_max_per_trip` | 3 | FR-052 |
| `rep_short_change` | 5 | FR-033 |
| `rep_impatient` | 5 | FR-042 |
| `rep_change_request_declined` | 5 | FR-045 |

Two keys have hard upper bounds, checked by `TripParams` validation (data-model.md):
`booster_traffic_jam_ms` at most 60000, and `booster_traffic_jam_max_per_trip` at most 5. Remote
Config may tune them within the bounds; a value outside them makes the engine refuse the trip.

## The hints key changes type (FR-069)

| Before (M03) | After (M01) |
| --- | --- |
| `trip_hints_enabled_<line_id>`: `bool` | `trip_hints_mode_<line_id>`: enum `off` · `first_time` · `always` |
| `line_hay` `true`, all others `false` | `line_hay` `always`, `line_gamaa` `first_time`, `line_souq`, `line_masyaf` and `line_safar` `off` |

In the registry, `Tunable.tripHintsEnabled(LineId)` becomes `Tunable.tripHintsMode(LineId)`, of type
`Tunable<TripHintsMode>`. Its enum has a `wire` string, like `PreTripCardMode`. The engine never
reads it. M02 uses it, and remembers on the device which passenger types the player has already
seen for `first_time`.

After M01 the registry holds **50 keys**: M03's 30, with five renamed, plus the 20 above. The
defaults test asserts the full table, including the type of each value.

## TripParams wire form

A flat JSON object with one integer per engine rule number (data-model.md "TripParams"). Its keys
are the tunable names, except that the per-line key is written without its suffix:

| Tunable | `TripParams` key |
| --- | --- |
| `trip_hop_ms_<line_id>` | `trip_hop_ms` |
| every other key above, plus `trip_undo_window_ms` and the six M03 `rep_*` keys | the same name |

`trip_bubble_min_ms_<line_id>` and `trip_hints_mode_<line_id>` are presentation, so they are not in
`TripParams` and not in the replay tuple.

`TripParams.fromTunables(values, line)`:

- reads every key from a flat map such as the `tunables.json` object or M02's resolved values;
- picks `trip_hop_ms_<line_id>` for the line;
- throws `FormatException` naming the first missing or non-integer key.

## Checks

| Test | Asserts |
| --- | --- |
| `apps/mobile/test/core/config/tunables_defaults_test.dart` | `tunables.json` holds exactly the 50 keys with these values and types, and the per-line rows cover every line. |
| `apps/mobile/test/core/config/config_source_test.dart` | `tripHintsMode` parses the three wire values and rejects anything else, which falls through to the default. |
| `packages/trip_engine/test/params/params_tunables_test.dart` | Every `TripParams` key resolves from `apps/mobile/assets/config/tunables.json` for every line, and `toJson` and `fromJson` round-trip. |
