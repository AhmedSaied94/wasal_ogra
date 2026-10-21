# Research: Solver and Parity (B05)

The decisions behind [plan.md](./plan.md). Each one gives the decision, why it was chosen, and
what was rejected. The spec's Clarifications fix four of them already: an out-of-band score is a
warning (R11, R13), the mirror reproduces results only (R3), slower players are reported, not
gated (R17), and a full MVP pack may take 30 minutes on staging (R8, R19).

Nothing in the architecture docs is marked NEEDS CLARIFICATION for B05 (delivery plan, step 3), and
the plan's Technical Context has no open item.

## R1. The package: `tools/solver`, a uv project like the content kit

**Decision.**

- `tools/solver` is the uv project `wassal-solver`, with the import package `wassal_solver`, Python
  `==3.13.*` (its own `.python-version`) and hatchling, laid out like `tools/content_kit`.
- Runtime dependencies: `wassal-content` only, as a path dependency (`../content_kit`). That brings
  the generated Pydantic models, the canonical JSON form, the schema validator, the findings type
  and `capabilities()`. Nothing else: no NumPy, no Django.
- Dev dependencies use the content kit's pins (`ruff==0.17.1`, `mypy==1.19.1`, `pytest==9.1.1`,
  `pytest-cov==7.1.0`, `hypothesis==6.170.1`), plus the backend's `pytest-xdist==3.8.0`, so the
  tests run on 4 workers in CI.
- Sub-packages follow backend §10.2: `engine/` (the mirror), `solver/`, `scoring/`, `report/`, plus
  `data/` (package data) and `cli.py`. Backend §10.2's `generator/` belongs to B08, which generates
  daily challenges (spec Out of scope).
- The backend depends on it as a second path dependency
  (`wassal-solver = { path = "../tools/solver" }`) and calls it in-process (backend §10.2).

**Why.** The content kit already proved this shape: a path dependency, a non-editable install into
the image, its own CI job and its own coverage gate. FR-048 asks for nothing but the standard
library, the generated models and the content kit, so CI runs the solver without a database.

**Rejected.**

- **The solver inside `backend/`.** CI would need Django to replay a fixture, and the solver
  couldn't be run by hand without a database.
- **The solver inside `tools/content_kit`.** The content kit's job is the schemas. The mirror and the
  search are a separate concern, with a different coverage gate (R15).

## R2. The mirror's shape: mutable working state with a cheap `clone()`

**Decision.**

- **One module per rules area**, matching `packages/trip_engine/lib/src/rules/` so a reviewer can
  read the two side by side: `step`, `chain`, `fares`, `change`, `claims`, `requests`, `passengers`,
  `authored_events`, `stations`, `course`, `aids`, `reputation`, `scoring`, `command_handlers`, plus
  `money`, `params`, `validation`, `capabilities`, `wire`, `replay` and `fixture`. Each module names
  the `RULES.md` section it implements.
- **State** is a tree of `@dataclass(slots=True)` objects (`TripState`, `PassengerState`,
  `MoneyToken`, `StationState`, choices and counters), with the same fields as M01's data-model.
  A step mutates the state in place, like the Dart engine's `Transition`, which works on a mutable
  copy and freezes it at the end.
- **`Trip.clone()`** copies the state field by field, with no `copy.deepcopy`. The solver branches
  by cloning at a decision point.
- **The public surface** (contracts/mirror.md):
  - `start(definition, params, seed)`, which raises `TripRefused` with M01's codes;
  - `Trip.step()`, `Trip.step_to(t_ms)`, `Trip.apply(command)` (returning a rejection or `None`),
    `Trip.result`, `Trip.status` and `Trip.clone()`;
  - `replay(definition, seed, params, command_log)`.
- **Integers only** (`RULES.md` §15):
  - `//` and `%` only on non-negative operands;
  - no `float`, no `/`;
  - no `bool` in arithmetic;
  - lists iterated in the fixed orders of §1.2, and no iteration over a `set` or over a dict that
    wasn't built in a fixed order.

  Guard tests scan the source for `float`, `/`, `random`, `time` and `datetime`, as the Dart guards
  do.

**Why.**

- Python allocates slowly. Rebuilding immutable objects on every one of up to 45,500 steps, and
  again on every branch of the search, would cost the solver most of its budget.
- A mutable step plus an explicit clone is the same model as Dart's `Transition`: change a working
  copy, then hand it over. So the two engines still read alike.
- The same module split lets every rule change touch matching files in both languages.

**Rejected.**

- **Immutable state with `dataclasses.replace`.** Faithful to Dart's surface, but several times
  slower in CPython. The search would get far fewer simulations within its budget.
- **The Dart engine compiled with `dart compile exe` and called from Python.** This is backend
  §10.3's fallback. Starting a process per simulation, and serializing state across the boundary at
  every branch, makes search impossibly slow. Python would also lose the mid-trip state that
  branching needs. It stays the fallback for *replay only*, if keeping parity proves costly.
- **Generating Python from Dart.** There is no maintained tool for it, and the generated code would
  be unreadable in review.

## R3. What the mirror leaves out

**Decision** (Clarifications Q2). The mirror reproduces state, results, the fingerprint, rejections
and refusals. It leaves out:

- **Domain events**, the `List<DomainEvent>` of each step. What the solver needs (who is owed, who is
  asleep, where tokens are) is in the state.
- **Speech** (§12), and with it the PRNG (§13). The PRNG is drawn only by speech, and no
  `TripResult` field depends on either. The seed is still validated (`bad_seed`), so refusals stay
  equal.
- **`pause()` and `resume()`**, which never appear in a log (replay-and-fixtures.md §2), and the
  rebuild-to-`t_ms` of a replay record. B08 replays whole runs.

Everything else is mirrored, the aids and `Revive` included, because fixtures use them.
`RULES.md`'s opening is changed to say that the mirror reproduces state and results, and that the
Dart tests alone check the event order and speech.

**Why.** No result depends on events or speech, and no MVP server feature reads them. That is about
900 lines of Dart events and speech code that would otherwise need a Python twin and a
cross-language check of its own.

**Rejected.** A full mirror with an event-sequence comparison: Clarifications Q2 chose against it.

## R4. Parity: the check, the fixture tool and solver fixtures

**Decision.**

- **The check.** `tests/parity/test_fixtures.py` is parametrized over every
  `fixtures/parity/*.json`. Each case loads the five keys, replays them through the mirror and
  compares the result with `expected_result` (`TripResult.to_json()`), `command_log_hash` included.
  - A mismatch prints the fixture, the first differing JSON path and both values.
  - `wassal-solver parity` does the same from the command line, and exits 1 on a difference.
  - Fixture files are read with the content kit's strict JSON loader, so a float in a fixture fails.
- **The capabilities check.** A test compares the mirror's supported archetypes, events and event
  parameters with `wassal_content.engine.capabilities()`, the packaged copy of
  `content/engine/capabilities.json`. The two must be equal.
- **Solver fixtures** (FR-041). `wassal-solver fixture <trip.json>…` solves each trip with the
  bundled params and writes `fixtures/parity/solver__<trip_id with "." as "_">.json`:
  - in the fixture form (five keys, sorted, two-space indent, trailing newline);
  - with the run as `command_log` and the trip's own seed;
  - with `expected_result` computed by the mirror.

  It refuses to overwrite a file. Rewriting an existing fixture's `expected_result` stays with
  Dart's `update` (FR-012).
- **The Dart expectations.** A new `packages/trip_engine/test/fixtures/expectations/solver.dart` has
  one entry per solver fixture. Each asserts 3 stars, no fights, no mistakes and no boosters, and is
  registered with the expectations test, so the Dart suite accepts the new area (FR-013). The
  fixture coverage test learns the `solver` area. `fixtures/parity/README.md` and M01's area table
  get the new row.
- **Areas.** `solver__` joins the areas of M01 `replay-and-fixtures.md` §5.

**Why.** Dart replaying runs that Python found is the one check of the two engines against each
other on logs nobody wrote by hand. One writer per existing fixture avoids two tools fighting over
the same `expected_result`.

**Rejected.**

- **Python rewriting any fixture's result.** Two writers of the same file, and an `update` in the
  wrong language could hide a mirror bug.
- **One CI job running both engines on random logs.** It needs both toolchains in one job, and the
  solver fixtures plus Dart's own seeded fuzz already cover the ground.

## R5. Params: the bundled tunables, copied into the package

**Decision.**

- `wassal_solver/data/tunables.json` is a byte-for-byte copy of
  `apps/mobile/assets/config/tunables.json`.
  - `wassal-solver sync` writes it, and `wassal-solver sync --check` fails when it differs.
  - CI runs `--check`, as the content kit's `codegen --check` guards its copy of
    `capabilities.json`.
- `TripParams.from_tunables(values, line_id)` reads `trip_hop_ms_<line_id>` into `trip_hop_ms`, and
  every other field under its own name, as Dart's `fromTunables` does.
  - It refuses any field that is missing or not an integer.
  - `TripParams.from_json` refuses unknown keys.
  - The bounds of M01 data-model "TripParams" raise `bad_params` at start.
- The solver plays every trip with `from_tunables(bundled, trip.line_id)`. Live overrides are out of
  scope (spec Assumptions, hand-over to B10).

**Why.** The backend image's build context admits only `backend/`, `tools/content_kit/` and now
`tools/solver/`. A packaged copy keeps the image free of `apps/`, and the drift check keeps it
honest.

**Rejected.**

- **Reading the app's file at runtime.** It isn't in the image, and adding `apps/mobile` to the
  build context would ship the app's assets into the backend image.
- **A copy inside the content kit.** The tunables aren't content. The solver is their only Python
  reader.

## R6. Replay of untrusted input

**Decision** (FR-007 to FR-009, contracts/mirror.md §4).

`replay_untrusted(document)` takes the JSON tuple and checks, in this order:

1. **The shape.** The four keys are present, and every number is an integer. Strict JSON is read with
   the content kit's loader, so `NaN`, floats and duplicate keys are refused. The refusal is
   `bad_input`.
2. **The definition.** It must pass `wassal_content.validate.document_findings("trip", …)` (schema,
   local references, V-T8 and V-T9). The refusal is `bad_definition`, with the findings.
3. **The params.** `TripParams.from_json` (`bad_params`).
4. **The log.**
   - It is a list of at most 1,201 entries.
   - Each entry is `[t_ms, name, …args]` with a known name and the arguments of
     replay-and-fixtures.md §1.
   - `t_ms` is a non-negative multiple of 33, at most 1,500,000.

   The refusal is `bad_log`, with the entry's index.
5. **The replay.** It refuses as Dart's `RebuildRefused` does, with the same reasons: `the trip is
   refused` (with M01's start codes), `t_ms goes down along the log`, and `an entry is rejected`
   (with its index and the rejection code).

The cost is bounded:

- the log is capped;
- every accepted command applies at an existing step;
- stepping stops when the trip leaves `running`;
- the params' bounds cap a trip at 1,500 s, about 45,500 steps;
- a `t_ms` past the end makes the next entry `wrong_status`, so the replay is refused.

**Why.** B08 will feed it logs that players sent. Every check happens before any stepping, and nothing
in the input can make the work grow past the longest trip.

**Rejected.** Trusting the shapes because the app made them. The app can be modified, and a crash in a
Celery worker is a cheap denial of service.

## R7. The idealized player

**Decision** (FR-016, FR-017, contracts/solver.md §1–§2).

- **Information.** It reads the whole mirror state: every balance, who paid and every token. It
  answers claims and disputes with the truth. A false claimer is insisted on, a truthful one isn't,
  and a dispute names the one who paid.
- **Decisions** (the timeline's vocabulary):
  - `collect_fare(p)`: a tap that asks for a fare;
  - `collect_rest(p)`: a tap after a fare increase leaves `balance < 0`;
  - `wake(p)`: a tap on a sleeper;
  - `call(p)`: two taps on a passenger in headphones;
  - `give_change(p, pieces)`: picks, then a send;
  - `request_break(d)`;
  - `pick_up(token)`: collecting a dropped bundle;
  - `answer_claim(p, insist)`, `answer_dispute(id, paid)`, `answer_change_request(p, agree)`;
  - `wait`.
- **Only exact change.** Over-change is a mistake (it loses the third star). Short change leaves
  the passenger owed, so it can't prevent a fight, and it costs reputation. Neither can be part of
  a 3-star run that exact change can't match, so the solver doesn't consider them. That cuts the
  branching a lot. A send to a passenger who isn't owed is excluded for the same reason.
- **No aids.** No booster, no `Revive`, no `UndoLastSend`, no `Abandon`, as the spec says.
- **Timing.** The reaction time is 600 ms (backend §10.2). The tap time is 198 ms: six steps, about
  five taps a second, a fast but human pace.
  - A decision starts at the first step that is at least one reaction time after the last command
    of the decision before it, and at least one reaction time after the step where it became
    possible. Times round up to the next 33 ms step: 600 ms becomes 627 ms.
  - The commands of one decision are one tap time apart.
  - If the mirror rejects a command partway through a decision (the passenger got off, say), the
    branch ends. It isn't repaired.
- **Change request.** Both answers are searched. Agreeing spends tray pieces (§14.4), and declining
  costs reputation but not a star.

**Why.** It is the player backend §10.2 describes. Searching only what can lead to 3 stars keeps the
search narrow without making a solvable trip look unsolvable.

**Rejected.**

- **Raw taps as the search unit.** The branching would be in the dozens per step.
- **Modelling forgetfulness.** Clarifications kept perfect information. Memory counts in the score
  instead (R11).
- **A tap time of 0, as the hand-written fixtures do.** A five-coin change then takes no time, which
  makes some trips look solvable that no person could play.

## R8. The search, its budget and the safety cap

**Decision** (FR-018 to FR-022, contracts/solver.md §3).

- **Depth-first over decisions**, with fixed move ordering:
  1. forced answers come first: claims, disputes and picking up dropped money;
  2. then the passenger whose stop comes soonest;
  3. for a change, compositions with the fewest pieces first. Among equal counts, the one that
     keeps the most small pieces (50s and 100s) in the tray comes first;
  4. then `wait`.
- **Wait points.** `wait` advances to the next step where the set of possible decisions changes: a
  fare lands, someone wakes or dozes, a station is reached, a choice opens, or a break completes.
  For a sleeper or a passenger in headphones, the solver also tries the latest step that still
  wakes or calls them in time for their token's pass or their stop, computed from the schedule and
  the params.
- **Pruning.**
  - **Star loss.** A branch stops at the first step after which the trip can no longer get 3 stars:
    a fight, a mistake, or `failed`.
  - **Transpositions.** At every decision point, the canonical state plus the earliest next
    decision time is hashed with BLAKE2b (16 bytes) into a visited table. A state already seen isn't
    explored again. The table holds at most `transposition_cap` entries; once full, it stops
    growing. That is deterministic either way.
- **The effort budget** counts mirror steps simulated, over all branches. It started at 1,000,000 and
  was calibrated during implementation to 1,500,000, so that a full-budget search costs about 30 s
  on the staging host (R19). When it runs out, the search ends `budget_spent`.
- **Ends:** `found`, `exhausted`, `budget_spent`, `safety_cap` and `internal_error`.
- **The safety cap.**
  - It is 180 s of wall time per trip, checked every 1,024 steps. It fires only when something is
    wrong, and is reported apart from the budget (FR-022).
  - Memory is bounded by construction: one cloned state per depth level, plus the visited table of
    16-byte digests. A test measures peak memory under the full budget, and it must stay under
    64 MB (R14).
- **The best run** for a trip that isn't solved: the branch with the most stars at its end, then the
  latest first loss, then the first found. When a branch is cut at its first loss, the solver
  finishes it with the same move ordering to learn its final stars.
- **Confirmation** (FR-020). A found run is replayed from the start through `replay()`. Anything but
  3 stars gives `internal_error`.

**Why.** Authored trips are meant to be solvable, so a good first move ordering usually finds a run on
the first dive. Cutting at the first star loss removes almost every bad branch within a few
hundred steps. Counting steps rather than seconds makes every verdict machine-independent (R9).

**Rejected.**

- **Breadth-first or A\*.** They keep thousands of states alive, which a 512 MB worker can't afford.
- **Monte Carlo tree search.** It is random, unless it is seeded, and even then results would depend
  on time cut-offs.
- **A time budget.** Verdicts would depend on how fast the host is, and a busy worker would fail
  trips.

## R9. Determinism

**Decision.**

- Nothing in a verdict reads a clock. Only the safety cap does, and it is reported as its own end.
- No `set` is iterated. No ordering depends on `hash()`. Dicts are built in fixed orders.
- Visited-table membership is by digest equality, which is the same under any `PYTHONHASHSEED`.
- Results are written as canonical JSON (`wassal_content.canonical`).

Tests:

- each sample trip is solved twice in-process, and in two subprocesses with different
  `PYTHONHASHSEED` values, and the canonical results must be byte-identical;
- `wassal-solver bench --digest` prints one hash over every result in the bench corpus. CI and the
  staging host must print the same one (SC-005; contracts/cli.md).

**Why.** FR-021 and SC-005. It is also what makes the reuse of R14 safe.

## R10. Verdicts, what cost a star, and the timeline

**Decision** (contracts/solver.md §4).

- **The verdict.** `solved`, `not_solved` or `refused`, with the end of R8.
- **The first loss.** `{kind, t_ms, passenger_id, station_id, detail}`:
  - `kind` is `fight`, `mistake` or `failed`;
  - `detail` is the mistake's or the fight's cause, read from the mirror's counters at that step.
- **The timeline.** One entry per decision: `{t_ms, decision, passenger_id?, amount_piasters?,
  pieces?, note?}`. For a run that isn't solved, a last `lost_star` entry. It is derived from the
  decisions and the mirror state (FR-006).
- **The run.** The command log, with its `command_log_hash` as `run_hash`.

**Why.** An author needs to know who, where and when, in game terms. The run hash lets a staging
result be compared with CI's without shipping the logs.

## R11. The difficulty score

**Decision** (FR-023 to FR-027, contracts/solver.md §5).

- **Inputs**, all integers, taken from the trip and its 3-star run:

  | Input | Value |
  | --- | --- |
  | `owed_at_once` | The most passengers owed change at the same step. |
  | `change_pieces` | Every piece the run sends as change. |
  | `blockers` | Pairs (payer, blocker): a sleeper or headphones passenger who sits on the payer's chain to the driver. |
  | `breaks` | `RequestBreak` decisions in the run. |
  | `tightness_ms` | `max(0, slack_ref_ms − least slack)`. The slack is the time from a change's arrival to its passenger's stop. |
  | `variety` | Distinct archetypes plus distinct authored event kinds. |

- **Points.** For each input, `min(cap, max(0, value − free) × per // unit)`. The score is
  `min(100, sum of points)`.
- **Settings.** Every `free`, `per`, `unit` and `cap`, and `slack_ref_ms`, is a solver setting (R12).
  The initial values are in contracts/solver.md §5. They are calibrated during implementation so
  that the sample pack scores inside its bands (FR-042): `line_hay` 0–30 and `line_gamaa` 20–55.
- **Monotonic by construction.** Every term is non-decreasing in its input (FR-025). A Hypothesis
  property test checks it.
- **The band check.** `min ≤ score ≤ max`. Outside the band is a `V-Z5` warning (Clarifications Q1).
  It isn't stored with the result: it is made each time a result is used, against the line's band
  at that moment. A result is reused by `input_key`, which doesn't cover the band (R14).
- **Reported per input:** its value and its points, which are its share.

**Why.** These are backend §10.2's inputs, plus the product spec's variety. A capped linear sum is
easy to explain on the preview page and to calibrate after the playtests. Integers keep the score
identical on every machine.

**Rejected.**

- **A learned or weighted-float model.** There is no data yet. Floats would also break FR-026.
- **Scoring from the trip alone, without the run.** Owed-at-once, slack and breaks depend on how the
  trip is played.

## R12. Solver settings and the fingerprints

**Decision.**

- **The settings** live in `wassal_solver/data/settings.json`, a single integer-only JSON record,
  loaded into a frozen `SolverSettings` dataclass. It holds:
  - `reaction_ms`, `tap_ms`, `effort_budget_steps`, `safety_cap_seconds` and `transposition_cap`;
  - `report_reaction_ms`;
  - the score's table (contracts/solver.md §5).
- **`settings_version`** is the first 16 hex digits of the SHA-256 of the record's canonical JSON.
  Nobody bumps it by hand.
- **`solver_fingerprint`** is the first 16 hex digits of a SHA-256 over:
  - every `.py` and `.json` file of the installed `wassal_solver` package, in sorted path order;
  - the packaged `capabilities.json`.

  Any change to the mirror, the search, the score or the data changes it.
- **`params_fingerprint`** is the first 16 hex digits of the SHA-256 of the canonical params.
- **Constitution VIII.** The settings decide which trips pass validation, and the game never reads
  them. They aren't balancing numbers the game runs with, so they get no Remote Config key and no
  `LiveSetting` copy. They do follow VIII's intent: data in one record, never constants scattered
  through code.

**Why.** Hand-bumped versions get forgotten, and a forgotten bump would make R14 reuse a stale result.
A content hash can't be forgotten.

**Rejected.**

- **Making the settings tunables.** They don't change how any trip plays. A Remote Config key would
  imply the app reads them.
- **The package version string as the fingerprint.** It is only as good as the person bumping it.

## R13. The solver stage in B04's pipeline

**Decision** (contracts/content-pipeline.md).

- **The stage's interface** (`apps/content/services/stages.py`) widens from `list[Finding] | None` to
  a `SolverOutput(findings, trips, meta) | None`.
  - `NoSolver` returns `None`.
  - `StandInSolver` returns findings `[]` and trips `[]`.
  - The real stage is `apps.content.services.solver_stage.SolverStage`.
- **`CONTENT_SOLVER_STAGE`** gains the value `solver`.
  - The default in strict environments (staging, prod) becomes `solver`; dev and test keep
    `stand_in`.
  - The settings check still refuses `stand_in` in strict environments.
  - The owner sets nothing. Staging's env file leaves the variable unset (B04 owner actions).
  - Production never builds, so on production the value only satisfies the check.
- **For each trip**, in pack order:
  1. Read the params of its line from the bundled tunables.
  2. Look up a finished `SolverRun` with the same input key (R14). If there is none, solve the trip
     and store the result.
  3. Touch the pack's `updated_at`. That is the heartbeat (R14).
  4. Emit findings:

     | Code | Severity | When |
     | --- | --- | --- |
     | `V-Z1` | error | Not solved |
     | `V-Z2` | error | Refused |
     | `V-Z3` | error | Stopped by the safety cap |
     | `V-Z4` | error | Internal error |
     | `V-Z5` | warning | Score outside the band |

  Every finding has `entity: "trip"`, the `trip_id`, the path `$.trips[i]`, and an English message
  for staff.
- **The report.** `stages.solver` gains `trips` (one summary per trip, contracts/content-pipeline.md
  §3) and `meta` (`solver_fingerprint`, `settings_version`, reused and solved counts).
- **The release record** gains `solver: {solver_fingerprint, settings_version, trips: […]}`, a
  compact summary of about 200 bytes per trip, with no runs and no staff names. A 50-trip pack adds
  about 10 KB, well under the 64 KB `MAX_RELEASE_BYTES`. `warnings` carries the `V-Z5` findings as
  usual.
- **A solver `warning` is accepted.** `services/publish.py` and `services/promote.py._passed` now
  accept solver `passed` or `warning`. B04's contracts say so (pack-delivery.md "Release record",
  admin.md "Validation report"). Production must run this release before it promotes a pack with a
  warning (owner actions).
- **Internal errors.** An exception on one trip is logged with `logger.exception` (Sentry), and the
  trip gets `V-Z4`. The other trips go on (FR-033).

**Why.** It is the plug-in point B04 left for this. The findings flow into B04's report and release
record unchanged. Only two guards learn that a warning is a pass, which Clarifications Q1 requires.

**Rejected.**

- **Keeping the result `passed` while adding warning findings.** It would break `Report.add_stage`,
  which derives `warning` from warning findings, and the report would then contradict its findings.
- **Production re-solving on promotion.** It would take the production host's single core for up to
  30 minutes while it serves players (spec Assumptions).

## R14. Reuse, the heartbeat and the preview: the `SolverRun` table

**Decision** (data-model.md "SolverRun", contracts/content-pipeline.md §5–§6).

- **The table.** A `content.SolverRun` holds one solve. Its fields:
  - UUIDv7 `id`, `kind` (`build` or `preview`), `status` (`queued`, `running`, `done` or `failed`);
  - `input_key`, the 64-hex SHA-256 of canonical `{definition with rev 0, params, solver_fingerprint}`;
  - `trip_id`, an optional FK to the authoring `Trip` (previews), and `requested_by` (previews only,
    a staff name kept in the database, never in a pack or a release record);
  - `result` (jsonb), `created_at` and `finished_at`.

  Constraints:
  - an index on `input_key`;
  - at most one active preview per trip: a unique constraint on `trip` where `kind = preview` and
    `status` is `queued` or `running`.

  The migration only adds the table (expand-only).
- **Reuse** (FR-031). A finished run of either kind with the same `input_key` is reused, so a
  preview's result also serves the next build. `rev` is zeroed in the key because a rev bump alone
  changes nothing the solver plays.
- **The heartbeat.** The build touches `ContentPack.updated_at` after each trip. B04's sweep already
  fails builds by `updated_at`, so it now catches a build with no progress for 30 minutes, not a
  slow build. Its message changes to "no progress for 30 minutes". No migration is needed.
- **The preview.**
  - A POST from the trip's change page creates a `queued` preview run from `snapshot.trip_part(trip)`
    and the line's params.
  - A `content.tasks.solve_trip` job then runs it on the `content` queue, with `bind=True`,
    `acks_late`, `reject_on_worker_lost` and retries on `OperationalError`, like B04's jobs.
  - The job first runs `document_findings("trip", …)`. If that finds errors, it stores them as a
    `failed` result without solving (FR-036).
  - The sweep also fails preview runs left `running` for over 30 minutes.
- **Concurrency.** A build solves its trips one after another, in its own job, without fanning out.
  The worker's second slot stays free for previews and other jobs (FR-047).
- **Memory.**
  - The worker has 512 MB for two prefork children (B01 compose).
  - The solver's own peak stays under 64 MB (R8), measured by a `tracemalloc` test at the full
    budget.

**Why.**

- One table serves FR-031 (reuse), FR-037 (one preview at a time) and the preview page.
- The heartbeat keeps B04's crash detection and allows builds of 30 minutes (Clarifications Q4).

**Rejected.**

- **Raising the stale threshold to two hours.** A crashed build would then sit `running` for two
  hours.
- **Reusing results from the previous pack's report.** It doesn't cover previews, and a report isn't
  indexed by input.
- **Fanning out one job per trip.** On one core it buys nothing, and it would fill both worker slots.

## R15. Tests and coverage

**Decision.**

- **Mirror, tests first** (FR-049):
  - one test module per rules module, mirroring the Dart test layout;
  - the parity suite (R4) and the capabilities check;
  - the untrusted-replay refusals (R6);
  - guard scans (R2).
- **Solver:**
  - the sample-pack trips solve, and their runs confirm;
  - one crafted trip per fault kind of SC-004 (a change that can't be made, timing tighter than the
    reaction time, 3 stars only with an aid, a refused definition, an unsupported type, a score
    above the band, a score below it);
  - the reaction-time flip of US2 (not solved at 600 ms, solved at 100 ms);
  - the budget and safety-cap ends, with tiny settings;
  - determinism (R9).
- **Property tests** (FR-050, Hypothesis):
  - replay determinism over random valid logs of the sample trips;
  - every found run confirms;
  - the score is monotonic;
  - random malformed tuples are refused without an exception escaping, within the step bound.
- **Performance tests** (SC-008):
  - the stress fixture replays in under 5 s on the CI runner;
  - a typical 90 s sample trip replays in under 0.5 s;
  - peak memory at the full budget is under 64 MB.
- **Coverage.**
  - `pytest --cov=wassal_solver --cov-fail-under=80` for the package;
  - then `coverage report --include='*/wassal_solver/engine/*' --fail-under=90` for the mirror
    (FR-051).
- **Backend.**
  - The real stage over the sample content: every trip solved, the report and release-record
    shapes, and reuse on a rebuild.
  - Publish and promotion accept a solver warning.
  - The heartbeat keeps a long build alive, and the sweep still fails a stalled one.
  - The preview: the permission, the target role, one at a time, the failed checks, nothing
    changed.

  All against real Postgres and Valkey, with the backend kept at 80%.
- **Dart:** `solver.dart` expectations, and the coverage test knows the area.

## R16. CI

**Decision** (contracts/ci-checks.md).

- **backend.yml.**
  - **The `changes` filter** adds `tools/solver/`, `packages/trip_engine/` (a Dart rule change must
    run the Python parity) and `apps/mobile/assets/config/tunables.json`.
  - **A new `solver` job**, in `tools/solver`, runs these steps in order:
    1. `uv sync --locked`;
    2. ruff, the format check and mypy;
    3. pytest on 4 workers, with both coverage gates;
    4. `wassal-solver sync --check`;
    5. `wassal-solver parity ../../fixtures/parity`;
    6. `wassal-solver check-source ../../content/examples/sample --bands error`;
    7. `wassal-solver check-source ../../content/source --bands warning`;
    8. `wassal-solver bench --digest`, which prints the hash for SC-005.

  - **The `backend` summary job** needs `solver`. The required checks stay `backend` and `mobile`,
    so the owner changes no branch protection.
- **The image.**
  - `.dockerignore` admits `tools/solver/` and excludes `tools/solver/tests`.
  - The Dockerfile binds `tools/solver` at `/tools/solver` next to the content kit, for `uv sync`.
  - `backend/uv.lock` gains the path dependency.
- **mobile.yml** doesn't change: `fixtures/` already starts it, so the Dart suite replays the
  solver fixtures.

**Why.** The B04 pattern: new steps inside the required workflows, so no branch-protection change.

## R17. The balancing report and the bench

**Decision** (FR-043, FR-044, contracts/cli.md).

- **`wassal-solver report <layout | pack.json.gz> [--csv FILE]`** prints one row per trip, in pack
  order, with these columns:
  - `trip_id`, the verdict, the stars and the score;
  - the six inputs;
  - `breaks`;
  - `slack_ms` per station, as `station:ms` pairs;
  - for each of `report_reaction_ms` (900 and 1,200 ms), that run's stars, fights and mistakes.

  The table goes to standard output, and `--csv` writes the same rows as CSV with a header. The
  output is byte-identical for the same input.

  Slower-player runs exist only here (Clarifications Q3). They play the best run found with the
  slower reaction time, which takes as many fresh searches as there are slower times. That is
  acceptable for a command run by hand.
- **`wassal-solver bench [--digest]`** solves the packaged bench corpus, `data/bench/*.json`. That is
  50 trips across both MVP lines, made once from the sample trips with seeded variations (more
  passengers, tighter trays, shifted stations) and committed. It prints the time per trip and in
  total, and with `--digest`, one SHA-256 over every canonical result.
  - The corpus is validated in the solver's tests with `document_findings`.
  - It is what measures SC-007 on the staging host (`docker compose exec worker wassal-solver
    bench`), and compares results across hosts for SC-005.

**Why.** SC-005 and SC-007 need the MVP's volume on the staging host before 50 real trips exist. A
fixed corpus measures the same work everywhere.

## R18. Documents and owner actions

**Decision.** In the same change (FR-052):

- **backend §10:**
  - what the mirror covers (R3);
  - the idealized player and its timing (R7);
  - the search and its ends (R8);
  - the score's inputs (R11);
  - the stage, the codes and reuse (R13, R14);
  - the preview;
  - §10.3's fallback, now for replay only.
- **backend §9.1:** a solver warning doesn't block publishing.
- **mobile §7.10:** `tools/solver` now exists, and both suites are required.
- **`RULES.md`'s opening** (R3).
- **`CLAUDE.md`:**
  - the solver's command table;
  - `tools/solver/` no longer "arrives with B05";
  - a rule change edits both engines;
  - the parity rules.
- **`fixtures/parity/README.md`** (the `solver` area and the Python commands) and
  **`content/source/README.md`** (CI re-solves).
- **B04's contracts**, three surgical edits: `environment.md` (the `solver` value and its default),
  `pack-delivery.md` (`warning` is allowed for the solver stage, and the `solver` key in the record),
  and `admin.md` (the same rule for the validation report). Each edit is marked "(B05)".
- **`docs/owner-actions.md`**, a B05 section:
  - **Before merge:** none.
  - **After merge:**
    1. Deploy production with this release before the first promotion of a pack that has a warning
       (production must accept solver warnings).
    2. On staging, run `wassal-solver bench --digest` in the worker container, and compare it with
       CI's digest (SC-005) and its total time with SC-007.
    3. Preview `line_hay.01` on staging (SC-006).
    4. Then B04's T107 live checks, items 3–7, whose first publish is this feature's SC-012.
- **`docs/delivery-plan.md`'s Progress**, when this merges.

## R19. Performance estimates

**Decision.** These are the targets the tests and the bench hold the implementation to:

| Measure | Target | Estimate | Measured (i5-10500H laptop, CPython 3.13) |
| --- | --- | --- | --- |
| Replay of the longest trip (45,500 steps, full vehicle), CI runner | < 5 s (SC-008) | 1.5–3 s at 30–60 µs per step in CPython 3.13 | 0.9 s |
| Replay of a 90 s trip (2,727 steps) | < 0.5 s | about 0.1 s | 0.02 s (`line_gamaa.02`, 100 s) |
| Full-budget search (1,500,000 steps), staging host | ≈ 30 s | 30–60 µs per step, plus a clone at each decision point | about 11 µs per step: 17 s; 25–33 s estimated on the 1-OCPU A1 host |
| Sample trip found on the first dive | < 1 s | one or two simulations' worth of steps | 0.02–0.04 s, 1,667–3,031 steps |
| 50-trip bench, staging host | < 30 min (SC-007) | solvable trips mostly found in the first dives. Only trips that aren't solved use the full budget. | 20 s, all 50 solved |
| Rebuild with no trip changed | < 2 min (SC-007) | lookups only | lookups only |
| Peak memory of a full-budget search | < 64 MB (FR-047) | the visited table at its cap | 0.4 MB (tracemalloc) |

**Calibration (T117).** `effort_budget_steps` is raised from 1,000,000 to 1,500,000. Only a trip
that isn't solved spends it, and an A1 core runs CPython at about 0.55 to 0.7 of this laptop's
speed, so a full-budget search costs about 25–33 s there, the 30 s envelope. Every solvable sample
and bench trip is found inside it, with room: the sample trips need at most 3,031 steps, and the
costliest bench trip, `line_gamaa.56`, 840,854 (56% of the budget; 84% of the old one). The owner's
`bench` run on staging (owner actions, B05) gives the real speed. If a full-budget search there
misses the envelope, a later PR moves the budget, which changes `settings_version`.

If the measured staging speed misses these, either the budget is lowered or the mirror's hot loop is
optimized. An optimization must keep every step's state exactly as Dart computes it, so the parity
suite still passes unchanged. Either way, the solver fingerprint changes, so nothing stale is
reused.

## Handed to later features

- **B08:**
  - verify results with `replay_untrusted` (R6), with the server's own definition and params,
    never the client's, and the body capped before it is read (contracts/mirror.md §4 "What the
    caller must do");
  - build and pick challenges with `solve` and the score;
  - a verdict is tied to `settings_version` and `solver_fingerprint`;
  - any seed is fine (R3).
- **B10:** before a live tunable change that affects trips, re-solve the current pack with the new
  values, via `solve` with explicit params.
- **B04:** its T107 live checks can run once this is deployed (owner actions).
- **After step 5's playtest:**
  - calibrate the score's table;
  - decide whether `V-Z5` becomes an error;
  - decide whether a slower-player gate is wanted (spec Assumptions).
