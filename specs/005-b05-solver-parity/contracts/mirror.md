# Contract: The Mirror (`wassal_solver.engine`)

The Python copy of `packages/trip_engine/RULES.md`. It reproduces state, results, the fingerprint,
rejections and refusals, but not events or speech (spec FR-006, research R3). The wire formats are
M01's [replay-and-fixtures.md](../../004-m01-trip-engine/contracts/replay-and-fixtures.md), and the
types are M01's [data-model.md](../../004-m01-trip-engine/data-model.md).

## 1. Public surface

```python
from wassal_solver.engine import (
    TripParams, Trip, TripRefused, ReplayRefused, ReplayReason, Rejection,
    start, replay, replay_untrusted, command_log_hash, SUPPORTED,
)
from wassal_solver.engine.commands import PickFromTray, LoggedCommand, decode_log

params = TripParams.from_tunables(values, line_id)      # or TripParams.from_json(wire)
trip = start(definition, params, seed)                  # TripDefinition model; raises TripRefused
trip.step()                                             # one 33 ms step; no-op unless running
trip.step_to(t_ms)                                      # steps until trip.t_ms >= t_ms or not running
rejection = trip.apply(PickFromTray(100))              # None if accepted (and logged)
copy = trip.clone()                                     # independent state, for the solver
trip.status, trip.t_ms, trip.state, trip.result, trip.command_log

result = replay(definition, seed, params, command_log)  # TripResult; raises ReplayRefused
result = replay_untrusted(document)                     # JSON bytes or str, or its parsed value (R6)
result.to_json()                                        # == Dart TripResult.toJson()
```

- `apply` takes one of the 13 command dataclasses of `engine.commands`, without its `t_ms`, and logs
  `LoggedCommand(trip.t_ms, command)`, whose wire form is `[t_ms, "Name", ...args]`, when it accepts
  it. `decode_log` reads a wire log into `LoggedCommand`s.
- `TripResult.to_json()` keys and values equal M01 data-model "TripResult" field for field.
- `SUPPORTED` is the mirror's own table of the archetypes, events and event parameter rules it
  implements. A test requires it to equal `wassal_content.engine.capabilities()` (spec FR-003).

## 2. What it must match

| Area | Rule source | Checked by |
| --- | --- | --- |
| Start refusals and their codes | M01 data-model "Validation" | Unit tests, one per code |
| Params bounds (`bad_params`) | M01 data-model "TripParams" | Unit tests |
| Step order | `RULES.md` §3 | Unit tests per phase, plus the fixtures |
| Every command, its checks in order, and its rejection codes | §4 | Unit tests per command, plus the `command__` fixtures |
| Tokens and the chain | §5 | Unit tests, plus the `core__` fixtures |
| Fares, change, passengers, events, stations, reputation and the ending | §6–§11 | Unit tests, plus every fixture area |
| Tables and selection | §14 | Unit tests |
| Integer rules | §15 | Guard scan, plus a Hypothesis property |
| `command_log_hash` | M01 replay-and-fixtures.md §3 | The fixtures |

**Not mirrored:** domain events, speech and the PRNG (only `bad_seed` is checked), `pause`, `resume`,
and rebuild-to-`t_ms`.

## 3. `replay`

```text
trip = start(definition, params, seed)        # TripRefused → ReplayRefused(trip_refused)
for i, entry in enumerate(command_log):
    if entry.t_ms < previous t_ms: refuse(t_ms_goes_down, index=i)
    trip.step_to(entry.t_ms)
    if trip.t_ms != entry.t_ms: refuse(clock_stopped, index=i)   # the trip ended first
    if trip.apply(entry.command) is not None: refuse(entry_rejected, index=i, rejection=…)
while trip.status == "running": trip.step()
return trip.result
```

This is the same algorithm as Dart's `replayEngine` and `playLog`, with the same four reasons and
messages:

| `ReplayReason` | Message |
| --- | --- |
| `trip_refused` | `the trip is refused`, with the start `refusals` |
| `t_ms_goes_down` | `t_ms goes down along the log` |
| `clock_stopped` | `the clock stopped at <t_ms>, before <entry t_ms>` |
| `entry_rejected` | `<Name> was rejected: <code>`, with the `rejection` |

## 4. `replay_untrusted(document)`

The input is `{definition, seed, params, command_log}`: its JSON text (bytes or str), read with
the content kit's strict loader, or the value it parsed to. The checks run in this order, and the
first that fails refuses:

| Reason | When |
| --- | --- |
| `bad_input` | Text over 256 KiB (`MAX_INPUT_BYTES`, over three times the longest trip's tuple, indented), checked before parsing. Not strict JSON (a float, `NaN`, a duplicate key), not an object, a key missing or extra, a non-integer number or a non-JSON value anywhere, nesting past 32 levels, or a `seed` that isn't an integer. |
| `bad_definition` | `document_findings("trip", definition)` has an error. The `findings` are attached. |
| `bad_params` | `TripParams.from_json` fails, or a bound is broken. |
| `bad_log` | Not a list. Over 1,201 entries. An entry that isn't an array. A `t_ms` that is negative, not a multiple of 33, or over 1,500,000. An unknown name. Wrong arguments: count, type, or a denomination that isn't in glossary §3.2. The `index` is attached. |
| Then `replay`'s four reasons | As in §3. |

**Guarantees.**

- No exception other than `ReplayRefused` escapes, for any JSON input. A Hypothesis test checks
  this.
- At most 1,201 commands are applied.
- Stepping stops when the trip leaves `running`, which is at most about 45,500 steps.
- No file, network, clock or database access.

**What the caller must do** (B08). `replay_untrusted` checks that a tuple is well formed and
within the rules' bounds; it can't know which rules the run was meant to be played under.

- Replay with the server's own `definition` (by `trip_id` and `rev`, from the pack version the
  client declares) and the server's own `params`, never the client's copies, or refuse a tuple
  whose `definition` or `params` differ from them. Otherwise a player who sends `rep_fight` 0 or a
  huge `trip_patience_ms` verifies a run under rules they wrote.
- Cap the request body before reading it, and pass the body as bytes.
- Treat any exception other than `ReplayRefused` as an internal error, not as a refusal of the
  player's run.

## 5. The parity check

- **Test.** `tests/parity/test_fixtures.py` runs once per `fixtures/parity/*.json`:
  `replay(…).to_json() == expected_result`.
- **Command.** `wassal-solver parity [PATH…]` (contracts/cli.md).
- **On a mismatch**, it prints the fixture, the first differing JSON path (by key order, then index)
  and both values, then exits 1.
- **Fixtures are read** with `wassal_content.loader.load_json_bytes`, which is strict JSON: no
  floats, no duplicate keys.
- **Where the I/O is.**
  - `engine/fixture.py` works on parsed documents only: the five keys, `first_difference`, and
    building a solver fixture. Dart's `lib/src/fixture.dart` is the same, with no `dart:io`.
  - Reading and writing fixture files is in `wassal_solver.fixture_files`, outside `engine/`. The
    engine does no I/O (spec FR-002), and the guard scan checks that.

## 6. Writing solver fixtures

`wassal-solver fixture <trip.json>… [--out fixtures/parity]`:

1. Load and check each trip (`document_findings`).
2. Solve it with the bundled params for its line and the default settings. A trip that isn't solved
   is an error, and nothing is written.
3. Build the document with `engine.fixture.build_fixture`, and write it with
   `fixture_files.write_fixture` as `solver__<trip_id with "." → "_">.json`, with:
   - `definition`: the trip as given;
   - `seed`: `definition.seed`;
   - `params`: `TripParams.to_json()` of the bundled params;
   - `command_log`: the run;
   - `expected_result`: `replay(…).to_json()`.

   The file has its keys sorted, a two-space indent, `ensure_ascii=False` and a trailing newline.
4. Refuse to overwrite an existing file, and exit 1.

A matching entry goes in `packages/trip_engine/test/fixtures/expectations/solver.dart` (3 stars,
`fights == 0`, no mistakes, no boosters). It is written by hand, in the same change.
