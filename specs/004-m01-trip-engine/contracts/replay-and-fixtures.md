# Contract: Command Log, Replay Record and Parity Fixtures

The wire formats shared by the engine, M02's saved trips, the sync payload (B03), the daily
challenge (B08) and the Python mirror (B05). Research R9 to R11 explains the choices.

## 1. Commands on the wire

A logged command is a JSON array: `[t_ms, "Name", ...args]`. `t_ms` is the clock when it applied, a
non-negative multiple of 33. The arguments are positional:

| Command | Wire | Example |
| --- | --- | --- |
| `PickFromTray` | `[t, "PickFromTray", denomination]` | `[330, "PickFromTray", 100]` |
| `ReturnHand` | `[t, "ReturnHand"]` | `[363, "ReturnHand"]` |
| `SendHand` | `[t, "SendHand", passenger_id]` | `[396, "SendHand", "p2"]` |
| `UndoLastSend` | `[t, "UndoLastSend"]` | |
| `Tap` | `[t, "Tap", passenger_id]` | |
| `ResolveClaim` | `[t, "ResolveClaim", passenger_id, insist]` | `[990, "ResolveClaim", "p4", true]` |
| `ResolveDispute` | `[t, "ResolveDispute", dispute_id, paid_passenger_id]` | `[1650, "ResolveDispute", 2, "p1"]` |
| `ResolveChangeRequest` | `[t, "ResolveChangeRequest", passenger_id, agree]` | |
| `RequestBreak` | `[t, "RequestBreak", denomination]` | |
| `CollectDropped` | `[t, "CollectDropped", token_id]` | |
| `UseBooster` | `[t, "UseBooster", booster_id]` | `[2013, "UseBooster", "wake_all"]` |
| `Revive` | `[t, "Revive"]` | |
| `Abandon` | `[t, "Abandon"]` | |

`dispute_id` is the authored event's index in `events`. `token_id` is the engine's token id, which
is deterministic.

## 2. The command log

- **What it holds.** A JSON array of logged commands: every accepted command, in the order applied.
  Rejected commands, pause and resume never appear.
- **Order.** `t_ms` never decreases along the log. Several commands may share a `t_ms`.
- **Size.** At most 1,201 entries: 1,200, plus a final `Abandon`, which the cap never refuses
  (rules.md §4). The longest entry is 45 bytes, for example
  `[1500000,"ResolveChangeRequest","p999",false]`: `t_ms` has at most 7 digits, because the longest
  trip is 1,500 s (data-model.md "TripParams"), and passenger ids at most 4 characters
  (`^p[0-9]{1,3}$`). With the commas, the
  canonical log is at most about 55 KB, under backend §16's 64 KB `command_log` limit.

## 3. The fingerprint (`command_log_hash`)

`command_log_hash = lowercase_hex(sha256(utf8(canonical_json(command_log))))`.

`canonical_json` is the canonical form shared by `content_models` (`canonicalJson`) and
`wassal_content` (`canonical_text`): no whitespace, object keys in UTF-16 code-unit order, integers
only. A log has no objects, so this amounts to `jsonEncode` with no spaces. The empty log `[]`
hashes to SHA-256 of the two bytes `[]`.

## 4. The replay record

M02 saves this record on every accepted command and every pause, and the engine rebuilds a killed
trip from it (research R10):

```json
{
  "definition": { "…": "the full TripDefinition, as in trip.schema.json" },
  "seed": 521288629,
  "params": { "trip_hop_ms": 1100, "…": "every TripParams field" },
  "command_log": [[330, "Tap", "p1"], [1287, "PickFromTray", 1000]],
  "t_ms": 1914
}
```

The rules:

- `t_ms` is a multiple of 33, and at least the last command's `t_ms`.
- **Rebuild:** start the trip; for each entry, `stepTo(entry.t_ms)` and then apply it, and every one
  must be accepted; then `stepTo(t_ms)`.
- **Refusal** (`RebuildRefused`): the definition is refused, `t_ms` goes down along the log, `t_ms`
  is before the last command, or an entry is rejected.

## 5. Parity fixtures

**Location and names.** One file per case, `fixtures/parity/<area>__<case>.json`. The areas:

| Area | Pins |
| --- | --- |
| `core` | The base rules: chain hops, empty-seat skips, exact, short, over and not-owed change, getting off. |
| `archetype` | One or more per supported archetype. |
| `event` | One or more per authored event. |
| `command` | One or more per command, including rejections that don't log. |
| `booster` | One per in-trip booster. |
| `ending` | 3, 2 and 1 stars, failed, revived and abandoned. |
| `sample` | Each sample-pack trip, played to 3 stars. |
| `stress` | `stress__longest_trip.json`: a full vehicle, the longest trip the bounds allow (1,500 s) and 1,200 commands (SC-004, SC-005). |

**Form.** Exactly these five keys (constitution III), pretty-printed with two-space indent and keys
sorted:

```json
{
  "command_log": [[33, "Tap", "p2"], [1089, "PickFromTray", 100]],
  "definition": { "…": "a TripDefinition that passes trip.schema.json on its own" },
  "expected_result": {
    "boosters_used": [],
    "caught_liars": 0,
    "command_log_hash": "…",
    "duration_ms": 60027,
    "earnings_jenehat": 25,
    "…": "every TripResult field (data-model.md)"
  },
  "params": { "…": "every TripParams field" },
  "seed": 521288629
}
```

**Rules:**

- `seed` is given explicitly, even when it equals `definition.seed`.
- `params` holds every `TripParams` field. Most fixtures use the bundled defaults resolved for the
  trip's line, and a fixture that tests a param changes only that one.
- `expected_result` is the engine's `TripResult.toJson()` after `replay`. It is filled by the tool
  (§6), never typed by hand.

## 6. The fixture tool

Run in `packages/trip_engine`:

| Command | Effect |
| --- | --- |
| `fvm dart run tool/fixtures.dart check` | Replays every fixture and prints any whose result differs. Exits 1 on a difference. The test suite does the same. |
| `fvm dart run tool/fixtures.dart update <file>…` | Recomputes `expected_result` for the named files and rewrites them in the canonical layout. A person then reviews the diff. |
| `fvm dart run tool/fixtures.dart show <file>` | Prints the event sequence of a fixture's replay, one per line, for authoring and review. |

`update` never runs in CI. Per-fixture expectation tests
(`test/fixtures/fixture_expectations_test.dart`) assert the rule each fixture is about, so a wrong
`update` fails review and CI.

## 7. What each side must do

| Side | Must |
| --- | --- |
| Dart (`packages/trip_engine`, this feature) | Replay every fixture to its `expected_result` exactly. Prove the SC-002 coverage list. Prove pacing invariance and rebuild at 10 cuts. |
| Python (`tools/content_kit`, this feature) | Validate every fixture's `definition` against `trip.schema.json` and rules V-T8 and V-T9. |
| Python (`tools/solver`, B05) | Replay every fixture to its `expected_result` exactly, fingerprint included. CI fails on any mismatch. |
| Server (B03, B08) | Store `command_log_hash` with `TripRun`. B08 replays `command_log` through the mirror to verify challenge results. |
