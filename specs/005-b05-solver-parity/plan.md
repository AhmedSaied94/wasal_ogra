# Implementation Plan: Solver and Parity (B05)

**Branch**: `005-b05-solver-parity` | **Date**: 2026-10-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/005-b05-solver-parity/spec.md`

## Summary

B05 creates `tools/solver`, the Python package `wassal_solver`, and plugs it into B04's pipeline. It
covers:

- **The mirror.** A Python copy of every result-deciding rule in `packages/trip_engine/RULES.md`. It
  reproduces all 55 M01 fixtures exactly, fingerprint included, and leaves out events and speech
  (Clarifications Q2). It is built as mutable per-step state with a cheap `clone()` (R2, R3). It also
  offers a replay for untrusted input, with bounded cost, ready for B08 (R6).
- **Parity in CI.** A new `solver` job in the required backend workflow replays every fixture. The
  sample trips' solver runs become `solver__` fixtures that the Dart suite replays too (R4, R16).
- **The solver.** A deterministic depth-first search over player decisions. The idealized player
  knows everything, reacts in 600 ms, taps at 198 ms, and uses no aids. The search prunes at the
  first lost star, keeps a visited table, and counts its effort budget in mirror steps. Every
  solved run is confirmed by a fresh replay (R7 to R10).
- **The difficulty score.** An integer from 0 to 100, as a capped sum over six run-based inputs,
  with its weights in a versioned settings file. A score outside the band is a warning
  (Clarifications Q1; R11, R12).
- **The pipeline.**
  - The real solver stage becomes the strict-environment default.
  - It emits the findings `V-Z1` to `V-Z5`, and per-trip summaries in the report and the release
    record.
  - Publish and promotion accept a solver `warning`.
  - A `SolverRun` table gives reuse of unchanged trips and the admin's one-at-a-time trip preview.
  - A heartbeat keeps long builds alive under B04's stuck-build sweep (R13, R14).
- **Tools.** `wassal-solver` gains `sync`, `parity`, `fixture`, `solve`, `check-source`, `report`
  and `bench`. The balancing report plays slower players at 900 and 1,200 ms, and only it does
  (Clarifications Q3; R17).

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**: Python 3.13 (uv, `==3.13.*`) for `tools/solver` and the backend. Dart 3.13.5
(FVM Flutter 3.47.7) only for the new Dart fixture expectations.

**Primary Dependencies**:

- Solver runtime: `wassal-content` (path) only, which brings Pydantic 2.13.5, jsonschema and
  referencing.
- Solver dev: `ruff==0.17.1`, `mypy==1.19.1`, `pytest==9.1.1`, `pytest-cov==7.1.0`,
  `pytest-xdist==3.8.0` and `hypothesis==6.170.1`.
- Backend: adds `wassal-solver` (path). No other new dependency.

**Storage**:

- The solver has none. Its package data is the settings, the tunables copy and the bench corpus.
- The backend adds one table, `content.SolverRun`, with an expand-only migration.
- The validation report and the release record each gain a `solver` object.

**Testing**:

- pytest and Hypothesis in `tools/solver`:
  - the mirror tests first, per rules module;
  - the parity suite;
  - capabilities equality, untrusted-replay refusals and guard scans;
  - solver fault cases, determinism, confirmation, the score's properties, and perf and memory
    budgets.
- Coverage: ≥ 90% for the mirror and ≥ 80% for the package (R15).
- Backend pytest against real Postgres and Valkey: the stage, reuse, guards, heartbeat, sweep and
  preview, with the backend kept ≥ 80%.
- Dart: the `solver.dart` expectations.

**Target Platform**: Linux, on x86-64 CI runners and on the ARM64 staging and production hosts
(CPython 3.13). The results are identical on both (SC-005).

**Project Type**: A Python library and CLI in the monorepo, plus a backend integration (a Django app
service, a Celery job, an admin view and a model) and CI.

**Performance Goals** (R19):

- Replay of the longest allowed trip: under 5 s on the CI runner. A 90 s trip: under 0.5 s.
- A full-budget search: about 30 s on staging. A 50-trip bench: under 30 minutes on staging.
- A preview of a typical trip: under 60 s on staging. A rebuild with no change: under 2 minutes.
- The CI `solver` job: under 10 minutes.

**Constraints**:

- Deterministic: no clock in a verdict, no set iteration, budgets in steps (R9).
- Integer money, time and score (II).
- The solver's peak memory stays under 64 MB, inside the 512 MB worker (R14).
- The release record stays under 64 KB.
- Production never runs the solver.

**Scale/Scope**:

- 12 archetypes, 8 events and 13 commands mirrored.
- 55 fixtures today, plus 5 solver fixtures.
- 50 trips in the MVP and the bench.
- About 4,000 lines of Python in the mirror and the solver, about 600 in the backend, and about
  25 test modules.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How B05 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | Yes, core | The rules live only in `packages/trip_engine` and its mirror in `tools/solver`, as I names them. The mirror has no clock, PRNG use, I/O or float, and guard scans enforce that (R2). The server doesn't re-implement rules: the stage and the preview call the mirror and solver in-process, and B08 will call `replay_untrusted`. Leaving events and speech out of the mirror keeps every outcome rule mirrored, because neither decides an outcome (R3). |
| II | Integer money | Yes | Piasters, milliseconds, step counts and the score are integers. JSON is read strictly, so a float is refused. The score's arithmetic is `//` on non-negative values (R11). |
| III | Parity | Yes, core | Every fixture is replayed by the Python suite in the required `backend` workflow. A mismatch fails it, as one in the Dart suite fails `mobile`. Solver fixtures add Python-found runs that Dart must replay. The fixture form is unchanged (five keys). Under III's 1.1.1 clause, this is the feature that creates `tools/solver`, and it reproduces every existing fixture before it merges. From then on both suites are required (R4, R16). |
| IV | Server authority | No | No currency, purchase or entitlement is touched. |
| V | Offline-first | No | Nothing changes on the device. |
| VI | Idempotency | Partly | No API. The Celery jobs are idempotent per run: a redelivered `solve_trip` finds its run already started or finished, and the build's reuse is keyed by input (R14). |
| VII | Content, not code | Yes | The stage is the "solver-validated (every trip 3-star solvable)" step VII requires. The solver reads trips only through the generated `TripDefinition`, and lines and bands from the pack. Packs stay immutable: a warning never changes a pack (R13). |
| VIII | Tunable numbers | Yes | The solver plays with the bundled tunables, through a drift-checked copy, and records `params_fingerprint` (R5). The solver settings (reaction and tap times, budget, score weights) are validation settings the game never reads. They are not balancing numbers, so they get no Remote Config key, but they live in one versioned data file and never as constants (R12). |
| IX | No ads in a trip | No | Nothing here. |
| X | RTL and Arabic first | No | The admin preview is staff UI in English, like the rest of B04's admin. No player-visible text is added. |
| XI | Accessible minimums | No | No player UI. |
| XII | No runtime LLM | Yes | The solver is a deterministic search. No model is called. |
| XIII | Small, testable features | Yes | One spec folder. The mirror's rules are written tests first, and there are property, perf and determinism tests. Coverage: 90% for the mirror, 80% for the package and the backend. Backend tests run on real Postgres and Valkey (R15). |

**Locked stack.** Python 3.13 on uv. The backend stays Django 5.2, Celery 5 and Postgres 17, and no
dependency outside the monorepo is added. The image keeps building for `linux/arm64`.

**Security.**

- No secrets, network or personal data in the solver.
- Untrusted input is replay tuples, from B08 onward. They are checked before any stepping, and
  their cost is bounded by the longest trip (R6).
- The preview is a CSRF-protected admin POST behind staff login, `content.change_trip` and the
  `source` role. It writes only its own `SolverRun`. `requested_by` never leaves the database.
- Finding messages are English, for staff, and never carry exceptions. Those go to Sentry.
- No constitution-listed area is touched (auth, purchases, the ledger, sync, webhooks, personal
  data), so no security review is required. `replay_untrusted` is reviewed again with B08, which
  exposes it.

**CI gates.**

- Parity now runs in both Dart and pytest.
- Content: from this feature on, a fresh solve of `content/source` and the sample.
- The backend gates stay as they were: ruff, mypy, pytest at 80% and the OpenAPI diff. The diff is
  unchanged, since there is no API.

**Gate result (pre-research): PASS.** No violation. Principles I to IV and VI have no exceptions.

**Gate result (post-design): PASS.** The re-check after Phase 1 found nothing new:

- **The contracts.** They keep every outcome rule in the two engines, read every number from
  `TripParams` or the settings record, and make every wire format integer-only and canonical.
- **The B04 changes.** The guard change is the one Clarifications Q1 requires. The stage interface
  widens only within B04's plug-in point, and the new table is expand-only.
- **The documents.** They are updated in the same change (R18).

## Project Structure

### Documentation (this feature)

```text
specs/005-b05-solver-parity/
├── plan.md                    # This file
├── research.md                # Phase 0: decisions R1–R19, hand-overs
├── data-model.md              # Phase 1: settings, fingerprints, decisions, results, SolverRun, report shapes, codes
├── quickstart.md              # Phase 1: parity, solve, stage, preview, report, perf, after-merge checks
├── contracts/
│   ├── mirror.md              # Python engine surface, replay, untrusted replay, parity, solver fixtures
│   ├── solver.md              # idealized player, decisions, search, ends, score, report
│   ├── content-pipeline.md    # stage interface, findings, report/record, guards, reuse, preview, env, B04 edits
│   ├── cli.md                 # wassal-solver commands
│   └── ci-checks.md           # backend.yml solver job, filters, image
├── checklists/requirements.md
└── tasks.md                   # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
tools/solver/                               # NEW: uv project wassal-solver (R1)
├── pyproject.toml                          # wassal-content (path); dev pins; hatch artifacts data/
├── .python-version                         # 3.13
├── uv.lock
├── README.md
├── src/wassal_solver/
│   ├── __init__.py                         # solve, score_trip, load_settings, bundled_params
│   ├── cli.py                              # sync | parity | fixture | solve | check-source | report | bench
│   ├── fixture_files.py                    # reading and writing fixture files (engine/ does no I/O)
│   ├── fingerprint.py                      # solver_fingerprint, params_fingerprint, input_key
│   ├── settings.py                         # SolverSettings (frozen), load_settings, settings_version
│   ├── data/
│   │   ├── settings.json                   # R12, contracts/solver.md §5
│   │   ├── tunables.json                   # copy of apps/mobile/assets/config/tunables.json (sync)
│   │   └── bench/                          # 50 committed trip definitions (R17)
│   ├── engine/                             # the mirror (contracts/mirror.md)
│   │   ├── __init__.py                     # start, replay, replay_untrusted, Trip, TripParams, …
│   │   ├── params.py  wire.py  capabilities.py  validation.py  money.py
│   │   ├── model.py                        # slots dataclasses: state, passenger, token, station, choices, counters, result
│   │   ├── replay.py  fixture.py           # replay, untrusted replay, fingerprint; fixture shape, diff, builder
│   │   └── rules/                          # step, chain, fares, change, claims, requests, passengers,
│   │                                       #   authored_events, stations, course, aids, reputation,
│   │                                       #   scoring, command_handlers (one per Dart module)
│   ├── solver/
│   │   ├── decisions.py                    # possible decisions, commands, timing (contracts/solver.md §2)
│   │   ├── search.py                       # DFS, ordering, wait points, pruning, visited table, budget, cap
│   │   ├── result.py                       # SolverResult, first loss, best run, confirmation
│   │   └── timeline.py
│   ├── scoring/difficulty.py               # inputs, points, band check
│   └── report/balancing.py                 # rows, table, CSV
└── tests/
    ├── engine/                             # one module per rules module; validation; params; replay;
    │                                       #   replay_untrusted (+ hypothesis); capabilities; guards
    ├── parity/test_fixtures.py             # every fixtures/parity/*.json
    ├── solver/                             # sample solves, fault kinds, ends, determinism, confirmation
    ├── scoring/                            # range, monotonic (hypothesis), sample in band
    ├── report/  cli/                       # report output, every command's exit codes
    ├── perf/                               # longest replay, 90 s trip, memory at full budget
    └── data/faults/                        # crafted trips, one per SC-004 kind

fixtures/parity/solver__line_*.json         # NEW: 5 solver fixtures (R4)
fixtures/parity/README.md                   # solver area, Python commands
packages/trip_engine/
├── RULES.md                                # opening: what the mirror reproduces (R3)
└── test/fixtures/                          # expectations/solver.dart; area known to coverage test
content/examples/sample/                    # only if a trip or band needs correcting (FR-042), + golden
backend/
├── pyproject.toml  uv.lock                 # wassal-solver path dependency
├── docker/Dockerfile                       # bind tools/solver at /tools/solver
├── config/env.py                           # CONTENT_SOLVER_STAGE: `solver`, strict default
└── apps/content/
    ├── models/solver.py                    # SolverRun (+ models/__init__ export)
    ├── migrations/000N_solverrun.py        # expand-only
    ├── services/
    │   ├── stages.py                       # SolverOutput, widened protocol, progress callback
    │   ├── solver_stage.py                 # NEW: the real stage, reuse, findings V-Z1..V-Z5
    │   ├── preview.py                      # NEW: request_preview, run_preview
    │   ├── build.py                        # pass progress; report_dict solver trips/meta; sweep message + runs
    │   ├── release.py                      # solver object in the record
    │   ├── publish.py  promote.py          # accept solver warning
    ├── tasks.py                            # solve_trip
    ├── admin/authoring.py                  # TripAdmin: solve view, preview panel
    ├── templates/admin/content/trip/change_form.html   # NEW: button + panel
    └── tests/                              # test_solver_stage, test_solver_preview, guard + record + sweep updates
.dockerignore                               # !tools/solver/, tools/solver/tests
.github/workflows/backend.yml               # changes filter; solver job; summary needs
docs/architecture-backend.md                # §9.1, §10
docs/architecture-mobile.md                 # §7.10
specs/003-b04-content-pipeline/contracts/   # environment.md, pack-delivery.md, admin.md, content-schemas.md "(B05)" edits
content/source/README.md  CLAUDE.md  docs/owner-actions.md  docs/delivery-plan.md
```

**Structure decision.**

- **The solver** is the `tools/solver` layout of backend §5 and §10.2, without `generator/`, which
  is B08's.
- **The mirror's `rules/`** matches the Dart engine's file by file, so a rule change edits a matching
  pair (R2).
- **The backend integration** stays inside `apps/content`, at B04's plug-in point: business logic in
  `services/`, thin admin views, and one job.
- **No new app, endpoint or OpenAPI change.**

## Complexity Tracking

No constitution violations. Nothing to justify.
