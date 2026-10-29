---
description: "Review the active feature's implementation across spec, API, database, security, economy, engine, UI, tests and docs; write a review file and append fix tasks"
---

# Review Implementation

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). It may contain:

- `base=<ref>`: compare against this ref instead of the default branch.
- `layers=<a,b,...>`: review only these layers (the names in step 2's table). Spec conformance and
  security always run.
- `no-run`: skip the test suites and builds and review the code only. The report must say so.
- `fix`: after the report, fix the confirmed CRITICAL and HIGH findings yourself (step 8).
- Anything else is an area to look at harder.

## Goal

Another agent, often a different model, ran `__SPECKIT_COMMAND_IMPLEMENT__` for this feature. Review
what it built as the senior engineer who will answer for it in production. Nothing it claimed is
true until you have seen the evidence yourself. A ticked task, a "tests pass" note, a commit
message or a `// done` comment is a claim, not evidence.

The review produces:

1. `FEATURE_DIR/reviews/round-<K>.md`: the verified findings, graded, each with its evidence, plus
   every check you ran and its result.
2. A new `## Phase N: Review fixes (round K)` section at the end of `tasks.md`, with one task for
   each confirmed finding that needs a change, so `__SPECKIT_COMMAND_IMPLEMENT__` can fix them.

## Operating Constraints

- **Read-only on code.** Without `fix`, the only writes are the round file and the appended tasks
  section. Never stash, reset, check out, commit or discard anything.
- **Append-only on tasks.md.** Never edit, untick, renumber or delete an existing task. A task that
  is ticked but not done gets a new task that cites it.
- **Authority.** The constitution (`.specify/memory/constitution.md`) overrides everything. Next
  come the project's agent instructions (the root `CLAUDE.md` and the area `CLAUDE.md` files it
  points to, else `AGENTS.md`), then the feature's
  `plan.md` and `spec.md`, then the docs they cite. A finding cites the rule it breaks.
- **Evidence or nothing.** Every finding names a `file:line` and what you saw there. Every passed
  check names the command you ran and its exit code. A check you did not run is `NOT RUN`, never
  passed.
- **No noise.** Skip what formatters and linters own. Don't pad the report: one real finding
  outweighs ten guesses.
- **Stay on the change.** Review the change set, and read the code around it as far as needed to
  judge its effect. A problem that predates the change goes under "Outside this change" (no task),
  unless the change makes it worse or newly depends on it.

## Execution Steps

### 1. Load the context

1. Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from
   the repo root and parse `FEATURE_DIR`. If `spec.md`, `plan.md` or `tasks.md` is missing, stop and
   name the command that makes it (`__SPECKIT_COMMAND_SPECIFY__`, `__SPECKIT_COMMAND_PLAN__`,
   `__SPECKIT_COMMAND_TASKS__`).
2. Run `.specify/extensions/review/scripts/bash/review-scope.sh --json` (add `--base <ref>` when
   given) and parse it: `BRANCH`, `FEATURE_BRANCH`, `ON_FEATURE_BRANCH`, `BASE`, `MERGE_BASE`,
   `HEAD`, `TOTALS`, `COMMITS`, `FILES` (each with `status`, line counts, `committed` and
   `uncommitted`).
   - `ON_FEATURE_BRANCH` false: stop and tell the user which branch to check out. Don't switch.
   - `FILES` empty: stop. There is nothing to review.
   - Files that are plainly not part of the feature (an agent's own setup, editor files) are listed
     once under "Outside this change" and not reviewed.
3. Read, in full:
   - the constitution, the root `CLAUDE.md` (or `AGENTS.md`) and the `CLAUDE.md` of each area the
     change touches (`apps/mobile/`, `backend/`, `packages/trip_engine/`, `tools/content_kit/`,
     `tools/solver/`): the command tables, the invariants, the repo guards, and the conventions;
   - `spec.md`: every FR, SC, user story with its acceptance scenarios, edge case and clarification;
   - `plan.md`: the Constitution Check, Complexity Tracking, technical decisions and the files it
     names;
   - `tasks.md`, plus `research.md`, `data-model.md`, `contracts/` and `quickstart.md` when present;
   - the latest `FEATURE_DIR/reviews/round-*.md`, if any. Its number plus one is this round's `K`
     (else `K` = 1). Each of its findings is re-checked in this round.
4. Read the `changes` job in each `.github/workflows/*.yml` to learn which CI jobs this change set
   triggers.

### 2. Map the change

Put every changed file in one or more layers. Security and tests apply to every file.

| Layer | Paths in this repo | Checklist |
| --- | --- | --- |
| `spec` | every file | 4.A |
| `api` | `backend/apps/*/{api,services}/`, `tasks.py`, `admin.py`, `backend/config/`, `contracts/openapi.yaml` | 4.B |
| `db` | `backend/apps/*/models.py`, `migrations/`; `apps/mobile/lib/core/storage/`, the drift stores, `drift_schemas/`, `test/drift/` | 4.C |
| `economy` | `backend/apps/{economy,progress,accounts}/`, `apps/mobile/lib/core/{economy,sync,account,progress}/`, `assets/config/tunables.json` | 4.D |
| `engine` | `packages/trip_engine/`, `tools/solver/`, `fixtures/parity/`, `content/`, `tools/content_kit/`, `packages/content_models/`, `apps/mobile/assets/content/` | 4.E |
| `mobile` | `apps/mobile/lib/**/{application,data,domain}/`, `lib/core/`, `lib/bootstrap/`, `pubspec.yaml` | 4.F |
| `ui` | `apps/mobile/lib/**/presentation/`, `lib/core/theme/`, `lib/l10n/`, `assets/`, `test/goldens/`, `test/design/` | 4.G |
| `security` | every file | 4.H |
| `tests` | every test file, coverage and lint config | 4.I |
| `ops` | `.github/`, `backend/docker/`, `codemagic.yaml`, `docs/`, `specs/`, every `CLAUDE.md`, `AGENTS.md` | 4.J |

Then build two maps (keep them internal; they feed steps 4 and 6):

- **Intent → code.** For each FR, SC that needs building, acceptance scenario, edge case, plan
  decision and task: the code that does it and the test that proves it, or "none found".
- **Code → intent.** Each changed file that no task, plan decision or requirement explains is
  scope creep. Each file a task or the plan names that did not change is a likely gap.

### 3. Run the checks

Unless `no-run` was given:

- For each CI job the change triggers, run its commands locally exactly as the areas' `CLAUDE.md`
  command tables give them (right directory, `fvm`, `uv`). Add the checks those tables tie to what
  changed: the property tests at 10,000 examples when auth or the economy changed, the fixtures
  check and the parity replay when the engine changed, `codegen --check` when a schema changed,
  `makemigrations --check` and the OpenAPI regeneration diff when the backend changed, the drift
  schema tests when a table changed, the integration tests `quickstart.md` names.
- The backend tests need the dev stack. If it's down, start it with the command in
  `backend/CLAUDE.md`; if it won't start, mark those checks `NOT RUN` with the reason.
- Run independent suites in the background or in parallel, and review the code while they run.
- Record each check as `command → exit code → one-line result`. A failing check is a finding.
- Look at the diff for ways around the checks, each a finding: deleted or skipped tests (`skip`,
  `xfail`, `@Skip`, new `--exclude-tags`), weaker assertions, goldens rewritten without a UI change
  that explains them, new `# noqa`, `# type: ignore`, `// ignore:` or `ignore_for_file`, changes to
  analysis, ruff, mypy or coverage config, lowered CI thresholds, and generated files edited by
  hand.

### 4. Review each layer

If your agent can run subagents, review the touched layers in parallel: one subagent per layer, and
spec conformance always gets its own. Run them on a cheaper model than yours when your agent lets
you choose one (in Claude Code on Opus, `model: "sonnet"`): step 5 re-checks each of their findings
on yours. Give each one its checklist below, its file list, the paths of `FEATURE_DIR`, the
constitution, the root `CLAUDE.md` and the `CLAUDE.md` of each area its files are in, the base and
head commits, and the finding format of step 5. Ask it to report what it checked as well as what it
found. Use a specialized reviewer (security, database, Python, Flutter) where your agent has one.
Give subagents the code and the checklist, not your suspicions. Without subagents, review the
layers yourself, one at a time.

Each checklist is the minimum. Every MUST, NEVER and "only" in the constitution and the `CLAUDE.md`
files that touches the layer is a check too.

**4.A Spec conformance**

- Each FR, buildable SC, acceptance scenario, edge case and clarification answer: built, where, and
  proven by which test. Walk each `quickstart.md` scenario through the code.
- Each ticked task: the work exists, in the files the task names, and does what the task says.
  Stubs, `TODO`/`FIXME`, `UnimplementedError`, `NotImplementedError`, bare `pass`, hard-coded
  returns, placeholder text and commented-out code mean not done.
- Each unticked task: really not done? Was it needed?
- The code follows `research.md`'s decisions, `data-model.md`'s fields, constraints and state
  transitions, and `contracts/` exactly (names, types, status and error codes, events).
- Behaviour the spec didn't ask for, and changes outside the plan's files.

**4.B API (backend)**

- Views and serializers stay thin; the logic sits in `services/`.
- A new `/v1` endpoint keeps the defaults (player token, the two headers, the per-player throttle),
  or the spec justifies the opt-out. Failures use `ApiError` and the error envelope's code table,
  and leak no internals.
- Validation at the boundary: types, ranges, lengths, enums, batch sizes, integer money, unknown
  fields.
- Object-level authorization: a player reads and changes only their own rows. Staff admin actions
  check their permission group.
- Status codes, safe retries, stable ordering, bounded lists.
- `contracts/openapi.yaml` is regenerated and matches the feature's `contracts/`.
- Celery tasks use `bind=True`, retries and timeouts, and are idempotent. No external call sits in
  the request path unless the architecture allows it.
- New settings are in the environment contract, validated at startup, and hold no secret default.

**4.C Database**

- Django: every model change has a migration. It is expand/contract, so the running release still
  works mid-deploy (no drop or rename of what old code reads; a new NOT NULL gets a default or a
  backfill step). Data migrations use `apps.get_model` and batch.
- New query patterns have indexes; invariants have unique or check constraints; `on_delete` is
  deliberate; primary keys are UUIDv7; money columns are integers.
- Queries: no N+1 (`select_related`, `prefetch_related`), no unbounded querysets, `select_for_update`
  inside `atomic`, no races in get-or-create or counters, no SQL built from strings.
- drift: a table change bumps `schemaVersion`, adds its step to `AppDatabase.upgradeSteps`, and
  commits the exported schema and generated migration tests. A migration keeps existing rows. Only
  the owning store writes the table. No REAL column. Multi-table writes run in one transaction.

**4.D Economy, sync and server authority**

- Every balance change goes through the ledger service. Nothing writes `Wallet` directly or edits a
  ledger row.
- A new sync op: registered handler, works on the batch's in-memory state and not the ORM,
  idempotent by `client_txn_id`, checks bounds (earnings caps, catalog prices for the declared
  `content_version`), and records soft anomalies as `PlayerFlag`s rather than rejecting them.
- Client: only `EconomyService` changes the economy, and only through its store. Optimistic only for
  JENEHAT and progress. BONAT, purchases and entitlements are the server's. BONAT never becomes
  JENEHAT. Ops carry UUIDv7 ids and survive offline replay.
- Integer money in every layer: Dart, Python, JSON, columns, analytics, fixtures.
- A phone port of a server rule matches the server line by line, and a test pins the two together.
- A new balancing number has its tunables entry, Remote Config key and registry row, and the server
  copy matches where a test requires it.

**4.E Engine, parity and content**

- A rule change updates `RULES.md`, both engines, the fixtures and their expectations together.
  Each changed `expected_result` is explained by the rule change.
- The engine stays pure and deterministic: no Flutter, I/O, wall clock or platform random;
  integer arithmetic; `TripParams` without defaults.
- No trip rule re-implemented in the UI or on the server (look for fare, change, star or earnings
  logic outside the engine).
- A schema change: codegen and `build_runner` rerun, generated files committed and unedited,
  restricted profile kept, major bump when the change breaks a promoted pack.
- No Arabic or player text in code; content limits respected; bundled packs agree with their
  records.

**4.F Mobile architecture and Dart**

- Layers: each `domain/` imports only what its folder allows; plugins sit behind gateways;
  `TripController` owns the engine and widgets only send commands.
- Riverpod with the generator: right provider lifetimes, `watch` versus `read` versus `listen`,
  no business logic in `setState`, no BLoC.
- Async: `mounted` checked after every `await` before using `context`; intentional fire-and-forget
  wrapped in `unawaited`; errors handled and shown, never swallowed.
- Lifecycle: controllers, streams, subscriptions, timers and `AnimationController`s disposed.
- Performance: `ListView.builder` for dynamic lists, `const` where it qualifies, narrow rebuilds,
  heavy work off the UI isolate.
- No token, session or install id in logs or preferences. No ad SDK call while a trip runs.

**4.G UI and design**

- Each artboard the plan builds (see `docs/delivery-plan.md` "Design sources") has its sample, a
  golden in both digit styles, and a layout test against its boxes; expected differences are listed.
- Shared components and theme tokens only: no raw colors, radii, font sizes, shadows, durations or
  curves; no Material ink or stock buttons.
- RTL, both digit styles, every string in `app_ar.arb`; text fits at 390×844 and on short screens.
- Minimum sizes: touch targets 44, text 12, bubble text 15, faces 50 and 80, money tokens 40×24.
  Gameplay targets in the bottom third.
- Loading, empty, error, offline and first-run states; disabled states; no double-submit.
- Semantics labels, WCAG AA contrast, reduced motion, a letter beside every station color.
- Rive art keeps its static fallback, and its contract checks pass.

**4.H Security (every file)**

- No secret in code, config, tests, fixtures or logs; no `.env` committed.
- Every new endpoint authenticated and authorized, including object-level checks.
- No injection: SQL, shell (`shell=True`, string-built commands), path traversal (zip import, pack
  files), unsafe deserialization (`pickle`, `yaml.load`), SSRF on outbound URLs.
- Size, count and rate limits on everything a player sends.
- The server trusts no client value it can check: earnings, prices, timestamps, versions.
- Client: tokens only in secure storage, no plain HTTP outside dev, no secret in Dart, deep links
  and URLs validated.
- Tokens compared in constant time; no home-made crypto.
- New dependencies exist, are maintained, are pinned in the lockfile (`uv.lock`, `pubspec.lock`),
  and have an acceptable license.

**4.I Tests**

- Each FR and acceptance scenario has a test that fails if the behaviour breaks. Read the
  assertions and ask: if I flip this condition, does a test fail?
- Engine rules, ledger and sync validators, entitlements and purchase verification were written
  test-first and test the edges.
- Backend tests use the real PostgreSQL and Valkey, not mocks; app tests use the fakes in
  `test/helpers/`.
- Coverage gates hold (80%, the engine 90%) without new exclusions.
- No sleeps, wall-clock time, order dependence or network in tests.

**4.J Ops and docs**

- `docs/owner-actions.md` has this feature's section, with its "Open now" rows.
- The area's `CLAUDE.md` (the root one for what crosses areas) and `AGENTS.md` list new commands,
  files, invariants and guards.
- New environment variables, runbook steps and CI jobs or path filters are where they belong.
- The shared glossary (§3), if touched, changed in both architecture docs. No NEEDS CLARIFICATION was
  resolved by guessing.

### 5. Verify every finding

Before anything reaches the report, re-open the cited code yourself (always for a subagent's
finding) and try to disprove it: is it handled elsewhere (a base class, middleware, a guard test)?
Does the cited rule really require it? Can the path be reached?

- Keep it as **CONFIRMED** when you have seen it and can state the failing scenario.
- Keep it as **PLAUSIBLE** when only running the code would settle it.
- Drop it otherwise.

Each finding records: id `R<K>-<n>`, severity, layer, `file:line`, the problem, a concrete failure
scenario (input or state → wrong outcome), its source (FR, task, constitution principle, `CLAUDE.md`
rule, plan decision), the direction of the fix (not a patch), and CONFIRMED or PLAUSIBLE.

Severity:

- **CRITICAL**: breaks a NON-NEGOTIABLE principle (I, II, III, IV, VI); a security hole a player
  can use; data loss or corruption; ledger or money inconsistency; a migration that breaks the
  running release.
- **HIGH**: a P1 requirement or acceptance scenario missing or wrong; a task ticked but not done; a
  failing check; a crash or unhandled error on a normal path; a test-first area without real tests;
  a way around the checks (step 3).
- **MEDIUM**: a secondary requirement partly met; an unhandled edge case; missing docs or owner
  actions; a maintainability problem with a concrete future failure.
- **LOW**: minor polish.

Verdict: **BLOCK** if any CRITICAL, **CHANGES REQUESTED** if any HIGH, **APPROVE WITH NOTES** if
only MEDIUM or LOW, **APPROVE** if none.

### 6. Write the round file

Create `FEATURE_DIR/reviews/round-<K>.md`:

```markdown
# Implementation review: <feature dir name>, round <K>

- Date: <YYYY-MM-DD> · Reviewer: <agent and model>
- Branch: <BRANCH> · Base: <BASE> (merge base <short sha>) · Head: <short sha>, plus <n> uncommitted files
- Change: <commits> commits, <files> files, +<added> −<deleted>
- Verdict: <verdict> · CRITICAL <n> · HIGH <n> · MEDIUM <n> · LOW <n>

## Checks
| Check | Command | Result |

## Previous round
| Finding | Now |   (fixed / still open / regressed / no longer applies; omit in round 1)

## Findings
### CRITICAL
#### R<K>-1: <title>
- Layer · Source · Location (`file:line`) · CONFIRMED | PLAUSIBLE
- Problem:
- Failure scenario:
- Fix direction:
### HIGH
### MEDIUM
### LOW

## Requirements
| Requirement | Built in | Proven by | Status |   (every FR, buildable SC and acceptance scenario)

## Task audit
Ticked <n>, verified <n>, not done <n>, partly done <n>. Then a table of the mismatches only.

## Outside this change

## Not reviewed
What you did not check or run, and why.
```

### 7. Append the fix tasks

If there are CONFIRMED findings of MEDIUM or higher, append to the end of `tasks.md`:

1. Find the highest task ID `M` and the highest phase number; this phase is that number plus one.
2. Write the header `## Phase <N>: Review fixes (round <K>)` and one line saying the tasks come
   from `reviews/round-<K>.md`.
3. One task per finding, CRITICAL first, numbered from `M+1` and zero-padded like the rest of the
   file, in the file's own task format:

   ```markdown
   - [ ] T123 [R2-4] <imperative fix> in `<path>`: <what is wrong and what must be true after>. Add a test that fails before the fix. (HIGH, per FR-007)
   ```

   Write each task so an agent that has not read the review can do it: the files, the wrong
   behaviour, the right behaviour and the test that proves it. A fix that needs a decision from the
   owner (a spec, plan or constitution change) becomes a task to ask, not a guess.

LOW and PLAUSIBLE findings stay in the round file only. With no CONFIRMED finding of MEDIUM or
higher, leave `tasks.md` byte for byte unchanged.

### 8. Fix mode (only with `fix`)

For each CONFIRMED CRITICAL and HIGH finding, in order: write the failing test first where the
area is test-first, make the smallest fix that follows the plan and the constitution, rerun the
checks it affects, tick its appended task, and add `Fixed in round <K> by the reviewer.` under the
finding in the round file. Never make a check pass by weakening it. Stop and ask when a fix needs a
decision from the owner. When done, rerun every check from step 3 and update the Checks table.

### 9. Report

Reply in chat with the verdict, the counts by severity, one line per CRITICAL and HIGH finding, any
check marked `NOT RUN`, the round file's path, and how many tasks were appended under which phase.
Then give the next step:

- With appended tasks: run `__SPECKIT_COMMAND_IMPLEMENT__` (in whichever agent implements) to fix
  them, then run `__SPECKIT_COMMAND_REVIEW_IMPLEMENTATION__` again for round K+1.
- With APPROVE or APPROVE WITH NOTES: the feature is ready for its PR once the owner has read the
  notes.

Do not commit. The user decides when to commit.
