# Feature Specification: Solver and Parity (B05)

**Feature Branch**: `005-b05-solver-parity`

**Created**: 2026-10-20

**Status**: Draft

**Input**: User description: "start feature 005 (next feature in docs/delivery-plan.md)". Feature 005
in `docs/delivery-plan.md` is B05, step 3: "Solver and simulator, difficulty scoring, parity fixtures
in CI". It depends on B04 (merged in #3 and #4) and on the M01 fixtures (merged in #5). Sources:
docs/architecture-backend.md §10 (with §9.1, §11.1 and §16); docs/architecture-mobile.md §7.10;
`packages/trip_engine/RULES.md`; `fixtures/parity/` and M01's
`specs/004-m01-trip-engine/contracts/replay-and-fixtures.md`; `content/engine/capabilities.json`;
docs/product-spec.md «الفوز والنجوم», «أنواع الركاب» and «المساعدات». Resolve: nothing open.
Handed over from B04: supply the solver stage at B04's plug-in point, re-solve `content/source` in
CI, and make the first live publish on staging possible, with B04's live checks SC-007, SC-008 and
SC-012. Handed over from M01: mirror `RULES.md`, read `capabilities.json`, make the Python suite
reproduce every `fixtures/parity/*.json`, and add that job to CI. Done when: the Python suite
reproduces every M01 fixture exactly and CI fails on any mismatch, and every authored trip is proven
3-star solvable before it is published.

## Clarifications

### Session 2026-10-20

- Q: When a trip's difficulty score falls outside its line's band, should that stop the pack from
  being published? → A: No. It is a warning, shown in the build report and the release record, and
  publishing and promotion go ahead. Only a trip that can't be 3-starred blocks a pack. The score
  has no playtest calibration yet, and the owner's judgement of a trip comes first (FR-027).
- Q: Should the Python mirror reproduce only what decides a trip's result, or also the event stream
  and speech the trip screen shows? → A: Results only: state, results, the fingerprint, rejections
  and refusals. No result depends on events or speech, and no MVP server feature reads them.
  `RULES.md` is updated to say the Dart tests alone check events and speech (FR-006).
- Q: Besides being 3-starable by a fast, near-perfect player, should a trip also have to be
  finishable by a slower player before it can be published? → A: No. How slower players fare is in
  the balancing report only; builds don't play trips at slower reaction times, and nothing blocks or
  warns on it. A gate can be considered after step 5's playtest (FR-043).
- Q: How long may the solver check take for a full MVP-sized pack (50 trips) on the staging host?
  → A: 30 minutes. The effort budget is sized for about 30 s of search per trip on average, so few
  solvable trips fail for lack of search; authors get faster feedback from the preview (SC-007).

## User Scenarios & Testing *(mandatory)*

This feature has one screen of its own, the trip preview in staging's admin. Its users are:

- **Content authors** on staging, who learn whether a trip can be played to 3 stars, and how hard it
  is, while they write it.
- **Publishers**, who can publish only a pack whose every trip passed (B04 FR-022).
- **The owner, as game designer**, who reads the difficulty scores and the balancing report to tune
  each line's curve.
- **Developers who change trip rules.** From this feature on, a rule change has to keep both engines
  and the fixtures in step, or CI blocks it.
- **Later server features.** The daily challenge (B08) builds trips with the solver and verifies
  players' results by replaying them through the mirror. Leagues (B13, phase 3) do the same.

Players never see this feature. What they get from it: no trip they are served is impossible to
3-star, and a result the server checks is judged by the same rules they played.

Terms used throughout:

- **Engine**: the Dart trip engine in `packages/trip_engine` (M01).
- **Mirror**: the Python copy of the trip rules in `tools/solver`, reproducing `RULES.md`.
- **Replay tuple** `(definition, seed, params, command_log)` and **fingerprint**
  (`command_log_hash`): as in M01. A tuple decides a trip's result completely.
- **Run**: a command log that plays a trip from its start to its end.
- **Idealized player**: the player the solver plays as. It sees and remembers the whole trip, but it
  needs time to react, and it uses no aids (FR-016, FR-017).
- **Decision**: one meaningful player move, such as building a change and sending it, waking a
  sleeper, or answering a claim. One decision can take several commands.
- **Verdict**: the solver's answer for one trip: *solved* (a 3-star run was found), *not solved* (no
  3-star run was found), or *refused* (the trip can't be played at all).
- **Effort budget**: how much searching the solver may do for one trip. It is counted in work done,
  not in seconds, so the verdict doesn't depend on how fast the machine is.
- **Difficulty score**: a whole number from 0 to 100 that rates a trip. Each line has a difficulty
  band (B04's line schema) that its trips should fall in.
- **Solver settings**: the reaction and tap times, the effort budget, the safety cap, the score's
  weights and the balancing report's slower reaction times (FR-046).

### User Story 1 - The mirror reproduces every parity fixture (Priority: P1)

A developer runs the Python suite over `fixtures/parity/`. For each fixture, the mirror replays the
tuple and gets exactly its `expected_result`, fingerprint included. CI runs this check next to the
Dart suite on every change that could affect a trip's outcome, and a mismatch in either language
blocks the merge.

**Why this priority**: Constitution III says the feature that creates `tools/solver` must reproduce
every existing fixture before it merges. Every other story plays trips through the mirror, and B08
will trust it to judge players' results.

**Independent Test**: Run the mirror over the 55 fixtures on `master`: every one matches, the
longest-trip stress fixture included. Change one rule in the mirror only, for example the
exact-change reward: CI fails, naming each failing fixture, the first field that differs and both
values. Revert it, and make the same change in the Dart engine only: CI fails again. Make the change
in both engines and update the fixtures: CI passes.

**Acceptance Scenarios**:

1. **Given** any fixture in `fixtures/parity/`, **When** the mirror replays its tuple, **Then** the
   result equals `expected_result` field for field, `command_log_hash` included.
2. **Given** a change to a rule in only one of the two engines, without updated fixtures, **When** CI
   runs, **Then** it fails and the change can't merge.
3. **Given** a change to the fixtures, either engine, the rules reference, the bundled tunables or
   the content schemas, **When** CI runs, **Then** both the Dart and the Python suite run.
4. **Given** a tuple the engine refuses (a refused definition, time going backwards along the log, an
   entry the rules reject), **When** the mirror replays it, **Then** it refuses it too, with the same
   reason.
5. **Given** `content/engine/capabilities.json`, **When** CI compares it with what the mirror
   supports, **Then** the passenger types, events and event parameters are the same, and any
   difference fails CI.

---

### User Story 2 - Prove a trip can be played to 3 stars (Priority: P2)

Given a trip and its params, the solver plays as the idealized player and searches for a run that
ends with 3 stars. When it finds one, it returns that run, and replaying the run from scratch through
the mirror gives 3 stars. When it doesn't, it reports the best run it found: its stars, and the first
thing that cost a star (a fight at a station, a mistake, a lost fare, or reputation running out), with
the passenger, the station and the time. The author then knows what to fix.

**Why this priority**: Constitution VII requires every trip to be 3-star solvable before it is
published. Until this exists, staging can't publish at all (B04 FR-022).

**Independent Test**: Solve each sample-pack trip: each one is solved, and its run replays to 3 stars
in both engines. Solve a trip whose tray can never make one passenger's change, with no break allowed:
not solved, and the report names that passenger. Solve a trip in which two deliveries must land closer
together than the reaction time: not solved at the default 600 ms, and solved when the reaction time
is set to 100 ms.

**Acceptance Scenarios**:

1. **Given** a sample-pack trip and the bundled params for its line, **When** it is solved, **Then**
   the verdict is solved and the run replays to 3 stars in the mirror and in the engine.
2. **Given** a trip that can reach 3 stars only with a booster, a revive or an undo, **When** it is
   solved, **Then** the verdict is not solved.
3. **Given** a trip whose 3 stars need a break request («حد معاه فكة؟»), **When** it is solved,
   **Then** the verdict is solved. Asking for a break is part of playing, not an aid.
4. **Given** the same trip, params and solver settings, **When** it is solved again, on the same
   machine or on another, **Then** the verdict and the run are identical every time.
5. **Given** a trip for which the effort budget runs out, **When** it is solved, **Then** the verdict
   is not solved, the report says the budget ran out (rather than that every option was tried), and
   it shows the best run found.
6. **Given** a trip the engine refuses, or one that uses a passenger type or event the mirror doesn't
   support, **When** it is solved, **Then** the verdict is refused, with the reason, and the solver
   doesn't guess.

---

### User Story 3 - Score a trip's difficulty against its line's band (Priority: P3)

For every solved trip, the solver computes a difficulty score from 0 to 100. The score comes from
how many passengers are owed change at once, how many pieces each change takes, how many blockers sit
on the passing chains, how many break requests the trip needs, how little time there is between the
earliest possible delivery and each station, and how many passenger types and events the trip mixes.
The report shows the score with each input's value and its share of the score, and checks the score
against the line's band.

**Why this priority**: Backend §10.1 makes "sits in its line's band" part of validation, and B04's
solver stage includes it (B04 FR-021). The score is also how B08 will pick daily challenges.

**Independent Test**: Score the sample pack. Every `line_hay` trip falls within 0–30 and every
`line_gamaa` trip within 20–55, and each score lists its inputs. Score a `line_hay` trip with four
passengers owed at once and little time slack: it scores above 30 and gets an out-of-band warning.

**Acceptance Scenarios**:

1. **Given** a solved trip, **When** it is scored, **Then** the score is a whole number from 0 to 100,
   reported with every input's value and share, and scoring it again gives the same score.
2. **Given** two trips that differ only in one input, for example a sleeper on a chain or less time
   before a station, **When** both are scored, **Then** the harder one doesn't score lower.
3. **Given** a score outside the line's band, **When** the trip is checked, **Then** a warning names
   the trip, its score, the band and the inputs that contribute most, and the trip doesn't block its
   pack.
4. **Given** a trip that isn't solved, **When** it is checked, **Then** it gets no score. Its verdict
   already fails it.

---

### User Story 4 - Staging builds run the real solver stage, and publishing opens (Priority: P4)

When a pack is built on staging, the solver stage solves and scores every trip in it. The pack's
report shows each trip's verdict, stars, score and band, and the solver settings used. The stage
passes when every trip is solved, and the pack can then be published (B04 FR-022). A trip outside
its band adds a warning but doesn't stop the pack. This makes the first live publish on staging
possible, which in turn unblocks B04's live checks.

**Why this priority**: It is the second half of the delivery plan's "done when", and it ends the
"not available" state that blocks every publish today.

**Independent Test**: On the local stack with the real stage, build the sample content: the solver
stage passes with a result for every trip, and the pack can be published. Add an unsolvable trip and
build again: the stage fails, the finding names that trip, and publishing is refused. Build once more
with no trip changed since the last build: the earlier verdicts are reused, the report says so, and it
is otherwise identical.

**Acceptance Scenarios**:

1. **Given** a pack whose every trip is solved, **When** it is built, **Then** the solver stage
   passes and the pack can be published.
2. **Given** a pack in which one trip isn't solved, **When** it is built, **Then** the solver stage
   fails with a finding for that trip, the other trips' results are still reported, and publishing
   is refused.
3. **Given** a pack whose every trip is solved but one scores outside its band, **When** it is built
   and then published and promoted, **Then** the report and the release record carry a warning for
   that trip, and neither the publish nor the promotion is refused.
4. **Given** staging configured with the real stage, **When** any pack is built, **Then** its solver
   stage is never "not available". The pass-all stand-in stays refused on staging and production
   (B04).
5. **Given** a published pack, **When** its release record is read, **Then** it carries the solver
   stage's result for every trip, the fingerprints of the solver settings, the solver version and
   the params used, and no staff names.
6. **Given** the background worker restarts in the middle of the solver stage, **When** the build is
   looked at, **Then** it is marked failed and can be started again. No half-validated pack looks
   valid (B04 edge cases).
7. **Given** production, **When** a pack is promoted, **Then** production doesn't run the solver, and
   still accepts only a release record whose solver stage passed (B04 promotion, unchanged).

---

### User Story 5 - Preview one trip in the admin while writing it (Priority: P5)

On a trip's page in staging's admin, an author asks for a preview. In the background, the solver
solves and scores the trip as it is written at that moment. For a typical trip the result is on the
page within a minute: the verdict, the stars, the score against the line's band with its inputs, and
the run as a timeline of when each decision happens, what it is, and which passenger and amount it
concerns. For a trip that isn't solved, the best run's timeline ends at the moment a star was lost.

**Why this priority**: Without it, an author learns that a trip is unsolvable only by building the
whole pack. B04 left the admin preview to B05.

**Independent Test**: On the local stack, preview `line_hay.01`: it is solved, its score is within
0–30, and the timeline shows each delivery. Change its tray so that one change can't be made and
preview again: not solved, naming the passenger and the station. The trip's content, its `rev` and
the pack history are the same before and after.

**Acceptance Scenarios**:

1. **Given** a staff user with authoring permission, **When** they open a trip on staging, **Then**
   they can start a preview. A staff user without it can't.
2. **Given** a trip that fails the schema, reference or capability checks, **When** it is previewed,
   **Then** the preview shows those errors and doesn't run the solver.
3. **Given** a preview already running for a trip, **When** it is asked for again, **Then** no second
   one starts, and the page shows the one that is running.
4. **Given** production's read-only admin, **When** a trip is opened, **Then** no preview is offered.
5. **Given** any preview, **When** it finishes, **Then** nothing changed: no content, no `rev`, no
   pack and no build.

---

### User Story 6 - CI re-solves published and sample content, and the engine replays the solver's runs (Priority: P6)

On every change that could affect whether a trip can be solved, CI re-solves every trip in
`content/source` (once it holds a pack) and in the sample pack. A trip that is no longer solved fails
CI. The solver's 3-star runs for the sample-pack trips are kept as parity fixtures, so the Dart engine
also replays runs that the Python solver found.

**Why this priority**: The constitution's CI gates include "a fresh solve of every published trip".
Solver-made fixtures check the engines against each other on runs no person wrote.

**Independent Test**: Lengthen the bundled hop time until a sample trip can't be 3-starred any more:
CI fails and names the trip. Revert it: CI passes. Run the Dart fixture check: the solver's fixtures
pass.

**Acceptance Scenarios**:

1. **Given** a change that leaves a trip in `content/source` unsolvable, **When** CI runs, **Then** it
   fails, naming the trip and the pack version.
2. **Given** a change to the scoring that moves a published trip out of its band, **When** CI runs,
   **Then** it reports it without failing. A published pack can't change, so the fix goes into the
   next pack.
3. **Given** the sample pack, **When** the Dart suite runs, **Then** it reproduces the solver fixture
   of every sample trip.
4. **Given** `content/source` holds no pack yet (as today), **When** CI re-solves, **Then** it solves
   the sample pack and says that `content/source` is empty.

---

### User Story 7 - A balancing report for the designer (Priority: P7)

For a pack or a content layout, the owner runs a balancing report with one row per trip: the
verdict, the stars, the score and its inputs, the break requests the run used, the time slack at each
station, and how the trip goes for slower players. For that last part, the solver plays again with
longer reaction times (900 and 1,200 ms by default) and reports the stars, fights and mistakes of its
best run at each. The owner uses the report to order a line's trips into a curve.

**Why this priority**: Backend §10.1 lists balancing reports among the solver's uses. They help tune
the game after the first playtests, but nothing is blocked without them.

**Independent Test**: Run the report on the sample pack: five rows in pack order, each with every
column. Run it again: the output is identical.

**Acceptance Scenarios**:

1. **Given** a content layout or a pack file, **When** the report runs, **Then** it has one row per
   trip, in pack order, with every column above.
2. **Given** the slower reaction times in the solver settings, **When** the report runs, **Then**
   each row shows the stars, fights and mistakes at each of them.
3. **Given** the same input and settings, **When** the report runs twice, **Then** both outputs are
   identical, both as a readable table and as a spreadsheet file.

---

### Edge Cases

- **A trip that needs superhuman timing**, such as two deliveries less than a reaction time apart:
  not solved at the default settings. That is the point of the reaction time.
- **A trip with a false claimer or a payment dispute**: the idealized player knows who paid, so it
  always answers right. A real player has to remember, which the score counts as difficulty, not as
  impossibility.
- **A change request («معاك فكة؟»)**: the solver may agree or decline. Declining costs reputation,
  not a star, so both are valid moves.
- **Events that move the schedule** (traffic, open road, `drop_me_here`, roadside pickups): the solver
  plays them as they come. The time slack is measured on the shifted schedule.
- **A trip with nothing to do**, where nobody needs change: solved with a score near 0. That is valid
  for a first tutorial trip.
- **The solver itself has a bug on one trip**: that trip fails with an internal error, the other trips
  are still solved, and the details go to error monitoring, not into the author's report.
- **A solved verdict whose run doesn't replay to 3 stars**: that is a solver bug. The trip is reported
  as an internal error, never as solved (FR-020).
- **The safety cap stops a runaway search**: the trip is not solved with "stopped by the safety cap",
  distinct from an exhausted budget, and the event is logged for the developers.
- **A change to the bundled tunables** that leaves a published trip unsolvable fails CI. Shipping it
  would hand players a trip that can't be 3-starred.
- **A change to the solver settings**, such as a longer reaction time, re-solves everything in CI. If
  a published trip no longer passes, the change can't merge without a decision about that trip.
- **Two authors preview at once**: both previews run, one after the other if the worker is busy.
  Previews never hold up the queue for more than their own effort budget.
- **A replay tuple from a player** (B08 later) with an unknown command, a non-integer amount, a log of
  more than 1,201 entries, time going backwards, or params outside their bounds: refused with the
  reason, never a crash, and never more work than the longest trip the rules allow.
- **A fixture written on one side** (Dart's `update`, or the Python fixture tool): it must pass on the
  other side too, or CI fails.
- **A sample-pack trip that fails the real stage today**: it is corrected in this feature, along with
  everything that copies it (FR-042).

## Requirements *(mandatory)*

### Functional Requirements

#### The mirror

- **FR-001**: The mirror MUST implement every rule in `RULES.md` that decides a trip's state or
  result: starting a trip, the order within a step, all 13 commands with their rejection reasons and
  the 1,200-command cap, money tokens and the passing chain, fares and change, the 12 supported
  passenger types, the 8 events, stations, reputation, failing and reviving, the ending and the
  result, the fingerprint, and the tables and selection rules (`RULES.md` §1–§11, §14 and §15).
- **FR-002**: The mirror MUST follow the integer rules of `RULES.md` §15, use only integer money and
  integer time, iterate in the same fixed orders, and use no floating point, real clock, platform
  random source or I/O (constitution I and II).
- **FR-003**: The mirror MUST support exactly what `content/engine/capabilities.json` declares: the
  same passenger types, events and event parameters. A trip that uses anything else MUST be refused
  with a reason, as the engine refuses it. CI MUST fail if the mirror's supported set and the file
  differ.
- **FR-004**: The mirror MUST accept commands in the command-log format of M01's
  `replay-and-fixtures.md` (names, arguments and timestamps) and MUST accept or reject each one
  exactly as the engine does.
- **FR-005**: The mirror MUST take every params field the engine takes, with the same bounds, and
  MUST build params from the bundled tunables for a trip's line in the same way the engine does.
  Params outside their bounds MUST be refused.
- **FR-006**: The mirror MUST reproduce state and results only. It doesn't emit the engine's events
  or pick speech variants (Clarifications). Speech changes nothing but the random generator, which
  nothing else draws from (`RULES.md` §12 and §13), so neither decides a result, and no MVP server
  feature reads them. `RULES.md` MUST say this where it says the mirror reproduces the rules. The
  preview's timeline (FR-035) is built from the run's decisions and the mirror's state.

#### Replay for result checks

- **FR-007**: The mirror MUST offer a replay of a tuple to its result that other backend features
  (B08, B13) can call in-process, with no network, file or database access.
- **FR-008**: Replay MUST treat its input as untrusted. Unknown commands, wrong argument types or
  values, non-integer numbers, time going backwards, a log longer than 1,201 entries, a definition or
  params the engine refuses, and an entry the rules reject MUST each be refused with the entry and the
  reason, using the engine's refusal reasons (M01 `replay-and-fixtures.md`). Replay MUST NOT crash
  on any input.
- **FR-009**: The cost of a replay MUST be bounded by the longest trip the rules allow (1,500 s of
  logic time and 1,201 entries), whatever the input.

#### Parity in CI

- **FR-010**: A Python suite MUST replay every file in `fixtures/parity/` and compare the result with
  its `expected_result` field for field, fingerprint included. A difference MUST fail the suite,
  naming the fixture, the first field that differs and both values.
- **FR-011**: The suite MUST run in CI on every change to the fixtures, the engine, the mirror,
  `RULES.md`, the bundled tunables, `capabilities.json`, the content schemas or the generated models.
  It MUST be part of a required check, so that a mismatch blocks the merge. The Dart suite keeps
  running on the same changes (M01).
- **FR-012**: A Python fixture tool MUST check every fixture and write new fixtures in the exact form
  of `fixtures/parity/README.md`: five keys, sorted, with a two-space indent, and `expected_result`
  computed by the mirror, never typed. Rewriting the `expected_result` of an existing fixture stays
  with the Dart tool's `update`.
- **FR-013**: Every fixture the Python tool writes MUST also get its entry in the Dart suite's
  fixture expectations (M01), which pins what the fixture is about.
- **FR-014**: From this feature on, a change to any trip rule MUST update `RULES.md`, the engine, the
  mirror and the affected fixtures in the same change (constitution III).

#### The solver

- **FR-015**: Given a trip and its params, the solver MUST search for a run that the mirror plays to
  3 stars, playing as the idealized player.
- **FR-016**: The idealized player MUST know the whole trip state at every moment, including what a
  real player has to remember: who has paid, how much, and who is owed. It MUST use only the commands
  a player has without aids: `PickFromTray`, `ReturnHand`, `SendHand`, `Tap`, `ResolveClaim`,
  `ResolveDispute`, `ResolveChangeRequest`, `RequestBreak` and `CollectDropped`. It MUST NOT use a
  booster, `Revive`, `UndoLastSend`, `Abandon` or an ad. The product spec says aids make a trip
  easier but never solve it, so 3 stars stay a matter of skill («المساعدات»).
- **FR-017**: The idealized player MUST take time to act. Each decision comes at least one reaction
  time after the decision before it, and at least one reaction time after the moment it became
  possible, for example after the fare it answers reached the tray. The reaction time is 600 ms by
  default (backend §10.2). The commands that carry out one decision are at least a tap time apart.
  Both times are solver settings.
- **FR-018**: The solver MUST search over decisions, not single taps. It MUST stop when it finds a
  3-star run, when it has tried every decision sequence it considers, or when the effort budget is
  spent.
- **FR-019**: The solver MUST return one of three verdicts:
  - **solved**, with the 3-star run;
  - **not solved**, with the best run found, its stars, the first thing that cost a star (a fight, a
    mistake, a lost fare or a failure) with its passenger, station and time, and whether the budget
    ran out or every option was tried;
  - **refused**, when the trip can't be played, with the engine's reason.
- **FR-020**: Before returning solved, the solver MUST replay the run from scratch through the
  mirror's replay (FR-007) and confirm 3 stars. A run that doesn't confirm MUST be reported as an
  internal error, never as solved.
- **FR-021**: The verdict, the run, the best run and the score MUST depend only on the trip, the
  params, the solver settings and the solver version. They MUST be identical on every machine and on
  every attempt.
- **FR-022**: A safety cap on time and memory per trip MUST stop a runaway search. The trip is then
  not solved, "stopped by the safety cap", which is reported apart from an exhausted budget. The cap
  MUST sit well above what the effort budget normally costs, so it doesn't fire in normal use.

#### The difficulty score

- **FR-023**: Every solved trip MUST get a difficulty score, a whole number from 0 to 100, computed
  from the trip and its 3-star run. Its inputs are:
  - the most passengers owed change at the same time;
  - the change complexity: the pieces each change takes;
  - the blockers on the passing chains: sleepers and passengers in headphones between a payer and the
    driver;
  - the break requests the run needs;
  - the time slack: the time between the earliest possible delivery and each station, where less
    slack is harder;
  - the variety: how many passenger types and events the trip mixes. The product spec has the first
    trips bring one new type, and the hard ones three or four together («أنواع الركاب»).
- **FR-024**: The score MUST be reported with each input's value and its share of the score.
- **FR-025**: Raising one input while the others stay the same MUST NOT lower the score.
- **FR-026**: The score MUST be computed in whole numbers, so that it is identical on every machine.
  Its weights are solver settings.
- **FR-027**: A score outside the line's band (from `min` to `max`, both included) MUST produce a
  warning that names the trip, the score, the band and the inputs that contribute most. It MUST NOT
  stop the pack from being validated, published on staging or promoted on production
  (Clarifications). The warning is kept in the validation report and the release record.

#### The solver stage in builds

- **FR-028**: The feature MUST supply the real solver stage at B04's plug-in point. Once staging is
  configured with it, every build solves and scores every trip of the pack.
- **FR-029**: The stage MUST pass when every trip is solved, and fail otherwise. Out-of-band scores
  are warnings (FR-027). Each failure and warning MUST be a finding in B04's format: the entity
  (`trip`), the `trip_id`, the field, the problem and the severity.
- **FR-030**: The pack's validation report MUST carry, for every trip, the verdict, the stars, the
  score with each input's value, and the band. The release record MUST carry, for every trip, the
  verdict, the stars, the score and the band, and leaves the inputs to the report, to stay compact.
  Both MUST name the solver settings, the solver version and the params used by their
  fingerprints, and MUST NOT carry staff names (B04's release record).
- **FR-031**: A trip whose definition, params, solver settings and solver version are identical to
  those of a trip solved in an earlier build MUST reuse that result instead of being solved again.
  FR-021 makes this safe. The report MUST say which results were reused.
- **FR-032**: The pass-all stand-in stage MUST remain for development and tests, and the settings check
  MUST keep refusing it on staging and production (B04). Production MUST NOT run the solver;
  promotion keeps requiring a release record whose solver stage passed (B04, promotion step 3).
- **FR-033**: An internal failure on one trip MUST fail that trip with an internal-error finding,
  without stopping the other trips. Its details MUST go to error monitoring, and the author's report
  MUST NOT show internals.

#### Trip preview in the admin

- **FR-034**: On staging, a staff user with authoring permission MUST be able to preview a trip from
  its admin page. The solver solves and scores the trip as currently written, in the background.
- **FR-035**: The preview MUST show the verdict, the stars, the score against the line's band with its
  inputs, the settings used, and the timeline of the run, or of the best run: for each decision, its
  time, what it is, and the passenger and amount it concerns.
- **FR-036**: The preview MUST first run the trip's schema, reference and capability checks. If they
  fail, it MUST show them and not run the solver.
- **FR-037**: A preview MUST NOT change any content, `rev`, pack or build. At most one preview MUST run
  for a trip at a time; asking again while one runs shows the running one.
- **FR-038**: The preview MUST NOT be offered where the admin is read-only (production).

#### Re-solving in CI

- **FR-039**: CI MUST re-solve every trip in `content/source` (once it holds a pack) and in the sample
  pack, with the bundled tunables, on every change to the rules, either engine, the mirror, the
  solver or its settings, the bundled tunables, the content schemas, `content/source` or the sample
  pack. A trip that isn't solved MUST fail CI, naming the trip and where it is.
- **FR-040**: A score outside its band MUST be reported as a warning without failing CI (FR-027). A
  published pack can't change, so a fix goes into the next pack. The sample pack is held to more:
  FR-042 keeps its scores inside their bands.
- **FR-041**: The solver's 3-star run for every sample-pack trip MUST be kept as a parity fixture in a
  `solver` area, written by the Python fixture tool (FR-012), so that the Dart suite replays runs the
  solver found.
- **FR-042**: Every sample-pack trip MUST pass the real solver stage without a warning: solved, and
  scored inside its line's band. A test MUST check this, so CI fails otherwise. A sample trip that
  doesn't pass MUST be corrected in this feature, either the trip or its line's band, together with
  the sample's golden checksums and every fixture or test that copies it.

#### The balancing report

- **FR-043**: A command MUST produce a balancing report for a pack file or a content layout, with one
  row per trip in pack order: the verdict, the stars, the score and its inputs, the break requests the
  run used, the time slack at each station, and, for each slower reaction time in the solver settings
  (900 and 1,200 ms by default), the stars, fights and mistakes of the best run at that reaction time.
  Slower-player results appear only in this report. Builds, previews and CI don't compute them, and
  they never block a pack or add a warning (Clarifications).
- **FR-044**: The report MUST come both as a readable table and as a spreadsheet file, and the same
  input and settings MUST give identical output.

#### Settings, limits and boundaries

- **FR-045**: The solver settings MUST live in one versioned settings record, not as constants spread
  through the code, and every result MUST record the version of the settings it used.
- **FR-046**: The solver settings are the reaction time, the tap time, the effort budget, the safety
  cap, the score's weights and the balancing report's slower reaction times.
- **FR-047**: The solver stage MUST run within the memory the staging host gives its background
  worker (B01), and leave the worker's other jobs room to run.
- **FR-048**: The mirror and the solver MUST depend only on the language's standard library, the
  generated content models and the content kit, so that the backend can call them in-process (backend
  §10.2) and CI can run them without a database.

#### Tests

- **FR-049**: The mirror's rules MUST be built tests first, as the engine's were (constitution XIII).
  Every section of `RULES.md` that the mirror implements MUST have its own tests, beyond the fixtures.
- **FR-050**: Property tests MUST cover: replaying the same tuple always gives the same result; every
  solved run confirms (FR-020); raising one input never lowers the score (FR-025); and random malformed
  tuples are refused without a crash and within the bound of FR-009.
- **FR-051**: Coverage MUST reach at least 90% of lines in the mirror, as in the engine, and at least
  80% in the rest of the solver package and in the backend (constitution XIII).

#### Documents

- **FR-052**: The same change MUST update:
  - backend §10: what the mirror covers (FR-006), the idealized player, the verdicts, the score's
    inputs, the stage and the preview;
  - `RULES.md`'s opening: the mirror reproduces state and results, and the Dart tests alone check
    events and speech;
  - `CLAUDE.md`: the solver's commands, and that a rule change now edits both engines;
  - `fixtures/parity/README.md`: the Python commands and the `solver` area;
  - `content/source/README.md`: CI now re-solves every trip;
  - `docs/owner-actions.md`: a B05 section, with configuring the real stage on staging before B04's
    live checks (B04 T107);
  - `docs/delivery-plan.md`'s Progress list.

### Key Entities

- **Mirror**: the Python copy of the trip rules. It takes a replay tuple and gives a trip result or a
  refusal.
- **Replay outcome**: either the trip result (the same fields as the engine's, fingerprint included)
  or a refusal naming the entry and the reason.
- **Solver settings**: the versioned record of FR-046.
- **Solver result**: for one trip, the verdict, the run or the best run, the stars, what cost a star,
  the search's end (found, exhausted, budget spent, or safety cap), the score, the settings version,
  the solver version and the params fingerprint.
- **Difficulty score**: the 0–100 value, each input's value and share, and the band it was checked
  against.
- **Timeline**: a run as a list of decisions, each with its time, kind, passenger and amount.
- **Solver stage report**: the solver results of every trip in a pack, inside B04's validation report
  and release record.
- **Balancing report**: one row per trip, with the columns of FR-043.
- **Solver fixture**: a parity fixture whose command log is a run the solver found.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The mirror reproduces 100% of the parity fixtures: the 55 on `master` today and every
  one added since. Replaying any fixture 100 times never changes its result or its fingerprint.
- **SC-002**: Before this feature merges, a deliberate change to one rule in only one engine turns CI
  red, once for each engine.
- **SC-003**: Every sample-pack trip is solved at the default settings, scores within its line's band,
  and its solver run reproduces in both engines.
- **SC-004**: A set of deliberately flawed trips, with at least one per kind of fault, is caught every
  time, each with its trip and reason, and none of them can be published. The kinds are: a change that
  can't be made, timing tighter than the reaction time, 3 stars only with an aid, a refused
  definition, and an unsupported passenger type. A trip scoring below its band and one scoring above
  it each get their warning every time, and their pack still publishes.
- **SC-005**: Solving each sample-pack trip 10 times on the CI runner and 10 times on the staging host
  gives identical verdicts, runs and scores.
- **SC-006**: A preview of a typical MVP trip (60–90 s long, up to 12 passengers) shows its result
  within 60 s on staging.
- **SC-007**: For the MVP's content volume (50 trips across the two MVP lines, as in B04 SC-006), the
  solver stage finishes within 30 minutes on the staging host, without going over the worker's memory
  (Clarifications). The effort budget is sized to fit: about 30 s of search per trip on average. A
  rebuild in which no trip changed finishes its solver stage within 2 minutes.
- **SC-008**: Replaying the longest trip the rules allow through the mirror takes under 5 s on the CI
  runner, and a typical 90-second trip under 0.5 s.
- **SC-009**: A set of malformed replay inputs, with at least one per refusal in FR-008, is refused
  every time with the right reason. None crashes, and none costs more than the longest allowed trip.
- **SC-010**: The mirror reaches at least 90% line coverage, and the rest of the solver package and
  the backend at least 80%.
- **SC-011**: The parity and re-solve checks add no more than 10 minutes to CI.
- **SC-012**: After merge, the first pack built on staging with the real stage is published, with a
  passed solver stage and a result for every trip. B04's live checks (B04 T107) can then run.

## Assumptions

- **The band check is a warning** (Clarifications). B04 FR-021 lists it among the solver stage's
  checks without fixing its severity. Making it an error once playtests have calibrated the score is
  a later decision.
- **The mirror leaves out events and speech** (Clarifications). A later feature that needs the event
  stream on the server adds it, with its own Dart-vs-Python check.
- **Slower players are reported, not gated** (Clarifications). Whether a trip must also be finishable
  at a slower reaction time is revisited with the data from step 5's playtest.
- **Defaults this feature sets** (not raised in clarification; to revisit after the playtests):
  - **The idealized player has perfect information.** It never forgets who paid. Memory is counted as
    difficulty, through the score's variety and owed-at-once inputs, not as a limit on solvability.
  - **The balancing report's slower players** react in 900 and 1,200 ms. Both are settings.
- **Params**: the solver uses the bundled tunables for each trip's line, the same defaults a fresh
  install plays with. Changing a tunable live (Remote Config in M15, `LiveSetting` in B10) can make a
  trip harder than it was validated for; checking that before a live change is handed to B10.
- **The seed doesn't matter.** The random generator only picks speech variants (`RULES.md` §13), so a
  verdict holds for every seed. B08 can give each daily challenge any seed.
- **Production doesn't re-solve.** It trusts staging's release record, anchored by the promotion code,
  as B04 designed. The production host's single core serves players, and CI re-solves every promoted
  pack once its export lands in `content/source`.
- **Solver settings and constitution VIII**: the settings decide which trips pass validation, and the
  game never reads them. The plan's Constitution Check decides whether VIII applies to them. Either
  way, FR-045 keeps them in one versioned record.
- **The Dart-CLI fallback** of backend §10.3 isn't taken. The mirror is Python, as backend §23
  decided. If keeping parity turns out to be costly, the fallback stays open.
- **Out of scope**:
  - generating, delivering and verifying the daily challenge, and flagging players whose result
    differs (B08);
  - leagues (B13);
  - checking live tunable changes against the published trips (B10, M15);
  - the "easy mode" the product spec mentions as a risk mitigation;
  - the six phase 2 and 3 passenger types.
- **Hand-overs**:
  - **B08**: call the replay of FR-007 to verify results, and the solver and the score to build and
    pick challenges. A verdict is tied to a settings version (FR-045), and any seed is fine.
  - **B10**: before a live change to a tunable that affects trips, re-solve the current pack with the
    new values.
  - **B04**: its live checks (T107) become possible once staging is configured with the real stage.
- **Dependencies**: B04 is merged (the plug-in point, the validation report, the release record and
  the admin), and so is M01 (`RULES.md`, the fixtures, `capabilities.json` and the replay contract).
  B01 provides the background worker and CI.
