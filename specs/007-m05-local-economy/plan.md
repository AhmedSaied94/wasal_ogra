# Implementation Plan: Local Economy (M05)

**Branch**: `007-m05-local-economy` | **Date**: 2026-10-22 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/007-m05-local-economy/spec.md`

## Summary

M05 gives the app its economy: the balances, fuel, boosters, ownership and trip progress, kept on
the device and changed only through one service. It covers:

- **The app database.** One drift (SQLite) file in the app's private storage, opened off the UI
  isolate during startup, with WAL and full sync, step-by-step migrations, and the refusal to open
  a newer database. Nothing ever resets it. It is left out of device backup (research R1–R3, R14).
- **An append-only ledger.** Every change is one operation in backend §7.4's vocabulary, with a
  UUIDv7 id, its wire payload, its effects, its reason, its trusted time and the active pack
  version. Its row and the materialized state commit in one transaction (R4, R7, R10, R11).
- **A projection that always adds up.** The rules are pure functions in the domain layer. They
  apply operations one at a time, and a fold rebuilds the same state from a base. Rejections and
  server snapshots (M06) are handled by refolding, which re-validates later operations the way the
  server does (R5, R6).
- **Fuel.** One liter per start (replays included, resolving mobile §24.5), one back every 20
  minutes up to 5, refills and unlimited windows. The rules are exact to the millisecond, and B03
  adopts them (R8, R20).
- **Trusted time.** The phone's uptime counter plus an anchor, through a small Android channel.
  Clock changes while the phone stays on do nothing, and a restart re-anchors without ever moving
  back. M06 later anchors on the server's time (R9).
- **Trips and purchases.** Starts, results, ×2, revives, boosters, and JENEHAT and BONAT purchases
  at the active catalog's price, with per-trip caps and no BONAT ever created on the device
  (R12, R13).

Planning refined two of the spec's own requirements, and the spec has been updated to match:

- **FR-026:** a restart with the clock set back re-anchors at the latest recorded time. That is
  the owner's clarified answer, and it replaces the earlier wording ("pause until …").
- **FR-027:** a tunable change applies to the time since the last operation, so the fold stays
  exact (research R8).

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**: Dart 3.13.5 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`); Kotlin for the
small `wassal/clock` channel in `MainActivity`.

**Primary Dependencies**:

- **New.** `drift ^2.35.2`, `sqlite3 ^3.7.1` (SQLite bundled through build hooks, no
  `sqlite3_flutter_libs`), `uuid ^4.6.0`, `trip_engine` (path), and `drift_dev ^2.35.1` (dev).
- **Existing.** Riverpod 3 with its generator, `path_provider`, `content_models` and
  `build_runner`.
- **Rejected.** `drift_flutter`, which still pulls the end-of-life stubs (research R1).

**Storage**:

- `<app support>/db/wassal.sqlite`, schema v1: `ledger_ops`, `wallet`, `inventory`, `ownership`,
  `trip_progress`, `trip_session`, `projection_base` and `clock_anchor` (data-model.md).
- `drift_schemas/app/drift_schema_v1.json` in the repo.
- M04's `content/` files are unchanged (R15).

**Testing**:

- `flutter_test` on real SQLite: in memory, or temp files to reopen.
- Pure-Dart domain tests, and a seeded property test of 1,000 sequences.
- Kill-point, idempotency, full-disk, newer-database and failed-upgrade tests.
- drift's generated schema tests, and seven simulated days of fuel.
- Repo guards, a CI startup budget, and on-device integration tests (offline play, A06 timings).
- Coverage ≥ 80% (research R19).

**Target Platform**:

- Android, `minSdk 24` (`Settings.Global.BOOT_COUNT` needs 24), `targetSdk 36`, all three flavors.
- iOS (phase 3) runs with the device-clock fallback, and its backup exclusion is handed over.
- Linux for CI.

**Project Type**: A mobile app feature in the `wassal` monorepo: `apps/mobile/lib/core/economy/`
(with `domain/`), `lib/core/storage/`, `lib/core/platform/uptime.dart`, and the Android manifest,
resources and `MainActivity`.

**Performance Goals**:

- On the Galaxy A06, opening the database and reading the balances takes ≤ 200 ms with 50,000
  operations (SC-005), and an operation shows in the view ≤ 100 ms after it is requested (SC-006).
- The cold start to Home stays ≤ 3 s.
- CI budget: 150 ms for the 50,000-operation startup read (research R18).

**Constraints**:

- Offline-first.
- Integer money in every layer, with no `REAL` column.
- One writer, and one transaction per operation.
- Append-only operations.
- No background work.
- No BONAT created on the device.
- Domain purity, enforced by a guard.
- The device clock is read only at a phone restart, and trusted time never goes back.

**Scale/Scope**:

- Six operation types, eight tables, and one Riverpod entry point.
- About 20 new `lib/` files, 1 Kotlin method channel, 2 Android XML files, and about 20 test files.
- 4 guards (2 new, 2 extended), and 5 document updates.
- Years of play: 50,000 operations is the tested ceiling.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How M05 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | Yes | No trip rule is re-implemented. The economy records the engine's `TripResult` and checks only its bounds: earnings within the trip's `max_earnings_jenehat`, and stars 0–3, as the server will. The economy rules live in `lib/core/economy/domain/`, and the extended guard allows there only `dart:core`, `dart:collection`, `content_models`, `trip_engine` and the content domain (research R16). |
| II | Integer money | Yes | Every balance, delta, price, count and time is an `int`, and every column is `INTEGER` or `TEXT`. Payloads are canonical JSON with integers only. The integer-money guard now also forbids `REAL` columns (R16, data-model.md). |
| III | Parity | No | No engine rule, score, parameter or PRNG change. The fixtures are untouched. |
| IV | Server authority | Yes | No operation adds BONAT, and `morning_piggy` is refused on the device (`server_only`). Spending BONAT is optimistic up to the local balance. The kind decides the currency, so no BONAT-for-JENEHAT path exists, and a test enumerates every operation (R7). Every change is an append-only operation applied through `EconomyService` in one transaction, which is the client side of `EconomyService.apply(op)`. A guard scans for direct writes (R11, R16). Rejections roll back through the fold (R6). |
| V | Offline-first | Yes | Everything works with no network from the first launch. Operations stay pending until M06 and are never dropped (FR-045). |
| VI | Idempotency | Yes | Every operation has a client-generated UUIDv7 `client_txn_id` held per player intent. A repeated id returns the stored outcome (R10). **Time (VI as amended in 1.3.0):** trusted time counts the phone's uptime from an anchor. The device clock only takes a new anchor, at first open or after a restart while offline, and never moves time back; a clock change while the phone stays on does nothing. The server recomputes fuel from its own clock and its wallet replaces the device's (M06) (R9). |
| VII | Content, not code | Yes | Prices and currencies come only from the active catalog, read when the operation applies. Trip bounds come from the active pack's definition. Each operation declares the pack version. No player-visible text is added. |
| VIII | Tunable numbers | Yes | Fuel uses `fuel_max` and `fuel_regen_minutes` from `ConfigSource`, and each operation records the values it applied. No new balancing number. The unlimited window's 60 minutes define the product `fuel_unlimited_1h` (glossary §3.3), not a tunable (R8). |
| IX | No ads in a trip | No | No ad call. `applyAdReward` only records a reward after M11's callback. |
| X | RTL and Arabic first | No | No screen (FR-049). |
| XI | Accessible minimums | No | No UI. |
| XII | No runtime LLM | No | — |
| XIII | Small, testable features | Yes | One spec folder. Tests first for the ledger rules and validators. The property test covers the ledger invariant. Kill points, idempotency, migrations, guards and an offline integration test. Coverage ≥ 80% (R19). |

**Locked stack.** drift (SQLite), as the constitution requires, with drift's own native
connection. The new dependencies are drift's own packages, `sqlite3` by drift's author, `uuid`,
and the repo's `trip_engine`. Riverpod with its generator, as before. The one platform call, the
`wassal/clock` channel, sits behind `UptimeSource` (Architecture boundaries).

**Security & privacy.**

- **The ledger is security-relevant.** The constitution's review list names the ledger, so this PR
  gets a security review (Development Workflow, "Review").
- **No secrets, tokens or personal data** are stored. The database holds balances, ids and game
  progress only.
- **Private storage, and out of backup** (R14). A rooted player's edits change nothing the server
  accepts: the server keeps its own ledger, and its snapshot replaces the device's.
- **No network** in this feature.

**CI gates (constitution).** Mobile analyze, unit, widget and golden tests: unchanged jobs, with
more tests. Parity and the OpenAPI diff: unchanged. The direct-`Wallet`-write scan is a backend
gate that arrives with B03; its client counterpart, `economy_writes_test.dart`, starts here.

**Gate result (pre-research): PASS.** No exceptions. Principle VI's time clause was the one to
examine. `/speckit-analyze` (C1) found the 1.2.0 wording unmeetable offline, so constitution 1.3.0
amended it to the rule this design follows (R9).

**Gate result (post-design): PASS.** The re-check after Phase 1 found nothing new:

- the domain folder's imports are only those the guard allows;
- every table column is `INTEGER` or `TEXT`;
- every write goes through `DriftEconomyStore` inside one transaction;
- no operation in contracts/operations.md raises BONAT or pairs a BONAT spend with JENEHAT;
- the wire payloads are backend §7.4's, with two proposed reasons, the revive's `ref` and `chapter`
  ownership handed to B03 and recorded in the backend doc in this PR (R21);
- no screen, string or tunable is added.

## Project Structure

### Documentation (this feature)

```text
specs/007-m05-local-economy/
├── plan.md                 # This file
├── research.md             # Phase 0: decisions R1–R21, hand-overs
├── data-model.md           # Phase 1: domain values, tables, invariants, lifecycles
├── quickstart.md           # Phase 1: setup, scenarios 1–6, done when
├── contracts/
│   ├── economy-api.md      # the Economy interface, outcomes, refusal codes, view, providers, caller rules
│   ├── operations.md       # each op's payload, effects, reason, refusals; the fold; what M06 sends
│   ├── fuel-and-time.md    # fuel arithmetic, examples, TrustedClock, the wassal/clock channel
│   └── storage.md          # the file, pragmas, migrations, backup rules, guards, CI
├── checklists/requirements.md
└── tasks.md                # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
apps/mobile/
├── pubspec.yaml                                   # drift, sqlite3, uuid, trip_engine; drift_dev (dev)
├── drift_schemas/app/drift_schema_v1.json         # NEW: exported schema (storage.md)
├── lib/
│   ├── bootstrap/startup.dart                     # waits for economyProvider; retry invalidates it
│   ├── bootstrap/app.dart                         # lifecycle: TrustedClock.resync on resume, latest on pause
│   └── core/
│       ├── storage/                               # NEW
│       │   ├── app_database.dart                  # AppDatabase, migrations, newer-db refusal
│       │   ├── tables.dart                        # the eight tables (data-model.md)
│       │   └── connection.dart                    # file path, createInBackground, pragmas
│       ├── economy/                               # NEW
│       │   ├── domain/
│       │   │   ├── economy_state.dart             # EconomyState, FuelState, TripProgress, Owned, …
│       │   │   ├── op.dart                        # OpRequest, Op, OpType, LedgerReason, TxnId, AdPlacement
│       │   │   ├── economy_refusal.dart           # EconomyRefusal (economy-api.md)
│       │   │   ├── rules.dart                     # validate and apply, per operation (operations.md)
│       │   │   ├── fold.dart                      # fold(base, ops), re-validation (research R6)
│       │   │   ├── fuel.dart                      # regenerate, spendOne, fillToMax, view (fuel-and-time.md)
│       │   │   └── trusted_time.dart              # anchor arithmetic, restart check
│       │   ├── economy.dart                       # Economy interface, OpOutcome, EconomyView
│       │   ├── economy_service.dart               # writer queue, view stream, next-liter timer
│       │   ├── drift_economy_store.dart           # the only writer of economy tables; EconomyKillPoint hook
│       │   ├── trusted_clock.dart                 # TrustedClock over UptimeSource + the store's anchor
│       │   └── economy_providers.dart             # providers (economy-api.md)
│       └── platform/uptime.dart                   # NEW: UptimeSource, the wassal/clock channel client
├── android/app/src/main/
│   ├── AndroidManifest.xml                        # dataExtractionRules, fullBackupContent
│   ├── res/xml/data_extraction_rules.xml          # NEW
│   ├── res/xml/backup_rules.xml                   # NEW
│   └── kotlin/com/wassalogra/app/MainActivity.kt  # wassal/clock: bootSnapshot
├── test/
│   ├── core/economy/domain/                       # rules, fuel, trusted time, direction
│   ├── core/economy/                              # store, kill points, idempotency, property, fuel week, service
│   ├── core/economy/perf/startup_budget_test.dart # 50,000 operations
│   ├── core/platform/uptime_test.dart             # channel client against a mock channel
│   ├── drift/                                     # generated schema-verification tests
│   ├── repo/                                      # domain_imports (extended), economy_writes, integer_money (extended), backup_rules
│   └── helpers/economy.dart                       # NEW: in-memory service, fake uptime, fixed tunables
└── integration_test/
    ├── economy_offline_test.dart                  # NEW: airplane mode, restart (SC-007)
    └── economy_perf_test.dart                     # NEW: A06 timings (owner)
docs/architecture-mobile.md                        # §11, §13, §24.5
docs/architecture-backend.md                       # §7.2, §7.4, §7.5, §12
docs/delivery-plan.md                              # M04 merged in #7; §24.5 resolved; M05 progress
docs/owner-actions.md                              # M05 section (at /speckit-implement)
CLAUDE.md                                          # drift commands, the first sqlite3 download
```

**Structure decision.**

- **Folders.** `core/economy/` and `core/storage/` are the folders mobile §5 names for "wallet,
  ledger, fuel" and "drift database". The rules go in `economy/domain/`, so the purity guard
  watches exactly the code that decides balances.
- **Ownership of the database.** `core/storage/` owns the connection and the schema. Each feature's
  data access lives with the feature. For M05 that is `drift_economy_store.dart`, the only writer
  of the economy tables.
- **No new package.** The rules depend on the app's `ContentSource` interface and nothing outside
  the app uses them (research R16).

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified

None.
