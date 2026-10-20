# Research: Trip Engine (M01)

Phase 0 of [plan.md](./plan.md). Each section gives the decision, why, and what was rejected. The
open item this feature had to settle, mobile §24.4 (resume or restart after the app is killed), is
R10. The M03 hand-over (`trip_hints_enabled_line_gamaa`) is R12. The exact rules live in
[contracts/rules.md](./contracts/rules.md); this file explains the choices behind them. Package
versions come from the local pub cache and B04's lockfiles, checked 2026-10-20.

## R1. Package, toolchain and dependencies

**Decision.** A pure Dart package at `packages/trip_engine` (mobile §5), with:

- **SDK:** `^3.13.0`, the floor of the app and `content_models`. It runs on Dart 3.13.5, bundled
  with the FVM-pinned Flutter 3.47.7. Every command runs through `fvm dart`.
- **Dependencies:**
  - `content_models` (path `../content_models`), for `TripDefinition` and the glossary enums
    (B04 hand-over);
  - `crypto ^3.0.7`, for the command-log fingerprint (R9).
- **Dev dependencies:** `test ^1.33.0`, `coverage ^1.16.0` and `lints ^6.1.0`, as in
  `content_models`.
- **Lints:** `lints/recommended.yaml` plus `strict-casts`, `strict-inference` and
  `strict-raw-types`, as the app has.
- **No `build_runner` in the engine.** Commands, events and state are hand-written Dart 3 sealed
  and final classes. `content_models` still needs its own `build_runner` run first, because its
  `*.freezed.dart` and `*.g.dart` parts are gitignored.

**Why.**

- Constitution I: the engine imports no Flutter, Flame, Firebase or plugin. `content_models` and
  `crypto` are pure Dart, and `content_models` is the generated model package that constitution VII
  requires the engine to read.
- No Clock, Random or ContentSource interface is needed. Time is the caller's step count, the PRNG
  is internal and seeded (R4), and the definition is passed in.
- Without codegen, the engine has one build step fewer, and its classes stay plain enough to mirror
  line by line in Python (B05).

**Rejected.**

- Putting the engine inside `apps/mobile`: the solver, fixtures and tests must run without Flutter
  (constitution I, SC-006).
- freezed for the engine's state: it adds codegen for value classes the engine needs few of.
- `package:collection` for deep equality: state is compared through its canonical JSON (R2).

## R2. A functional core: immutable state, pure `step` and `apply`

**Decision.** The rules are pure functions over an immutable `TripState`:

- `step(state, params) → (state', events)` advances one logic step;
- `apply(state, params, command) → accepted(state', events) | rejected(reason)` applies one command.

`TripEngine` is a thin shell. It holds the current state, the accepted-command log and the pause
flag, and returns each call's events. Collections inside the state are unmodifiable. An update
builds new objects only along the changed path, and everything else is shared.
`TripState.toJson()` gives a canonical form (via `content_models`' `canonicalJson`). Tests compare
two states as two strings: the rebuild test (SC-009) and the replay-invariance test.

**Why.**

- Replay, rebuild (R10) and parity are all "run the same pure function over the same inputs". A
  pure core makes that true by construction and keeps the Python mirror a direct translation.
- Callers read the state but can change it only through commands (FR-072), so M02 can never patch a
  rule.
- The project's coding rules ask for immutable data.
- **Cost.** A full trip has at most 30 passengers, a few dozen tokens and about 45,500 steps (the
  longest trip, 1,500 s, at 33 ms; R12). Copying only what changed in a step is well under the 1 s
  replay budget (SC-004), measured by `test/perf/replay_budget_test.dart`.

**Rejected.**

- A mutable object graph mutated in place: it is faster, but harder to compare, rebuild and reason
  about, and it lets callers hold references that change under them.
- An entity-component system: far more machinery than 30 passengers need.

## R3. Time, integer arithmetic and the order of work

**Decision.**

- **Time.** Time is integer milliseconds. One logic step is 33 ms, so the clock is always `33 × n`.
  A scheduled time `T` (an authored `at_seconds × 1000`, a timer or a deadline) is reached at the
  first step whose clock is `≥ T`. Commands apply at the current clock, between steps.
- **Hops.** A hop's elapsed time grows by 33 each step, and the hop ends at the step where it
  reaches its duration. The excess isn't carried over. A 1300 ms hop takes 40 steps.
- **Integer operations.** Only `+`, `−`, `×`, comparison, and floor division `~/` on non-negative
  operands. Percentages are `x * pct ~/ 100`. Dart's `~/` truncates toward zero and Python's `//`
  floors, and the two agree only on non-negative numbers. So every division is on non-negative
  values, and the rules reference says so.
- **Magnitudes.** No value comes near 2^53: the largest money total is 30 × 10 × 20000 =
  6,000,000, and the largest clock is under 10^7 ms. `canonicalJson` then accepts every value.
- **Order of work.** One fixed order inside a step, written in contracts/rules.md §3. It extends
  mobile §7.3 with timers, then authored events, then scheduled payments, then tokens, then
  patience, then warnings, then stations, then the failure check, then the end check. Inside each
  phase, things run in definition order (passengers, events) or creation order (tokens).

**Why.** Every one of these rules has a single exact meaning in both Dart and Python, which is what
parity needs (constitution III). Fixed iteration orders remove the last source of divergence:
insertion-ordered maps behave the same in both languages, but "for each passenger" must still name
an order.

**Rejected.**

- Carrying the excess of a hop into the next one: it is slightly more accurate, but adds a rule for
  nothing a player can see.
- Floating-point percentages: forbidden (constitution II), and a source of parity drift.

## R4. The PRNG and speech variants

**Decision.**

- **Generator.** `xorshift32` with the shifts 13, 17 and 5 on an unsigned 32-bit state, masked to
  32 bits after each left shift. The state starts at the seed, which the schema keeps in
  1..2^32−1, so it is never 0.
- **Use.** There is one stream per trip, drawn once for every `PassengerSpeaks` event, in emission
  order. The draw (a uint32) is the event's `variant`, and the app shows line
  `variant % lines.length` of the pool.
- **Gameplay.** Nothing else draws from the PRNG. Every gameplay value is authored, tunable or
  derived (payments, times, the break-down table, the change-request selection).

**Why.**

- Constitution XII asks for speech picked deterministically from the trip seed, and the speech pool
  schema says the engine picks it. The engine doesn't know pool sizes, because pools live in the
  pack, not in the definition. So the engine fixes the choice and the app reduces it.
- Keeping randomness out of gameplay means a seed can never change a trip's outcome. The solver
  proves a trip with its authored values, and the daily challenge's seed (B08) only flavors the
  speech.

**Rejected.**

- A hash of `(seed, passenger, key, count)` per line: it works equally well, but the mobile and
  backend docs already name `xorshift32`.
- Random payment times or random breaks: they would make authored trips unprovable by the solver.

## R5. Money tokens and the passing chain

**Decision.** A bundle of money in transit is a `MoneyToken`. That is mobile §7.2's name, and the
spec's "bundle". Each token has a kind: `fare`, `change`, `return`, `redirect`, `break_out` or
`break_in`. It moves from holder to holder, where a holder is `DRIVER` or a seat. The rules are in
contracts/rules.md §5. In short:

- **The next holder is worked out when each hop starts,** not stored as a path, from who is aboard
  at that moment. A passenger who boards or leaves mid-transit is handled with no special case.
- **Routing:**
  - toward the driver, a token goes to the nearest occupied seat ahead in the same column, or to the
    driver from rows front and A;
  - toward a passenger, it goes to the next occupied seat between the current holder and the target,
    in the target's column;
  - a group redirect is one hop of `trip_group_redirect_hop_ms`.
- **Blocking.** A hop can start only if both ends are able to act: the driver, or an aboard
  passenger who is awake or attentive. Otherwise the token waits, and `TokenBlocked` names who is
  blocking it. A hop in progress always finishes.
- **Duration.** `trip_hop_ms`. It is scaled by `trip_hop_pct_hajja` when the holder passing it on is
  a hajja, and by `trip_hop_pct_chatty_row` when the holder's row has an awake chatty passenger.
- **When a passenger gets off,** tokens they hold or are about to receive as a middle holder are
  handed to the driver: a fare counts as arrived, and anything else goes to the tray. Tokens
  addressed to them go back to the tray.

**Why.** Recomputing the next holder is simpler and more robust than repairing stored paths. Both
blocking checks follow mobile §7.7: a sleeping passenger can't take money or pass it on.

**Rejected.**

- Stored paths with repair on boarding and alighting: more state and more edge cases for the
  mirror.
- Letting a dropped or blocked token jump over a blocker: that is the reroute gesture the ux-spec
  dropped (spec Assumptions).

## R6. Fares, payments and judging change

**Decision.** contracts/rules.md §6 has the full rules.

- **The fare** is the current fare of the destination station: the authored fare plus any
  `fare_increase` so far.
  - A student's fare is discounted and rounded up to a multiple of 50:
    `(fare × (100 − pct) + 4999) ~/ 5000 × 50`.
  - A group payer's fare is the sum of the members' fares (FR-030).
- **Paying.** A passenger hands over their authored `payment`. After a fare increase, a passenger
  *not* listed by it tops their payment up to the new fare, in the fewest pieces, when it falls
  short. Listed passengers pay the authored amount, so they may owe the difference. This is what
  "pay at the old fare" means in practice.
- **The balance** (signed) is the payment minus the fare, fixed when the fare is sent. Positive
  means change is owed, and negative means the passenger owes the driver. A tap on a passenger who
  owes makes them pay the rest, in the fewest pieces.
- **Change** reaching a passenger is judged exact, short, over or not owed (FR-033):
  - an honest passenger returns over-change in the fewest pieces;
  - an honest passenger returns change they weren't owed as the same pieces;
  - any other passenger keeps it, and it counts in `overpaid_piasters` (clarification 3).
- **Fewest pieces** is the greedy decomposition over the glossary denominations. The set is
  canonical, so greedy is optimal.
- **Fares collected** is the sum, over passengers, of `min(fare, paid_in)`, where `paid_in` is the
  money from that passenger's fare tokens that reached the driver.
- **Earnings** are the fares collected, minus overpaid, plus tips, floored at 0. They convert to
  whole pounds rounded down, are capped by `max_earnings_jenehat`, and are paid only when the trip
  finishes.

**Why.**

- The top-up rule gives `fare_increase` a real effect. Without it, "listed" and "not listed"
  passengers would behave the same, since payments are authored.
- `min(fare, paid_in)` counts a bumped fare as never collected, and a partial payment as partial,
  with no special cases.
- Fewest pieces is the only composition rule both languages can't get wrong.

**Rejected.**

- Recomputing the balance when the fare changes after payment: a passenger who has paid has paid.
- Returning excess from the pieces received: this sometimes can't be done (a 1000 note against 500
  of excess), and then needs a second rule anyway.

## R7. Passengers: alertness, patience and claims

**Decision.** contracts/rules.md §7.

- **Alertness:** `awake`, `asleep`, `waking` (until `wake_at`), `muted` (with a tap count), or
  `attentive` (until a deadline).
  - A sleeper starts `asleep`. A tap sets `waking` for `trip_wake_ms`, then he is awake until
    `trip_sleeper_awake_ms` later, and then asleep again (clarification 5). `wake_all` skips
    `waking`.
  - A headphones passenger starts `muted`. The second tap makes them `attentive` for
    `trip_headphones_attentive_ms`.
- **Patience** starts when a passenger is first owed change: `trip_patience_ms`, or
  `trip_patience_pct_hurry` percent of it for `hurry`. It drains 33 per step while they are owed and
  aboard, or `33 × trip_patience_drain_pct_traffic ~/ 100` (49 by default) while traffic is active.
  - At half, the passenger says `wants_change` once.
  - At zero, they cost `rep_impatient` once and lose their tip (clarification 2).
- **Claims.** At most one open claim per passenger, and at most one resolved claim per passenger.
  Once a claim is resolved, later taps only make them say they paid. A false claimer who is
  believed is marked `never_pays`.
- **Group members.** A tap on a member acts on the group's payer, and a member's money questions are
  the payer's. Members get off thanked, or with a missed stop if asleep.

**Why.**

- One resolved claim per passenger stops a player from cycling claims to farm `rep_liar_caught`.
- Routing member taps to the payer matches «خلّيها عليّا»: the payer is the one who pays.
- The half-patience line gives the player a warning before the penalty, a second channel next to
  the visual (constitution XI).

**Rejected.**

- Patience for passengers who haven't paid yet: the spec ties it to waiting for change (FR-042), and
  unpaid passengers are the player's choice to leave.
- Repeated claims: they would turn a memory test into a reputation farm.

## R8. Events and open choices

**Decision.** contracts/rules.md §8.

- **Time.** An authored event fires at the first step at or after its `at_seconds`, on the trip
  clock, which is not shifted. Station times shift. An event that needs a passenger who isn't aboard
  at that moment (not yet boarded, or already gone) is skipped, with `EventSkipped`.
- **Shifts.** `traffic`, `open_road` and `traffic_jam` move the next unprocessed station and every
  later one. Open road is clamped so the next station is at least `trip_station_warning_ms` away,
  and later stations move by the clamped amount.
- **Bump** drops only tokens that are mid-hop. Tokens waiting in a hand stay there.
- **Open choices** are claims (keyed by passenger), disputes (keyed by event index) and change
  requests (keyed by passenger). Several can be open at once. They resolve by command, or by
  themselves when a passenger involved gets off (FR-047).
- **Change-request pieces.** The pieces for a change request come from the tray by a deterministic
  backtracking search: denominations below the note, largest first, each count tried from the most
  available down. The first exact total wins. If none exists, agreeing is rejected.

**Why.**

- Events on the unshifted clock keep authoring simple: "at 20 s" means 20 s into the trip, whatever
  traffic did.
- Skipping beats refusing, because whether a passenger is aboard can depend on shifts the author
  can't fully predict.
- Backtracking always finds a combination when one exists. It matches greedy whenever greedy works,
  and it is about 15 lines in each language.

**Rejected.**

- Pure greedy for change requests: it can miss a valid combination when counts are limited.
- Events on the shifted station clock: then an event's time would depend on earlier events.

## R9. Commands, the log, the cap and the fingerprint

**Decision.** contracts/replay-and-fixtures.md.

- **Commands** are a sealed `Command` hierarchy with the 13 names from spec FR-050. mobile §7.4's
  names are kept, plus `ResolveDispute`, `ResolveChangeRequest` and `Abandon`.
- **The wire form** of a command is a JSON array `[t_ms, "Name", ...args]`, as backend §11.2's
  example shows (`[33, "PickFromTray", 100]`).
- **The log** is the array of every accepted command, in order. Rejected commands are not logged.
  Pause and resume are not commands.
- **The cap.** At most **1,200 accepted commands** per trip. The longest command encodes to 45
  bytes (a 7-digit `t_ms` and a 4-character passenger id), so the log stays under 55 KB, below
  backend §16's 64 KB limit (FR-055, SC-005). It is a
  protocol limit, not a balancing number, so it is a constant, not a tunable.
- **`Abandon` is exempt** (owner decision, 2026-10-20, raised by the T119 review). Without it, a
  player at the cap could neither leave a running trip nor a failed one. `Abandon` ends the trip, so
  a log holds at most 1,201 entries, still under 55 KB. `Revive` stays capped: a trip revived at the
  cap could take no further command, so its owed passengers would only fight. M02 hides the revive
  offer when `commands_accepted` has reached the cap.
- **The fingerprint** (`command_log_hash`) is the lowercase hex SHA-256 of the log's canonical JSON,
  encoded as UTF-8. That is the canonical form `content_models` and `wassal_content` already share,
  so Python computes the same fingerprint with `hashlib`.

**Why.** It reuses the backend's example format and the existing canonical JSON. 1,200 commands is
twice the densest plausible play (a tap or pick every second for 10 minutes) and still leaves
headroom under the server limit.

**Rejected.**

- Logging rejected commands: they don't change state, and they would only bloat the log.
- Step numbers instead of `t_ms`: the backend example uses milliseconds, and both identify the step.
- Shorter command names to save bytes: the names are a shared contract with B05.

## R10. The replay record and resuming (resolves mobile §24.4)

**Decision.** The owner chose to resume exactly (spec clarification 1).

- **The record.** `ReplayRecord = {definition, seed, params, command_log, t_ms}`: a replay tuple
  plus the clock it reached. It is self-contained, so a pack swapped since doesn't matter.
- **Rebuilding.** `TripEngine.rebuild(record)` starts the trip. For each logged command, it steps to
  the command's `t_ms` and applies it, and every command must be accepted. Then it steps to `t_ms`,
  stopping early if the trip ends.
  - Events produced along the way are discarded.
  - A running trip is left paused. A failed one stays failed, and a finished one stays finished.
  - A record whose commands are out of order, whose `t_ms` is before its last command, or that has a
    command rejected on replay, is refused with `RebuildRefused`.
- **Saving the record** on every accepted command and on every pause belongs to M02's
  `TripController`. So do offering the trip back and ending a refused record as abandoned.

**Why.**

- The replay record *is* the checkpoint. No snapshot format to version, migrate or keep in parity.
  Mobile §10's "checkpoint every station" is replaced.
- Resuming lands on the exact state that was left, so killing the app is never a retry.
- Fuel is untouched (FR-071), so M05 and B03 need no refund op.
- **Cost.** Rebuilding is a replay, under 1 s for the longest trip (SC-004).

**Rejected.**

- Resume at the last station: it lets a player kill the app to retry a stretch.
- Restart with or without a refund: the owner chose resume.
- A serialized `TripState` snapshot: a second format to keep in parity for no gain.

## R11. Parity fixtures and the fixture tool

**Decision.** contracts/replay-and-fixtures.md.

- **Location and form.** One JSON file per case in `fixtures/parity/`, with exactly the
  constitution's five keys: `definition`, `seed`, `params`, `command_log` and `expected_result`.
- **Naming.** `<area>__<case>.json`, with the areas `core`, `archetype`, `event`, `command`,
  `booster`, `ending`, `sample` and `stress`. `fixtures/parity/README.md` lists what each one pins.
- **Authoring.** An author writes `definition`, `seed`, `params` and `command_log` by hand.
  `fvm dart run tool/fixtures.dart update <file>` fills `expected_result` from the engine, and a
  person reviews the diff. `fvm dart run tool/fixtures.dart check` is what CI runs, through the
  test suite. Files are pretty-printed with sorted keys, so diffs stay readable.
- **What is checked.**
  - The Dart suite replays every fixture and compares results.
  - `fixture_coverage_test.dart` proves SC-002 mechanically: every supported archetype, event,
    command, booster and ending appears in some fixture, and every sample trip has a 3-star one.
  - A per-fixture expectation test asserts the rule each fixture is about, for example "the sleeper
    misses his stop", so `update` can't silently bless a wrong result.
- **Python.** A `wassal-content` test validates every fixture's `definition` against the trip
  schema and the engine rules of R15. pytest replaying the fixtures arrives with B05.
- **Stress fixture.** `stress__longest_trip.json` has a full vehicle, the longest trip the params'
  bounds allow (1,500 s) and 1,200 commands. It serves both SC-004 and SC-005.

**Why.**

- `update` mirrors B04's `golden --update`: the engine computes, and a person reviews.
- The expectation tests are the human statement of each rule, and the fixtures pin the numbers for
  the mirror.

**Rejected.**

- Extra keys in fixtures (descriptions, expected events): the constitution fixes the form, and event
  sequences are checked inside Dart (FR-061).
- Generating fixtures from Dart scripts: the log would then be code, not data B05 can read as it is.

## R12. Params and tunables (settles the M03 hand-over)

**Decision.** contracts/tunables.md.

- **`TripParams`** has one integer field per rule number: the existing per-line `trip_hop_ms`, the
  undo window, the six `rep_*` keys, and the 20 new keys of spec FR-067.
  - It has no defaults in code.
  - Its wire form, in fixtures and replay records, is a flat JSON object keyed by tunable names,
    with the per-line key written without its suffix (`trip_hop_ms`).
  - `TripParams.fromTunables(values, lineId)` resolves a flat tunables map, such as the app's
    `ConfigSource` values or `tunables.json`, for one line. A missing or mistyped key is an error.
- **Engine tests** take their defaults from the app's `apps/mobile/assets/config/tunables.json`,
  read from disk by a test helper. `params_tunables_test.dart` fails if a `TripParams` key is missing
  from that file. There is still one source of defaults (constitution VIII).
- **The longest trip is bounded** (the owner's choice, 2026-10-20). The engine doesn't check booster
  stock (FR-052), so without a limit a log of 1,200 traffic jams would stretch a trip to about
  13,000 s, and B08 replays logs it doesn't trust. So `traffic_jam` is limited per trip by the new
  tunable `booster_traffic_jam_max_per_trip` (default 3; the ad's own cap is 1 per trip, glossary
  §3.4). Validation caps it at 5, and `booster_traffic_jam_ms` at 60,000, so the longest trip is
  600 s of stations plus 10 traffic events of 60 s plus 5 jams of 60 s: 1,500 s, whatever Remote
  Config says. Rejected: no limit, which leaves B08 unbounded; a limit of 1, which would stop a
  player who watched the ad from also buying one with BONAT.
- **The app's registry** gains the 20 keys and the `TripHintsMode` enum (`off`, `first_time`,
  `always`), and replaces `trip_hints_enabled_<line_id>` with `trip_hints_mode_<line_id>`. That
  takes it from 30 to 50 keys. `tunables.json` and the defaults tests are updated with it. M02 reads
  the hints mode, and the engine doesn't (FR-069).
- **mobile §14.3** is updated in the same change. The backend copy is R19.

**Why.**

- Defaults live only in `tunables.json`, so the engine, its tests and the app can't disagree.
- Collapsing the per-line key keeps fixtures line-independent and readable.
- An enum with three wire values is the smallest change that expresses the ux-spec's third hint mode
  («أول مرة لكل نوع راكب جديد بس»).

**Rejected.**

- Defaults in `TripParams`: magic constants in code (constitution VIII).
- Keeping `trip_hints_enabled` and adding `trip_hints_first_time`: two keys whose combinations make
  no sense.
- The engine reading `ConfigSource`: forbidden (constitution VIII).

## R13. Speech keys and the capabilities file

**Decision.** contracts/content-contract.md.

- **Slots.** The engine speaks through 23 named slots (`pays`, `stop_near`, `claims_paid` and so on).
  The default key for a slot is `passenger.<slot>`, and a passenger's `speech_keys[slot]` overrides
  it. `PassengerSpeaks` carries the passenger, the slot, the resolved key, the variant (R4) and, when
  the line has them, `amount_piasters` and `station_id`, which fill `{amount}` and `{station}`.
- **The capabilities file.** One machine-readable contract, `content/engine/capabilities.json`,
  lists:
  - the supported archetypes;
  - the supported events, with the parameters each requires or forbids;
  - the speech slots and their placeholders;
  - the allowed change-request notes.
- **Who reads it:**
  - `capabilities_test.dart` asserts that the engine and the file agree;
  - `wassal-content` reads its packaged copy for validation (R15). `codegen` copies it into
    `src/wassal_content/engine/capabilities.json`, and `codegen --check` covers the copy, the same
    way it covers the schemas;
  - B05's mirror reads it later.

**Why.**

- B04 asked for "the list of speech keys the engine emits". One file answers that, and also
  carries what content validation needs to refuse unsupported archetypes and malformed events
  before a build (FR-066).
- Packaging the copy keeps the backend image free of repo paths, as for the schemas.

**Rejected.**

- Speech keys in Dart only: Python can't read them.
- Generating the file from Dart: it adds a build step, and a hand-written file checked by a test is
  simpler.
- Putting it in `content/schemas/`: `codegen` would try to treat it as a schema.

## R14. The trip schema change and its ripple

**Decision.** contracts/content-contract.md §1.

- **The schema change.** `TripRules` gains a required boolean, `no_fights_required` (FR-057).
  Nothing else in the schema changes. The event parameter rules can't be written in B04's profile,
  which allows no combinators, so they live in the content rules (R15).
- **Allowed now.** No pack has been promoted, because `content/source/pack.json` doesn't exist. So a
  required field can be added without a major bump (B04 FR-010).
- **What follows in the same change:**
  - **content_kit:** `codegen` regenerates `_generated.py`, the packaged schemas and the Dart
    models.
  - **content:** every trip in the examples gains the field: the sample trips, the valid trip
    examples, the trips in `valid/pack/core.json`, and the 13 invalid trip examples (each must still
    fail at its named field only). `golden --update` rewrites the sample checksums.
  - **backend** (B04's authoring app):
    - a `no_fights_required` `BooleanField(default=False)` on `Trip`, with an add-field migration,
      which is expand-only;
    - the importer, the snapshot, the admin fieldset, the factories and the tests that build trips
      are updated.

**Why.**

- The story rule changes a trip's outcome, so it must be data the engine reads (constitution I,
  VII).
- A required field keeps the profile's "no defaults" rule. Authors must decide for every trip.
- The backend ripple is mechanical and covered by B04's existing tests.

**Rejected.**

- Deriving it from `kind: story`: not every story trip forbids fights. «المعلم راكب معاك» comments,
  but doesn't fail the trip.
- An optional field: the profile has no `default`, so readers would each have to invent one.
- Deferring the rule to M10: the outcome must come from the engine, and M10 has no engine work.

## R15. Content validation rules

**Decision.** Four new rules in `wassal_content.rules`, all errors, all reading the packaged
capabilities file:

- **V-T8 (event parameters):** every event has the parameters its row in the capabilities file
  requires, and none it forbids. Counts of `passenger_ids`, `seconds` 1..60 for traffic and open
  road, and an allowed note for a change request are all checked.
- **V-T9 (engine support):** every passenger's archetype and every event is supported by the engine.
  The phase 2 and 3 archetypes fail until their line's feature adds them.
- **V-T10 (engine speech):** a pack has a speech pool for every slot's default key. B04's V-T6
  already checks passenger overrides.
- **V-T11 (slot placeholders):** a pool reached through a slot, by default key or by override, uses
  only that slot's placeholders. A `{station}` in a `pays` line would otherwise render as nothing.

The sample pack gains a pool for each of the 20 slots it lacks, with short Egyptian Arabic lines
that pass B04's text rules (no digits; placeholders only `{amount}` and `{station}`). Backend tests
that build packs gain a factory helper that adds every engine pool.

**Why.** Authors see these problems in the admin's validation report, not as a refusal on a tester's
phone (FR-066). Making them errors protects players. A missing pool would show a passenger who opens
his mouth and says nothing.

**Rejected.**

- Warnings: a pack with a missing pool or an unsupported archetype must not reach players.

## R16. Testing strategy and guards

**Decision.** Tests come first for every rule (constitution XIII).

- **Unit tests** per rules module: chain, fares, change, passengers, events, stations, commands,
  reputation and scoring. They use small definitions built in code by `test/support/builders.dart`.
  Each archetype, event, booster and command has its own group.
- **Fixtures:** the replay test, the coverage test and the per-fixture expectations (R11).
- **Invariance:**
  - replaying every fixture with step pacings of 1, 7 and "all at once" gives an identical result,
    event sequence and fingerprint (SC-001);
  - each fixture is rebuilt at 10 evenly spaced cuts (SC-009).
- **Fuzz:** 200 random command logs per sample trip, from a fixed seed. Every run must end with no
  exception, integer-only money, the tray plus the hand plus money in transit equal to what entered
  and left, and a replay identical to the run.
- **Guards** (in `test/guards/`):
  - imports in `lib/` limited to `dart:core`, `dart:convert`, `dart:collection`,
    `package:content_models` and `package:crypto`;
  - no `double`, `num`, `toDouble` or `/` as an operator in `lib/` (SC-007);
  - no `DateTime`, `Stopwatch`, `Random` or `dart:io`;
  - no Arabic characters outside comments.
- **Perf:** `replay_budget_test.dart` replays the stress fixture and fails above 1 s (SC-004).
- **Coverage:** at least 90% line coverage, gated with the app's `tool/check_coverage.dart --min 90`.
- **Python:**
  - pytest for V-T8 to V-T11 with valid and invalid examples;
  - a test that validates every `fixtures/parity/*.json` definition;
  - backend tests for the new field (import, export, admin, snapshot).

**Why.** These cover every success criterion with an automated check except the device-side budget,
which M02 measures. The money-conservation property in the fuzz test catches any rule that creates
or destroys money by accident, the most likely parity bug.

**Rejected.**

- A property-testing package for Dart: a seeded loop over our own PRNG is enough, and it is
  deterministic.
- Timing on a device in CI: there isn't one, and the trip screen's fps budget is measured in M02.

## R17. CI

**Decision.** contracts/ci-checks.md.

- **mobile.yml.** The `trip_engine` steps follow `content_models`: `pub get`, the format check,
  `analyze --fatal-infos`, `test --coverage`, and the 90% gate. The `changes` filter adds
  `fixtures/`. To shorten CI, both packages now run in their own `packages` job, in parallel with
  the app's `app` job and `build-android`, and `check` is the job that sums them up
  (contracts/ci-checks.md).
- **backend.yml.** Its `changes` filter adds `fixtures/`, so the content-kit job's fixture test runs
  when fixtures change.
- **Parity in Python** waits for B05, which adds pytest over `fixtures/parity/` to the backend
  workflow.

**Why.** It is the pattern B04 used for `content_models`. Adding steps to the required check keeps
branch protection unchanged.

## R18. Where the rules reference lives, and which documents change

**Decision.**

- **The rules reference.** [contracts/rules.md](./contracts/rules.md) is the rules reference
  FR-063 asks for. During implementation it is copied to `packages/trip_engine/RULES.md`, which from
  then on is the living source that B05 mirrors and every rule change edits. The contract file then
  points there.
- **docs/architecture-mobile.md:**
  - §7.2 to §7.9 are updated: types, commands, events, money flow, scoring and difficulty, each
    linking `RULES.md` for exact behavior;
  - §10's checkpoint sentence gives way to R10;
  - §14.3 gets the new keys and the hints mode;
  - §24.4 is marked resolved.
- **Repo docs:** `CLAUDE.md` gains the engine's commands and drops "planned" for
  `packages/trip_engine`. `docs/owner-actions.md` gets an M01 section, which has no owner actions.

**Why.** A rules document next to its code is updated in the same PR as the code. The architecture
doc keeps the overview without duplicating every detail.

## R19. The backend copy of the new tunables

**Decision.** Constitution VIII says a new tunable is added "to the key table in mobile §14.3 and to
the backend settings in the same change". The backend has no settings store for tunables yet:
`liveops.LiveSetting` arrives with B10. M01 adds the keys to §14.3 and to the app's registry and
bundled defaults. B10 is handed the job of creating `LiveSetting` with every key in
`tunables.json`, the 20 new ones and the hints mode included. This is recorded in the plan's
Complexity Tracking as a time-boxed deviation from VIII that ends when B10 merges. The owner approved
it on 2026-10-20, and the follow-up that removes it is B10's "Handed over from M01" item in
`docs/delivery-plan.md`.

**Why.** There is nowhere to put the copy. Inventing a backend tunables module before B10 designs
live settings would pre-empt B10's model.

**Rejected.**

- An ad-hoc backend constants module now: B10 would have to replace it.
- Leaving it unrecorded: `/speckit-analyze` would rightly flag it.

## Handed to later features

- **B05:**
  - mirror `packages/trip_engine/RULES.md` in `tools/solver`;
  - read `content/engine/capabilities.json`;
  - make pytest reproduce every `fixtures/parity/*.json`;
  - add that job to CI.
- **M02:**
  - drive `TripEngine`, building `TripParams` from `ConfigSource` with `fromTunables`;
  - save the replay record on every accepted command and pause, and offer a killed trip back
    (R10);
  - show hints by `trip_hints_mode_<line_id>`;
  - hide who paid except during `ledger_peek`;
  - decide whether choices pause the trip.
- **B03:**
  - `TripResult` now carries `outcome`, the counters and `reputation_lost` (data-model.md);
  - the lower bound on duration (`0.85 × last station time`) must allow for open road and
    other schedule shifts;
  - a resumed trip is still one `trip_start` and one `trip_result`.
- **B10:** `liveops.LiveSetting` gets every key in `tunables.json`, including the 20 new ones and
  `trip_hints_mode_<line_id>` (R19).
- **B08:** a replay lasts at most 1,500 s of logic time, about 45,500 steps (R12), so verifying a
  run has a fixed worst-case cost.
- **M04:** the bundled pack must carry a pool for every engine slot (V-T10 already enforces it on
  build).
