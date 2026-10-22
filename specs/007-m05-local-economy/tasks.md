---

description: "Task list for M05 Local Economy"
---

# Tasks: Local Economy (M05)

**Input**: Design documents from `specs/007-m05-local-economy/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Constitution XIII requires tests, and tests come first for the ledger
  rules and validators. Every phase writes its tests first, and they must fail before its
  implementation tasks start.
- **Real SQLite.** Store and service tests use real drift databases: `NativeDatabase.memory()`, or
  a temp file when a test reopens it. Only the platform edges are faked: `UptimeSource`,
  `ConfigSource`, the content source (the sample pack) and the device clock.
- **Coverage.** At least 80% of lines in `apps/mobile`. Generated parts (`*.g.dart`) stay excluded,
  as `tool/check_coverage.dart` already does.

**Organization**:

- **Paths** are from the repository root. Dart commands run with `fvm` in `apps/mobile/`.
- **Codegen.**
  - After adding or changing a `@riverpod` provider or a drift table, run
    `fvm dart run build_runner build -d` in `apps/mobile`.
  - After changing a table, also run `fvm dart run drift_dev make-migrations`.
  - Before any app test, build `packages/content_models` (`fvm dart pub get && fvm dart run
    build_runner build -d`).
- **Exactness.** Every number in a task is from the contracts: the 60-minute window, the 4 in-trip
  boosters, the 1,000 property sequences, the budgets. Name each one as a constant in `lib/`, never
  as a bare literal. Each wire name is the contract's, spelled exactly.
- **Shared files.** These grow story by story, so tasks that touch them are sequential across
  stories:
  - `lib/core/economy/domain/rules.dart` (the dispatcher);
  - `trip_rules.dart` and `ad_rules.dart`;
  - `economy_service.dart` and `drift_economy_store.dart`.
- **One PR.** This feature merges as one PR, with a security review (plan "Security & privacy").

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US5 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Dependencies and drift's configuration (research R1, R3).

- [X] T001 Update `apps/mobile/pubspec.yaml` (research R1):
  - dependencies `drift: ^2.35.2`, `sqlite3: ^3.7.1`, `uuid: ^4.6.0` and
    `trip_engine: {path: ../../packages/trip_engine}`;
  - dev dependency `drift_dev: ^2.35.1`;
  - no `drift_flutter`, `sqlite3_flutter_libs` or `sqlcipher_flutter_libs`.

  Run `fvm flutter pub get` (the first run downloads the SQLite binary through the `sqlite3` hook),
  then commit `pubspec.lock`.
- [X] T002 [P] Create `apps/mobile/build.yaml` with drift's options (contracts/storage.md
  "Migrations"):
  - under `targets: $default: builders: drift_dev: options:`, set
    `databases: {app: lib/core/storage/app_database.dart}`, `schema_dir: drift_schemas/` and
    `test_dir: test/drift/`;
  - leave every Riverpod builder at its default.

  Add `apps/mobile/drift_schemas/README.md` in English: the directory holds drift's exported
  schemas, written only by `fvm dart run drift_dev make-migrations`, and every schema version must
  stay committed.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: What every story uses: the domain types, the database, trusted time, the store, the
service and its providers, the guards and the test helpers.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Test helpers

- [X] T003 Create `apps/mobile/test/helpers/economy.dart`:
  - `FakeUptimeSource implements UptimeSource`, with a settable `elapsedRealtimeMs`, `bootCount` and
    `available` (false makes `snapshot()` return null), and an `advance(Duration)` that moves
    `elapsedRealtimeMs`;
  - `FakeDeviceClock` with a settable UTC `nowMs`;
  - `fixedFuelTunables({int fuelMax = 5, int fuelRegenMinutes = 20})`, a `ConfigSource` that
    returns those for `Tunable.fuelMax` and `Tunable.fuelRegenMinutes` and the bundled default for
    every other key;
  - `testEconomy({ContentSource? content, ConfigSource? tunables, FakeUptimeSource? uptime,
    FakeDeviceClock? device, File? dbFile, Rules? rules})`, which opens an `AppDatabase` (in memory,
    or `dbFile`) and returns the `EconomyService` with its store and clock. The content defaults to
    `sampleActiveContent().source` from `test/helpers/content.dart`;
  - `tripResult({required String tripId, TripOutcome outcome = TripOutcome.finished, int stars =
    3, int earnings = 50, int durationMs = 90000, bool revived = false})`, which builds a
    `TripResult` through `TripResult.fromJson` with every other field zero or empty;
  - `reopen(File dbFile, …)`, which closes and opens the same file for kill-point tests.

### Guards: tests first

- [X] T004 [P] Extend `apps/mobile/test/repo/domain_imports_test.dart` (research R16,
  contracts/storage.md "Guards"):
  - replace the single folder with a table of domain folders, each with its allowed imports:
    - `lib/core/content/domain` keeps today's list;
    - `lib/core/economy/domain` allows `dart:core`, `dart:collection`,
      `package:content_models/`, `package:trip_engine/` and
      `package:wassal/core/content/domain/`, plus relative imports with no `/` and no `..`
      (files of the same folder);
  - each folder must exist and hold at least one `.dart` file;
  - self-tests: a relative `'fuel.dart'` passes in the economy domain; `'../economy.dart'`,
    `'package:uuid/uuid.dart'`, `'package:drift/drift.dart'` and `'dart:io'` fail; the content
    domain still refuses `package:trip_engine/`.

  It fails until T017 creates the economy domain.
- [X] T005 [P] Extend `apps/mobile/test/repo/integer_money_test.dart`: no file under
  `lib/core/storage/` contains `real()`, `RealColumn` or `.real(` (FR-008). Self-tests catch
  `RealColumn get price => real()();` and ignore the word in a comment.
- [X] T006 [P] Create `apps/mobile/test/repo/economy_writes_test.dart` (FR-013, contracts/storage.md
  "Guards"):
  - only files under `lib/core/storage/`, `lib/core/economy/drift_economy_store.dart` and
    `lib/core/economy/economy_providers.dart` import `app_database.dart`, whether by `package:` or
    relative path. The providers file only constructs the database and the store;
  - outside `lib/core/storage/` and `drift_economy_store.dart`, no `lib/` file contains `into(`,
    `update(`, `delete(`, `batch(`, `customStatement(`, `customUpdate(` or `customInsert(`. So
    `trusted_clock.dart` and `economy_providers.dart` write nothing directly, and `clock_anchor`
    too is written only by the store;
  - in `drift_economy_store.dart`:
    - `update(ledgerOps)` appears only inside the method `_setSyncStatus`, and that method's
      `LedgerOpsCompanion(` names only `syncStatus:` and `syncReason:`;
    - `delete(ledgerOps)` appears nowhere in `lib/`;
  - `drift_economy_store.dart` must exist, so the rules can't pass on an empty tree;
  - self-tests for each rule on small source strings.

  It fails until T020 exists.
- [X] T007 [P] Create `apps/mobile/test/repo/sqlite_dependency_test.dart` (research R1):
  `apps/mobile/pubspec.lock` has `sqlite3` at major version 3, and none of `sqlite3_flutter_libs`,
  `sqlcipher_flutter_libs` or `drift_flutter`.

### Domain and storage: tests first

- [X] T008 [P] Write `apps/mobile/test/core/economy/domain/txn_id_test.dart`:
  - `TxnId.parse` accepts a lowercase UUIDv7 matching
    `^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`;
  - it refuses a v4, uppercase, a missing hyphen and an empty string with `FormatException`.

  Also write `apps/mobile/test/core/economy/txn_ids_test.dart`: `newTxnId(trustedMs)` returns a
  valid `TxnId` whose first 48 bits equal `trustedMs`, and 10,000 calls give 10,000 distinct ids.
- [X] T009 [P] Write `apps/mobile/test/core/economy/domain/economy_state_test.dart` (data-model.md
  "Domain values"):
  - `EconomyState.newPlayer(fuelMax: 5, nowMs: t)` is "`jenehat = 0`, `bonat = 0`,
    `fuel = FuelState(liters: fuel_max, countedFrom: <first open>, unlimitedUntil: null)`,
    everything else empty or null";
  - `toJson` gives canonical JSON (`content_models`' `canonicalJson`), and `fromJson` round-trips a
    state with every field set;
  - `fromJson` refuses, with `FormatException`:
    - a non-integer amount;
    - a negative `jenehat`, `bonat`, `liters` or inventory count;
    - an inventory key outside `change_bag`, `wake_all`, `ledger_peek` and `traffic_jam`;
    - an ownership kind outside `item`, `vehicle` and `chapter`;
    - `bestStars` outside 0–3;
    - `trafficJamAds` outside 0–1;
  - `Owned` requires `variantId` for `item` and refuses it for `vehicle` and `chapter`.
- [X] T010 [P] Write `apps/mobile/test/core/economy/domain/trusted_time_test.dart` for the pure
  arithmetic in `trusted_time.dart`. Cover every row of contracts/fuel-and-time.md "Cases the tests
  cover":
  - clock +3 h with the phone on, app open, and app closed and reopened;
  - clock −3 h with the phone on;
  - a restart with the clock right and 2 h off;
  - a restart with the clock +3 h;
  - a restart with the clock −3 h;
  - no boot count, with a restart whose uptime is longer than the anchor's;
  - no channel;
  - a time zone change.

  Also check that `latestTrustedMs` never decreases, and that a server anchor never goes below it.
- [X] T011 [P] Write `apps/mobile/test/core/storage/app_database_test.dart`, on a temp file
  (contracts/storage.md, data-model.md "Tables"):
  - **first open** creates exactly the 8 tables and their first rows:
    - `wallet`: `jenehat 0`, `bonat 0`, `fuel` = `fuel_max`, `fuel_counted_from_ms` = the anchor's
      `anchor_ms`, `fuel_unlimited_until_ms` null, `last_seq 0`;
    - `trip_session`: all null;
    - `projection_base`: `kind new_player`, `after_seq 0`, `state` equal to `newPlayer`'s
      canonical JSON;
    - `clock_anchor`: `source device`;
  - `PRAGMA journal_mode` is `wal`, `synchronous` is `2` (FULL) and `foreign_keys` is `1`;
  - every column's declared type (`PRAGMA table_info`) is `INTEGER` or `TEXT`;
  - CHECK constraints reject: a negative `jenehat`, `bonat` or `fuel`; a negative inventory count;
    `best_stars = 4`; `sync_status = 'x'`; `op_type = 'x'`; a second row in each single-row table
    (`id = 2`); an ownership kind `upgrade`;
  - a file whose `user_version` is 2 makes open fail with `DatabaseFromNewerApp`, and the file's
    bytes are unchanged (compare sha256 before and after);
  - a file of random bytes makes open fail, and the file is unchanged.
- [X] T012 [P] Write `apps/mobile/test/core/platform/uptime_test.dart`, against a mock
  `wassal/clock` channel
  (`TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler`):
  - `bootSnapshot` with `{"elapsed_realtime_ms": 123, "boot_count": 7}` gives
    `BootSnapshot(123, 7)`;
  - a null `boot_count` gives `BootSnapshot(123, null)`;
  - `MissingPluginException`, a non-integer value or a missing key gives null.
- [X] T013 [P] Write `apps/mobile/test/core/economy/trusted_clock_test.dart`, over `FakeUptimeSource`,
  `FakeDeviceClock` and a `DriftEconomyStore` on a temp database. The clock reads and writes its
  anchor only through the store's `loadAnchor` and `saveAnchor`:
  - the first open anchors on the device clock;
  - **same boot:** reopening after moving the device clock ±3 h gives the same `nowMs` as the
    uptime says;
  - **restart:** a new boot count re-anchors at `max(device, latest)`;
  - `resync()` takes a new snapshot, as on a return to the foreground;
  - `saveLatest()` stores `latest_trusted_ms`, and it never decreases;
  - `anchorOnServer` sets `source server`, never below latest;
  - **no channel** (`available = false`): the device clock, never below latest.
- [X] T014 [P] Write `apps/mobile/test/core/economy/store_test.dart` for `DriftEconomyStore`, on a
  temp file:
  - `commit(op, before, after)` writes the `ledger_ops` row with every column of data-model.md, and
    in the same transaction writes the changed rows:
    - `wallet`, with `last_seq`;
    - `inventory` rows inserted, updated, and deleted when a count reaches 0;
    - `ownership` rows inserted;
    - `trip_progress` upserted;
    - `trip_session`;
    - `clock_anchor.latest_trusted_ms`;
  - `load()` returns the base, the state, `lastSeq` and the anchor equal to what was committed;
  - `findOp(txnId)` returns the stored op, or null;
  - `saveAnchor` then `loadAnchor` round-trips every `clock_anchor` column, and `saveAnchor` never
    lowers `latest_trusted_ms`;
  - **kill points:** for each `EconomyKillPoint` (`afterOpRow`, `afterWallet`, `afterInventory`,
    `afterOwnership`, `afterProgress`, `afterSession`, `afterAnchor`), a hook that throws leaves the
    file, once reopened, exactly as before the commit. At `afterCommit`, it is exactly as after.
- [X] T015 [P] Write `apps/mobile/test/core/economy/economy_service_test.dart`, the generic part,
  with a test `Rules` that accepts or refuses on a flag in the request:
  - `OpApplied` writes one row and emits one view, and the view changes only after the commit;
  - `OpRefused` writes nothing and emits nothing;
  - a repeated id returns `OpApplied(repeated: true)` with the stored op, and writes no row (FR-016);
  - two requests started together apply one after the other, in request order (FR-017);
  - an executor that throws `SqliteException(13, …)` (SQLITE_FULL) on insert gives `OpWriteFailed`.
    Memory and file are unchanged, and the next request applies;
  - every op's `occurredAtMs` is the trusted clock's `nowMs`, and is ≥ the previous one's.
- [X] T016 [P] Write `apps/mobile/test/bootstrap/economy_startup_test.dart`, widget tests with
  `pumpApp`:
  - the boot screen stays until `economyProvider` completes, then hands over to `/home`;
  - an `appDatabaseProvider` that throws (once) shows `l10n.bootErrorMessage` and the
    `l10n.bootRetry` button, and never Home;
  - retry reaches Home, because `retryAppStartup` invalidated the five economy providers
    (`uptimeSnapshotProvider`, `appDatabaseProvider`, `economyStoreProvider`,
    `trustedClockProvider` and `economyProvider`).

### Domain and storage: implementation

- [X] T017 Create the domain types in `apps/mobile/lib/core/economy/domain/`:
  - `txn_id.dart`: `TxnId` with `parse` and the pattern of T008;
  - `op.dart`, with every wire name exactly as contracts/operations.md spells it:
    - `OpType` (`trip_start`, `trip_result`, `ad_reward`, `spend_jenehat`, `spend_bonat`,
      `use_booster`);
    - `LedgerReason` (`trip_earnings`, `ad_result_double`, `item_purchase`, `vehicle_purchase`,
      `chapter_purchase`, `booster_purchase`, `fuel_purchase`, `revive_purchase`,
      `fuel_unlimited_purchase`);
    - `AdPlacement` (`result_double`, `fuel_refill`, `trip_revive`, `traffic_jam`,
      `morning_piggy`);
    - `FuelMode` (`fuel`, `unlimited`);
    - the sealed `OpRequest` (`StartTripRequest`, `RecordResultRequest`, `BuyRequest`,
      `UseBoosterRequest`, `AdRewardRequest`);
    - `Op`, with the fields of data-model.md "`OpRequest` → `Op`";
  - `economy_refusal.dart`: `EconomyRefusal`, with the 23 codes of contracts/economy-api.md as
    snake-case wire names;
  - `economy_state.dart`: `EconomyState`, `FuelState`, `TripProgress`, `Owned`, `OwnedKey`,
    `UnfinishedTrip` and `LastResult`, immutable, with `newPlayer`, `toJson` and `fromJson`;
    `inTripBoosters = {change_bag, wake_all, ledger_peek, traffic_jam}` as a named constant;
  - `trusted_time.dart`: `BootSnapshot`, `ClockAnchor`, `isRestart`, `reanchor` and `trustedNow`,
    as contracts/fuel-and-time.md "Rules" gives them.

  T008's domain part, T009 and T010 pass.
- [X] T018 Create `apps/mobile/lib/core/economy/domain/rules.dart` and `fold.dart`:
  - `RuleContext {nowMs, content (ContentSource), contentVersion, fuelMax, fuelRegenMinutes,
    txnId}`;
  - `sealed class Decision` (`Validated(Op op)`, `Declined(EconomyRefusal code)`; trip_engine already
    exports `Accepted` and `Rejected`);
  - `abstract interface class Rules`, with `Decision validate(EconomyState, OpRequest,
    RuleContext)`, `EconomyState apply(EconomyState, Op)` and `bool stillValid(EconomyState, Op)`;
  - `ProductionRules`, a dispatcher on the request and op type. Each type delegates to the rule file
    its story adds;
  - `FoldResult fold(EconomyState base, Iterable<Op> ops, Rules rules)`. In order, it applies each
    op whose `stillValid` holds, and lists the left-out `txnId`s (research R6).
- [X] T019 Create `apps/mobile/lib/core/storage/tables.dart`, `connection.dart` and
  `app_database.dart` (data-model.md "Tables", contracts/storage.md):
  - the 8 tables, with every constraint as data-model.md states it: CHECKs, NULL or NOT NULL,
    single rows with `CHECK (id = 1)`, the unique `txn_id`, and the indexes `(sync_status, seq)`
    and `ref`;
  - `connection.dart`: the path `<getApplicationSupportDirectory()>/db/wassal.sqlite`, created if
    missing, and `NativeDatabase.createInBackground(file, setup: …)` setting `journal_mode = WAL`,
    `synchronous = FULL` and `foreign_keys = ON`;
  - `AppDatabase`, with `schemaVersion = 1` and a constructor that takes the initial state and
    anchor:
    - `onCreate` creates the tables and the first rows in one transaction;
    - `onUpgrade` throws `DatabaseFromNewerApp(from, to)` when `from > to`, and otherwise runs
      each entry of `upgradeSteps` in its own transaction with its `user_version`;
    - the constructor takes any `QueryExecutor`, so tests pass one in memory.

  Run `build_runner`, then `fvm dart run drift_dev make-migrations`, and commit
  `apps/mobile/drift_schemas/app/drift_schema_v1.json`. With one version, `make-migrations`
  writes no tests, so generate the schema helpers with `fvm dart run drift_dev schema generate
  drift_schemas/app/ test/drift/app/generated/` and test v1 in
  `apps/mobile/test/drift/app/schema_v1_test.dart`. T005 and T011 pass.
- [X] T020 Create `apps/mobile/lib/core/economy/drift_economy_store.dart`:
  - `load()`, `commit(op, before, after)` (the op row plus the diff of materialized rows, in one
    transaction) and `findOp`;
  - `loadAnchor()` and `saveAnchor(ClockAnchor)`, the only writes of `clock_anchor` outside an
    operation's commit (research R9);
  - `EconomyKillPoint` and the `onKillPoint` hook (research R11);
  - a private `_setSyncStatus`, used only from US5;
  - a write error surfaces as `EconomyWriteError`.

  T006 and T014 pass.
- [X] T021 Create `apps/mobile/lib/core/platform/uptime.dart`, with `UptimeSource` and
  `ChannelUptimeSource` over `MethodChannel('wassal/clock')` (contracts/fuel-and-time.md "Android
  channel"). In `apps/mobile/android/app/src/main/kotlin/com/wassalogra/app/MainActivity.kt`, add a
  second `MethodChannel` named `wassal/clock` next to `wassal/launch`. Its `bootSnapshot` returns
  `elapsed_realtime_ms` (`SystemClock.elapsedRealtime()`) and `boot_count`
  (`Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT)`, or null on
  `SettingNotFoundException`). T012 passes.
- [X] T022 Create `apps/mobile/lib/core/economy/trusted_clock.dart` (a `TrustedClock` over
  `UptimeSource`, the device clock, the store's `loadAnchor` and `saveAnchor`, and a `Stopwatch`;
  it never touches the database itself) and
  `apps/mobile/lib/core/economy/txn_ids.dart` (`newTxnId(int trustedMs)` through `uuid`'s v7 with
  `V7Options(trustedMs, null)`). T008 and T013 pass.
- [X] T023 Create `apps/mobile/lib/core/economy/economy.dart` (the `Economy` interface, sealed
  `OpOutcome` with `OpApplied`, `OpRefused` and `OpWriteFailed` (trip_engine already exports
  `OpApplied`), and `EconomyView`, as in contracts/economy-api.md; `FuelView` is in
  `domain/fuel.dart`) and `apps/mobile/lib/core/economy/economy_service.dart`:
  - a single writer queue (a Future chain);
  - `newRequestId`;
  - the idempotency check through `findOp`;
  - validate, commit, then update memory and emit on `views`;
  - `OpWriteFailed` on `EconomyWriteError`;
  - `RuleContext` built from the trusted clock, `contentSourceProvider`, `contentVersionProvider`
    and the fuel tunables read at each request;
  - in debug builds, an assertion that a repeated id's request matches the stored op (research
    R10).

  T015 passes.
- [X] T024 Create `apps/mobile/lib/core/economy/economy_providers.dart`, with the keep-alive
  providers of contracts/economy-api.md "Providers". Build them in this order, which breaks the
  anchor's circle (creating the database needs the first anchor, and the clock reads the stored
  one):
  1. `uptimeSnapshotProvider`: one `UptimeSource.snapshot()`, with no database;
  2. `appDatabaseProvider`: opens the file. On a first open, `onCreate` builds the first state
     from `Tunable.fuelMax`, and the first anchor from that snapshot and the device clock;
  3. `economyStoreProvider`: the `DriftEconomyStore` over the database;
  4. `trustedClockProvider`: reads the stored anchor through the store, then applies the restart
     check to the same snapshot;
  5. `economyProvider`, then `economyViewProvider`.

  In `apps/mobile/lib/bootstrap/startup.dart`:
  - add `economyProvider.future` to `appStartup`'s `Future.wait`;
  - invalidate providers 1 to 5 in `retryAppStartup`.

  Run `build_runner`. T016 passes, and so do all the guards (T004–T007).

**Checkpoint**: The database opens during startup, every guard is green, and the generic service
applies, refuses, repeats and fails cleanly. No operation type has its rules yet.

---

## Phase 3: User Story 1 - Fuel limits play and refills by itself, offline (Priority: P1) 🎯 MVP

**Goal**: A start spends a liter, a liter returns every 20 minutes up to 5, refills and the
unlimited window work, and clock changes while the phone is on do nothing (FR-020 to FR-031, FR-036).

**Independent Test**: `fuel_service_test.dart` and `fuel_week_test.dart` (quickstart scenario 1),
and scenario 4 on a device.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T025 [P] [US1] Write `apps/mobile/test/core/economy/domain/fuel_test.dart`, for every function
  of contracts/fuel-and-time.md "Fuel" with `max 5` and `regen 20 min`:
  - the four worked examples, exactly;
  - `t < countedFrom` adds nothing;
  - `regenerate` leaves a tank above the maximum alone;
  - `spendOne` from above the maximum down to the maximum keeps `countedFrom`;
  - `fillToMax` is refused at or above the maximum;
  - `extendUnlimited` starts a new window at `t` and extends a running one from its end;
  - `isUnlimited` is false at `t == unlimitedUntil`;
  - `view` gives null times at or above the maximum;
  - a raised maximum counts from the moment the tank last filled;
  - regenerating with a different `fuel_regen_minutes` changes only the time after the given
    point.
- [X] T026 [P] [US1] Write `apps/mobile/test/core/economy/domain/trip_start_rules_test.dart`
  (contracts/operations.md `trip_start`):
  - refusals in order: `unknown_trip` (not in the sample pack), `trip_unfinished`, then `no_fuel`
    (0 liters, no window);
  - in `fuel` mode: `fuelDelta −1`, and payload canonical JSON
    `{"content_version":1,"fuel_mode":"fuel","trip_id":"<id>"}`;
  - inside a window: `fuel_mode` `unlimited` and `fuelDelta 0`;
  - `maxEarningsJenehat` comes from the pack's definition, not the request;
  - `unfinished` is set with `startedAtMs = nowMs`;
  - a trip with progress at 3 stars still costs one liter (FR-029);
  - `stillValid` is always true (lenient, research R6).
- [X] T027 [P] [US1] Write `apps/mobile/test/core/economy/domain/fuel_refill_rules_test.dart`: the
  `ad_reward` `fuel_refill` payload is `{"ad_placement":"fuel_refill"}`, with no `ref`. It fills to
  the maximum, with `fuelDelta = max − liters` and no reason. It is refused with `tank_full` at or
  above the maximum. In the fold it stays and adds nothing when the tank is full.
- [X] T028 [P] [US1] Write `apps/mobile/test/core/economy/fuel_service_test.dart`, with
  `testEconomy` and fake async. Cover US1 scenarios 1–9:
  - a new player is full;
  - a start spends one liter;
  - one liter per 20 minutes, while open, closed (reopen) and offline;
  - the countdown keeps the counted time;
  - the view's `nextLiterAtMs` and `fullAtMs`;
  - an empty tank refuses a start;
  - a rewarded refill;
  - after reopening, `view.unfinished` is set and no op is written;
  - moving `FakeDeviceClock` ±3 h with the same boot changes nothing.

  Also cover:
  - the next-liter `Timer` emits a view at `nextLiterAtMs`, and re-arms after an op;
  - the timer is cancelled on `AppLifecycleState.paused` and `hidden`, so none fires while the
    app is in the background, and re-armed on `resumed`;
  - `resync()` runs on `AppLifecycleState.resumed`, and `saveLatest()` on `paused`.
- [X] T029 [P] [US1] Write `apps/mobile/test/core/economy/fuel_week_test.dart` (SC-003):
  - seed 20261022; 7 simulated days of starts, rewarded refills, clock changes and restarts, using
    the domain rules directly with `fuel_max 5`, `regen 20`;
  - an independent reference model in the test, counting liters second by second;
  - every simulated minute, liters, `nextLiterAtMs` and `fullAtMs` match it exactly;
  - a clock change while the phone stays on moves none of them.

### Implementation for User Story 1

- [X] T030 [US1] Create `apps/mobile/lib/core/economy/domain/fuel.dart`: `regenerate`, `spendOne`,
  `fillToMax`, `extendUnlimited`, `isUnlimited` and `fuelView`, as in contracts/fuel-and-time.md.
  Name `unlimitedWindowMs = 3600000` after the product `fuel_unlimited_1h`. T025 passes.
- [X] T031 [US1] Create `apps/mobile/lib/core/economy/domain/trip_rules.dart` with the
  `trip_start` rule, and `apps/mobile/lib/core/economy/domain/ad_rules.dart` with the `fuel_refill`
  placement. Register both in `rules.dart`. Every op regenerates fuel to its `occurredAtMs` with its
  recorded tunables before applying. T026 and T027 pass.
- [X] T032 [US1] In `apps/mobile/lib/core/economy/economy_service.dart`, implement `startTrip` and
  `applyAdReward` (for `fuel_refill`), and the `FuelView` regenerated to trusted now with the
  current tunables. Add the next-liter `Timer`, re-armed after each op and each view refresh, and
  cancelled in `dispose`. In `apps/mobile/lib/bootstrap/app.dart`, add an `AppLifecycleListener`
  that calls `trustedClock.resync()` and re-arms the timer on `resumed`. On `paused` it calls
  `trustedClock.saveLatest()`, and on `paused` and `hidden` it cancels the timer (constitution
  budgets: no background work). T028 and T029 pass.

**Checkpoint**: US1 is complete. Fuel limits starts, refills by itself offline, and ignores clock
changes while the phone stays on.

---

## Phase 4: User Story 2 - A finished trip pays and counts, offline (Priority: P1)

**Goal**: Results add their earnings and update progress, and ×2 adds them once (FR-032 to
FR-035).

**Independent Test**: `earnings_service_test.dart` (quickstart scenario 1), and scenario 3's
earning step.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T033 [P] [US2] Write `apps/mobile/test/core/economy/domain/trip_result_rules_test.dart`
  (contracts/operations.md `trip_result`):
  - refusals in order:
    - `result_exists`: `start` is the latest result's start, whose result is already recorded;
    - `no_trip_start`: no unfinished trip, or another start id;
    - `trip_mismatch`;
    - `stars_out_of_bounds`: −1, 4, and 1 on a failed trip;
    - `earnings_out_of_bounds`: −1, `max_earnings_jenehat + 1`, and 5 on an abandoned trip;
  - payload `{"result":<TripResult.toJson()>,"trip_start_txn":"<id>"}`, with reason
    `trip_earnings` and `ref` the start;
  - `jenehatDelta` = earnings;
  - progress:
    - `bestStars` only rises;
    - `bestTimeMs` is the minimum over finished runs only;
    - `plays` rises for every outcome;
    - `firstCompletedAtMs` is set once, by the first finished run;
  - `unfinished` is cleared, and `lastResult` is set;
  - `stillValid` is false when the fold has no matching unfinished start.
- [X] T034 [P] [US2] Write `apps/mobile/test/core/economy/domain/result_double_rules_test.dart`:
  - refusals: `no_result`; `not_doublable` (failed, abandoned, earnings 0); `already_doubled`;
  - `jenehatDelta` = the last result's earnings, with reason `ad_result_double`;
  - payload `{"ad_placement":"result_double","ref":"<start>"}`;
  - `stillValid` is false when the last result is gone or already doubled.
- [X] T035 [P] [US2] Write `apps/mobile/test/core/economy/earnings_service_test.dart`:
  - US2 scenarios 1–5, including the balances after a reopen;
  - **FR-034:** seed progress for `line_hay.99` (not in the sample) and ownership of
    `salon.missing`. Then reading `view.progress` and `view.owns` for every trip and item of the
    sample neither fails nor lists them, and `view.progress['line_hay.99']` is still there.

### Implementation for User Story 2

- [X] T036 [US2] Add the `trip_result` rule to `apps/mobile/lib/core/economy/domain/trip_rules.dart`
  and the `result_double` placement to `apps/mobile/lib/core/economy/domain/ad_rules.dart`.
  T033 and T034 pass.
- [X] T037 [US2] In `apps/mobile/lib/core/economy/economy_service.dart`, implement
  `recordResult`, and `applyAdReward` for `result_double`. Fill `EconomyView.progress` and
  `lastResult`. T035 passes.

**Checkpoint**: US1 and US2 together are the whole economy of the first playable trip (M02).

---

## Phase 5: User Story 3 - Spending JENEHAT and BONAT at the catalog price (Priority: P2)

**Goal**: Every purchase at the active catalog's price, booster use, the in-trip ad rewards, one
charge per intent, and no BONAT path to JENEHAT (FR-012, FR-037 to FR-041).

**Independent Test**: `spending_service_test.dart` and `idempotency_test.dart` (quickstart
scenario 1).

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T038 [P] [US3] Write `apps/mobile/test/core/economy/domain/spend_rules_test.dart`
  (contracts/operations.md `spend_jenehat`, `spend_bonat`; research R13). Use the sample pack, plus
  a fake `ContentSource` with a broken catalog:
  - **for each kind:**
    - `item` with a variant;
    - `vehicle` `micro_old`;
    - `chapter` `ch3_shabka`;
    - `booster` (each of the 4);
    - `fuel` `refuel_full`;
    - `fuel_unlimited` `fuel_unlimited_1h`;
    - `revive` `revive`;
  - check each kind's payload, `price` from the catalog, the version, the deltas and the reason;
  - refusals in order: `not_for_sale`, `catalog_mismatch` (an item priced in BONAT, a booster priced
    in JENEHAT), `unknown_sku`, `unknown_variant`, `already_owned`, `insufficient_funds`;
    - `unknown_sku` covers: an unknown item, vehicle or chapter; `revive` as a booster; a `fuel` SKU
      other than `refuel_full`;
    - `unknown_variant` covers: an item with no variant, an item with an unknown variant, and a
      vehicle with a variant;
  - fuel effects:
    - `refuel_full` fills to the maximum and is refused with `tank_full` on a full tank;
    - `fuel_unlimited_1h` extends a running window by 60 minutes from its end;
  - revive: refused with `no_trip` and `already_revived`. It sets `unfinished.revived`, and its
    payload carries `ref`;
  - `stillValid` is false when the balance would go below 0 or the SKU is already owned.
- [X] T039 [P] [US3] Write `apps/mobile/test/core/economy/domain/booster_rules_test.dart`:
  - `use_booster` refusals in order: `no_trip`, `unknown_sku`, `none_left`;
  - inventory −1;
  - payload `{"booster_id":"<id>","ref":"<start>"}`;
  - `stillValid` is false at 0 left.
- [X] T040 [P] [US3] Write `apps/mobile/test/core/economy/domain/trip_ad_rules_test.dart`:
  - `trip_revive`: refused with `no_trip` and `already_revived`; sets `revived`; references the
    start;
  - `traffic_jam`: refused with `no_trip`, and with `cap_reached` after one per trip;
  - `morning_piggy`: refused with `server_only`.
- [X] T041 [P] [US3] Write `apps/mobile/test/core/economy/domain/direction_test.dart` (FR-012,
  contracts/operations.md "The direction rule"):
  - build one accepted op of every type and placement from a well-stocked state;
  - check that none has `bonatDelta > 0`, and none pairs `bonatDelta < 0` with `jenehatDelta > 0`;
  - check that each BONAT reason (`booster_purchase`, `fuel_purchase`, `revive_purchase`,
    `fuel_unlimited_purchase`) is never on an op with a JENEHAT increase.
- [X] T042 [P] [US3] Write `apps/mobile/test/core/economy/idempotency_test.dart` (SC-004):
  - one purchase sent 100 times with the same id, in sequence and with `Future.wait`, writes one row
    and charges once; every outcome after the first is `OpApplied(repeated: true)`;
  - a request refused with `insufficient_funds` and retried with the same id after earning enough
    applies.
- [X] T043 [P] [US3] Write `apps/mobile/test/core/economy/spending_service_test.dart`, covering US3
  scenarios 1–9 through `buy`, `useBooster` and `applyAdReward`.

### Implementation for User Story 3

- [X] T044 [US3] Create `apps/mobile/lib/core/economy/domain/spend_rules.dart`:
  - the kind-to-currency map as a named constant: `item`, `vehicle` and `chapter` → JENEHAT;
    `booster`, `fuel`, `revive` and `fuel_unlimited` → BONAT;
  - the SKU ids `refuel_full`, `fuel_unlimited_1h` and `revive` as constants;
  - prices only from `RuleContext.content.price`.

  Also create `apps/mobile/lib/core/economy/domain/booster_rules.dart`. Add `trip_revive`,
  `traffic_jam` and `morning_piggy` to `apps/mobile/lib/core/economy/domain/ad_rules.dart`.
  Register everything in `rules.dart`. T038–T041 pass.
- [X] T045 [US3] In `apps/mobile/lib/core/economy/economy_service.dart`, implement `buy`,
  `useBooster` and the remaining `applyAdReward` placements. Fill `EconomyView.inventory`, `owns`
  and `variantOf`. T042 and T043 pass.

**Checkpoint**: Every operation type applies. Purchases use the catalog, and a double tap charges
once.

---

## Phase 6: User Story 4 - Nothing is lost or counted twice (Priority: P2)

**Goal**: Kills, full disks, upgrades and a newer database never lose or half-apply a change, the
balances always equal the fold, and the database stays out of device backup (FR-002 to FR-006,
FR-018).

**Independent Test**: `kill_points_test.dart`, `fold_property_test.dart` and the upgrade tests
(quickstart scenarios 1 and 2), and scenario 3 on a device.

### Tests for User Story 4 ⚠️ (write first, must fail)

- [X] T046 [P] [US4] Write `apps/mobile/test/core/economy/kill_points_test.dart` (SC-002). For each
  op kind, kill at each `EconomyKillPoint` on a temp file and reopen. The state must be exactly the state
  before (or, at `afterCommit`, after), and `findOp` must agree. The op kinds are:
  - `trip_start` (both fuel modes) and `trip_result`;
  - the four applied `ad_reward` placements;
  - `spend_jenehat` (three kinds);
  - `spend_bonat` (four kinds);
  - `use_booster`.
- [X] T047 [P] [US4] Write `apps/mobile/test/core/economy/fold_property_test.dart` (SC-001):
  - 1,000 seeds, starting at 1, each up to 200 random requests (valid and invalid) over the sample
    pack, with a fake clock that advances 0–90 minutes between requests;
  - after every step:
    - the service's state equals `fold(base, stored ops)`;
    - `jenehat == base + Σ jenehatDelta`, and the same for BONAT;
    - no balance is below 0;
  - a failure prints its seed.

  US5's T057 adds rejections and bases.
- [X] T048 [P] [US4] Write `apps/mobile/test/core/storage/upgrade_test.dart`:
  - a test-only `AppDatabase` subclass with `schemaVersion 2`, whose step creates a table and then
    throws, leaves the file at `user_version 1` with every row intact, and the v1 code reopens it;
  - a kill (a throw from a step hook) in a later step keeps the steps before it: a v3 whose second
    step throws leaves the file whole at v2, which the v2 code opens (drift runs migrations outside
    the interceptor, so a failed commit can't be injected there);
  - the generated `test/drift/` tests pass for v1.
- [X] T049 [P] [US4] Write `apps/mobile/test/core/economy/write_failure_test.dart`: SQLITE_FULL
  injected at the op row, at the wallet update and at the commit gives `OpWriteFailed` each time.
  Nothing changes in memory or on disk, and the next request applies (US4 scenario 3).
- [X] T050 [P] [US4] Write `apps/mobile/test/core/economy/debug_fold_check_test.dart`:
  - a consistent file opens;
  - a file whose `wallet.jenehat` was changed by raw SQL in the test fails to open in debug mode
    with `ProjectionMismatch`, which surfaces as the boot error.
- [X] T051 [P] [US4] Write `apps/mobile/test/repo/backup_rules_test.dart` (FR-006, research R14):
  - `android/app/src/main/AndroidManifest.xml`'s `<application>` has
    `android:dataExtractionRules="@xml/data_extraction_rules"` and
    `android:fullBackupContent="@xml/backup_rules"`;
  - `data_extraction_rules.xml` has `<exclude domain="file" path="db/"/>` under both
    `<cloud-backup>` and `<device-transfer>`;
  - `backup_rules.xml` has it under `<full-backup-content>`.
- [X] T052 [P] [US4] Write `apps/mobile/integration_test/economy_offline_test.dart` (SC-007,
  quickstart scenario 3), on the real app with the real channel and file:
  - a fresh install is full;
  - start `line_gamaa.02`, then record a finished result with earnings 50 (`line_hay.01` pays at
    most 20): one liter fewer, JENEHAT 50, progress set;
  - play it twice more, then buy `salon.sitara` (150) with its first variant;
  - restart the app (re-pump `WassalApp` after disposing the scope);
  - everything is unchanged.

### Implementation for User Story 4

- [X] T053 [US4] In `apps/mobile/lib/core/storage/app_database.dart`, add the debug-only
  `beforeOpen` check: fold the base and the stored ops with `ProductionRules`, compare with the
  materialized tables, and throw `ProjectionMismatch` on any difference. Make every migration step
  commit together with its `user_version` bump. T048 and T050 pass. T046, T047 and T049 pass with
  no change, or the store is fixed until they do.
- [X] T054 [US4] Add `apps/mobile/android/app/src/main/res/xml/data_extraction_rules.xml` and
  `apps/mobile/android/app/src/main/res/xml/backup_rules.xml` (contracts/storage.md "Backup
  rules"), and both attributes on `<application>` in
  `apps/mobile/android/app/src/main/AndroidManifest.xml`. T051 passes.

**Checkpoint**: Every write is all or nothing, and the projection always equals the fold.

---

## Phase 7: User Story 5 - Every change is ready for the server (Priority: P3)

**Goal**: M06 can read the pending operations, mark them, roll back rejections with their
dependents, and replace the base (FR-044 to FR-047).

**Independent Test**: `sync_api_test.dart` and the extended property test (quickstart scenario 1).

### Tests for User Story 5 ⚠️ (write first, must fail)

- [X] T055 [P] [US5] Write `apps/mobile/test/core/economy/domain/fold_revalidation_test.dart`. One
  case per row of research R6's table:
  - a rejected booster purchase leaves out the later `use_booster`;
  - a rejected `trip_start` leaves out its result and its ×2;
  - a rejected `trip_result` with earnings leaves out a later purchase that needed them;
  - a rejected ×2 leaves the rest;
  - a rejected revive purchase leaves the trip.

  The lenient cases: after a rejected refill, a later start on an empty tank stays, with fuel held
  at 0; and a later refill on a full tank adds nothing.
- [X] T056 [P] [US5] Write `apps/mobile/test/core/economy/sync_api_test.dart`:
  - `pendingOps(limit: 2)` returns the two oldest pending ops in `seq` order, with the canonical
    payload, `occurredAtMs`, `seq` and `sync_status`;
  - `markAccepted` changes only `sync_status`, and the view is unchanged;
  - `markRejected` stores the reason, rebuilds and emits the rebuilt view;
  - a rejected or accepted op never goes back to `pending`. Marking it again is ignored, and a debug
    assertion fires;
  - `replaceBase(snapshot, afterSeq: n)` makes the view the snapshot plus the non-rejected ops after
    `n`. Ops at or before `n` aren't folded, and the `projection_base` row is `server_snapshot` with
    the given `state_version`;
  - `trustedClock.anchorOnServer` moves the anchor's source to `server`.
- [X] T057 [US5] Extend `apps/mobile/test/core/economy/fold_property_test.dart`: each step may also
  mark a random pending op rejected (10%) or replace the base with the current state at the current
  `seq` (2%). The invariants of T047 still hold, with the left-out ops excluded from the sums.

### Implementation for User Story 5

- [X] T058 [US5] In `apps/mobile/lib/core/economy/drift_economy_store.dart`, add:
  - `pendingOps(limit)`;
  - `setSyncStatus`, through `_setSyncStatus`, refusing to leave `accepted` or `rejected`;
  - `rebuild(FoldResult)`, which replaces `wallet`, `inventory`, `ownership`, `trip_progress` and
    `trip_session` in one transaction;
  - `replaceBase(state, afterSeq, stateVersion)`.

  In `apps/mobile/lib/core/economy/economy_service.dart`, implement `pendingOps`, `markAccepted`,
  `markRejected` (rebuild through `fold`) and `replaceBase`, and map rows to `LedgerOp`. T055, T056
  and T057 pass.

**Checkpoint**: Every story is complete. Everything M06 needs from the device side exists and is
tested.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Performance, documents, coverage, the full quickstart, review, and the owner's items.

- [X] T059 [P] Write `apps/mobile/test/core/economy/perf/startup_budget_test.dart` (SC-005, research
  R18):
  - seed a temp file with 50,000 ops through the store, in batches of 500 per transaction in the
    test's own setup;
  - close it, then measure `AppDatabase` open plus `store.load()`: the median of 5 runs after one
    warm-up is ≤ 150 ms on the CI runner;
  - check that `load()` reads no `ledger_ops` rows, with a counting executor.
- [X] T060 [P] Write `apps/mobile/integration_test/economy_perf_test.dart` (quickstart scenario 5):
  - with 50,000 seeded ops, open plus load ≤ 200 ms;
  - each op kind applies in ≤ 100 ms (the median of 20);
  - it prints the medians.
- [X] T061 [P] Update `docs/architecture-mobile.md` (research R21):
  - **§11:** the tables M05 creates, with `ledger_ops`' columns as research R4 gives them, and
    `clock_anchor`, `projection_base` and `trip_session`; `content_cache` stays M04's
    `state.json` (R15); the database is left out of device backup (R14);
  - **§13:** trusted time (R9, constitution VI as of 1.3.0), replacing "If the device clock jumps
    backward, regeneration pauses until the next bootstrap"; the projection and its fold (R5, R6),
    the fuel rules (R8), and a link to `specs/007-m05-local-economy/contracts/`;
  - **§24.5:** resolved in M05 (research R20).
- [X] T062 [P] Update `docs/architecture-backend.md` (research R21):
  - **§7.2:** add `chapter_purchase` and `fuel_unlimited_purchase`;
  - **§7.4:** the revive's `ref` in `spend_bonat`; `fuel_refill` carries no `ref`, since it belongs
    to no trip; `morning_piggy` is never a client op;
  - **§7.5:** the countdown rule, liters above the maximum are kept, the full refill is refused on a
    full tank, and the window extends from its end. Mark these as M05's rules, which B03 confirms;
  - **§12:** `Ownership.kind` gains `chapter`.

  Leave §3 untouched.
- [X] T063 [P] Update `docs/delivery-plan.md`:
  - **Progress:** `006-m04-content-loader` merged in #7 on 2026-10-21, so tick it and step 4's M04
    line. Add M05's line when its PR merges;
  - **Step 4:** mobile §24.5 resolved in M05 (every start costs a liter, replays included). Add the
    hand-overs to M02, M06, M07, M08–M13, M15, M17 and B03 from research.md "Handed to later
    features".
- [X] T064 [P] Update `CLAUDE.md`:
  - **"Project status":** the app keeps its economy in drift since M05
    (`specs/007-m05-local-economy/`);
  - **"Mobile commands":** `fvm dart run drift_dev make-migrations` after a table change, the
    schema tests in `test/drift/`, and the `sqlite3` hook's one-time SQLite download;
  - the database's place, `<app support>/db/wassal.sqlite`, and that it is left out of backup;
  - the new repo guards in the `flutter test` bullet.
- [X] T065 [P] Add the M05 section to `docs/owner-actions.md`, and update "Open now":
  - **Before merge:** none;
  - **After merge:** T067 (A06 timings, quickstart scenario 5), the clock check (scenario 4), and
    the backup check (scenario 6).
- [X] T066 Run the gates and the quickstart:
  - the coverage gate (`fvm dart run tool/check_coverage.dart --min 80`); add tests for any
    uncovered branch until it passes, and don't exclude files;
  - quickstart scenarios 1 and 2, then scenario 3 on an emulator in airplane mode.

  Record any scenario that needs a device that wasn't available as an owner item in
  `docs/owner-actions.md`.
- [ ] T067 **Owner** (after merge): on the Galaxy A06, run quickstart scenarios 4, 5 and 6, record
  the medians in a follow-up issue, and tick the items in `docs/owner-actions.md`.
- [X] T068 Review the diff:
  - run the `code-reviewer` and `flutter-reviewer` agents on `apps/mobile`;
  - run the `security-reviewer` on `lib/core/economy/`, `lib/core/storage/`,
    `lib/core/platform/uptime.dart`, `MainActivity.kt` and the backup rules. The ledger is on the
    constitution's security-review list;
  - check every changed file against constitution I, II, IV, V, VI, VII, VIII and XIII;
  - fix every CRITICAL and HIGH finding.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies. T001 first; T002 in parallel with it.
- **Foundational (Phase 2)**: depends on Setup.
  - T003 first (the helpers every test uses).
  - Then the tests T004–T016 in parallel.
  - Then T017 → T018 → T019 → T020. T021 can run alongside T017–T020. Then T022 → T023 → T024.
- **US1 (Phase 3)**: depends on Foundational. Tests T025–T029 in parallel, then T030 → T031 → T032.
- **US2 (Phase 4)**: depends on US1 (`trip_rules.dart`, `ad_rules.dart`, `economy_service.dart`,
  and results need starts). Tests T033–T035 in parallel, then T036 → T037.
- **US3 (Phase 5)**: depends on US1 (revive, booster use and in-trip ads need an unfinished trip).
  Its spending tests don't need US2, but `ad_rules.dart` and `economy_service.dart` are shared, so
  it runs after US2. Tests T038–T043 in parallel, then T044 → T045.
- **US4 (Phase 6)**: depends on US1–US3, because its kill-point and property tests cover every
  operation type. T051 and T054 (backup) depend only on Foundational and can go any time. Tests
  T046–T052 in parallel, then T053 and T054.
- **US5 (Phase 7)**: depends on US4's property test (T047) and the store. T055 and T056 in
  parallel, then T057, then T058.
- **Polish (Phase 8)**: after every story. T059–T065 in parallel, then T066 → T068. T067 is the
  owner's, after merge.

### Within Each User Story

- Tests first, and they must fail.
- The shared files grow in order US1 → US2 → US3: `rules.dart`, `trip_rules.dart`,
  `ad_rules.dart` and `economy_service.dart`. `drift_economy_store.dart` grows in Foundational,
  then in US5.
- Run `build_runner` after every provider or table change, and `make-migrations` after every table
  change.

### Parallel Opportunities

- **Foundational:** the tests T004–T016 touch different files, and T021 (uptime and the Kotlin
  channel) is independent of T017–T020.
- **US1:** T025–T029.
- **US2:** T033–T035.
- **US3:** T038–T043.
- **US4:** T046–T052. T051 with T054 can be done at any point after Foundational.
- **US5:** T055 and T056.
- **Polish:** T059–T065.

---

## Parallel Example: Foundational tests

```text
T004 test/repo/domain_imports_test.dart
T005 test/repo/integer_money_test.dart
T006 test/repo/economy_writes_test.dart
T007 test/repo/sqlite_dependency_test.dart
T008 test/core/economy/domain/txn_id_test.dart + test/core/economy/txn_ids_test.dart
T009 test/core/economy/domain/economy_state_test.dart
T010 test/core/economy/domain/trusted_time_test.dart
T011 test/core/storage/app_database_test.dart
T012 test/core/platform/uptime_test.dart
T013 test/core/economy/trusted_clock_test.dart
T014 test/core/economy/store_test.dart
T015 test/core/economy/economy_service_test.dart
T016 test/bootstrap/economy_startup_test.dart
```

## Parallel Example: User Story 3

```text
T038 test/core/economy/domain/spend_rules_test.dart
T039 test/core/economy/domain/booster_rules_test.dart
T040 test/core/economy/domain/trip_ad_rules_test.dart
T041 test/core/economy/domain/direction_test.dart
T042 test/core/economy/idempotency_test.dart
T043 test/core/economy/spending_service_test.dart
```

---

## Implementation Strategy

### MVP First (User Story 1, then 2)

1. Phase 1 and Phase 2.
2. Phase 3 (US1): fuel.
3. Phase 4 (US2): earnings. With US1, this is everything the first playable trip (M02) needs.
4. **Stop and validate**: quickstart scenario 1 for the fuel and earnings tests, and the delivery
   plan's "the wallet, `ledger_ops` and fuel regeneration all work offline".

### Incremental Delivery

1. US1 + US2: the trip economy, the MVP.
2. US3: purchases, which step 7's screens (M08–M12) need.
3. US4: the proof that nothing is lost. Ship it with US1–US3: an economy that can lose savings
   isn't shippable.
4. US5: the sync surface. M06 builds on it, and its tests run here.
5. Polish, review, then merge as one PR.

### Notes

- **[P]** tasks are in different files with no dependencies on incomplete tasks.
- Never edit a generated file: drift's and Riverpod's `*.g.dart`, `drift_schemas/` (only
  `make-migrations` writes it) and `test/drift/`.
- Never stash, reset or discard to get past a failing hook. Ask the owner.
- Commit after each task or logical group, with Conventional Commits.
