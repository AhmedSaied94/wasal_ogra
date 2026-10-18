# Contract: Tunables and Their Bundled Defaults

Constitution VIII; spec FR-031 – FR-035. M03 ships the defaults and the read interface. Remote Config
(M15) and the server's `liveops.LiveSetting` (B10) come later. They must use the same keys, types and
defaults.

## Files

| File | Role |
| --- | --- |
| `apps/mobile/assets/config/tunables.json` | **Only** place that holds default values. A flat JSON object of key → value, bundled in every variant. Its format is the one Firebase Remote Config `setDefaults` accepts, so M15 can pass it through unchanged. |
| `apps/mobile/assets/config/tunables.dev.json` | Optional overrides, bundled only in the `dev` variant (flavor-conditional asset). Ships as `{}`. |
| `apps/mobile/lib/core/config/tunable.dart` | Typed key registry: key name and type only, **no values**. |

## Read interface

```dart
abstract interface class ConfigSource {
  T read<T extends Object>(Tunable<T> key); // never throws for a registered key
}
```

- **Sources, in priority order:** valid override → (M15: remote) → bundled default.
- **Bad overrides:** a missing key, or a value that fails `Tunable.parse`, falls through to the next
  source (FR-035).
- **Startup:** the bundled defaults load once at startup, before الموقف is shown. After that, reads are
  synchronous.
- **Per-line keys** come from `Tunable.tripHopMs(LineId)`, `Tunable.tripBubbleMinMs(LineId)` and
  `Tunable.tripHintsEnabled(LineId)`. Each expands to `<prefix>_<line_id>`.
- **Who reads:** only the Application layer. The engine receives tunables as explicit `params`
  (constitution VIII); it never reads `ConfigSource`.

## Keys and defaults (mobile §14.3; per-line values from ux-spec «الصعوبة والمساعدة حسب الخط»)

| Key | Type | Default |
| --- | --- | --- |
| `trip_hop_ms_line_hay` | int | 1300 |
| `trip_hop_ms_line_gamaa` | int | 1100 |
| `trip_hop_ms_line_souq` | int | 900 |
| `trip_hop_ms_line_masyaf` | int | 900 |
| `trip_hop_ms_line_safar` | int | 900 |
| `trip_bubble_min_ms_line_hay` | int | 4500 |
| `trip_bubble_min_ms_line_gamaa` | int | 4000 |
| `trip_bubble_min_ms_line_souq` | int | 3500 |
| `trip_bubble_min_ms_line_masyaf` | int | 3500 |
| `trip_bubble_min_ms_line_safar` | int | 3500 |
| `trip_hints_enabled_line_hay` | bool | true |
| `trip_hints_enabled_line_gamaa` | bool | false (see open item) |
| `trip_hints_enabled_line_souq` | bool | false |
| `trip_hints_enabled_line_masyaf` | bool | false |
| `trip_hints_enabled_line_safar` | bool | false |
| `trip_undo_window_ms` | int | 1000 |
| `rep_fight` | int | 30 |
| `rep_false_accusation` | int | 20 |
| `rep_missed_stop` | int | 15 |
| `rep_liar_caught` | int | 10 |
| `rep_exact_change` | int | 3 |
| `rep_revive_to` | int | 40 |
| `fuel_max` | int | 5 |
| `fuel_max_subscriber` | int | 7 |
| `fuel_regen_minutes` | int | 20 |
| `ads_interstitial_every_n_trips` | int | 3 |
| `ads_interstitial_grace_trips` | int | 10 |
| `ads_fuel_refill_daily_cap` | int | 3 |
| `pre_trip_card_mode` | enum `always` · `new_only` | `always` |
| `notif_daily_max` | int | 2 |

30 keys in total. The defaults test fails if the registry and `tunables.json` disagree on any key or
type, or if a value differs from this table.

**Open item, handed to M01/M02 (not blocking M03).** Mobile §14.3 says hints are "true only for
`line_hay`". ux-spec gives `line_gamaa` a third mode: hints only the first time each new passenger type
appears. A boolean can't express that. M03 ships `false` per §14.3. M01/M02 decide whether the key
becomes an enum (`off` · `first_time` · `on`). If it does, they update mobile §14.3 and the backend
settings in the same change (constitution VIII).
