# Parity fixtures

Each file here pins one trip's exact outcome. The Dart engine (`packages/trip_engine`) must
reproduce every one today, and the Python mirror (`tools/solver`, B05) must reproduce every one
before it merges (constitution III).

## Form

A fixture has exactly five keys, pretty-printed with a two-space indent and keys sorted:

| Key | Holds |
| --- | --- |
| `definition` | A `TripDefinition` that passes `content/schemas/trip.schema.json` on its own. |
| `seed` | The PRNG seed, given even when it equals `definition.seed`. |
| `params` | Every `TripParams` field: the bundled defaults for the trip's line, with at most the one being tested changed. |
| `command_log` | The accepted commands, as `[t_ms, "Name", ...args]`. |
| `expected_result` | The engine's `TripResult`, written by the tool. |

`expected_result` is never typed by hand. The full formats are in
`specs/004-m01-trip-engine/contracts/replay-and-fixtures.md`.

## Names

`<area>__<case>.json`, for example `archetype__sleeper_missed_stop.json`.

| Area | Pins |
| --- | --- |
| `core` | The base rules: chain hops, empty-seat skips, exact, short, over and not-owed change, getting off. |
| `archetype` | One or more per supported passenger type. |
| `event` | One or more per authored event. |
| `command` | One or more per command, including rejections that don't log. |
| `booster` | One per in-trip booster. |
| `ending` | 3, 2 and 1 stars, failed, revived and abandoned. |
| `sample` | Each sample-pack trip, played to 3 stars. |
| `stress` | `stress__longest_trip.json`: a full vehicle, the longest trip the params allow, 1,200 commands. |

## Work with them

In `packages/trip_engine`:

```bash
fvm dart run tool/fixtures.dart check                                  # all, exit 1 on a difference
fvm dart run tool/fixtures.dart show ../../fixtures/parity/<file>.json  # the event sequence
fvm dart run tool/fixtures.dart update ../../fixtures/parity/<file>.json
```

To add one: write `definition`, `seed`, `params` and `command_log`, run `update`, read the `show`
output, and add the rule it pins to `test/fixtures/fixture_expectations_test.dart`.

## Rules

- Every engine rule, scoring, default-param or PRNG change updates the fixtures it affects in the
  same PR (constitution III). A change that shouldn't affect outcomes must leave them unchanged.
- An `update` is reviewed like code: every changed number must be explained by the change.
