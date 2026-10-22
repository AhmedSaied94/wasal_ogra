# Quickstart: Local Economy (M05)

How to check that M05 works. Commands run in `apps/mobile` unless noted. The contracts hold the
rules: [economy-api.md](./contracts/economy-api.md), [operations.md](./contracts/operations.md),
[fuel-and-time.md](./contracts/fuel-and-time.md) and [storage.md](./contracts/storage.md).

## Setup

```bash
# Once after checkout: the generated content models, then the app.
(cd ../../packages/content_models && fvm dart pub get && fvm dart run build_runner build -d)
fvm flutter pub get                     # also fetches drift, sqlite3, uuid and trip_engine
fvm dart run build_runner build -d      # Riverpod and drift code
```

The first `flutter test` or build after a `sqlite3` version change downloads that version's SQLite
binary from the package's GitHub release, so it needs the network once.

## Scenario 1: everything automated (CI)

```bash
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm flutter analyze --fatal-infos
fvm flutter test --coverage
fvm dart run tool/check_coverage.dart --min 80
```

**Expected.** All green. In particular:

- `test/core/economy/domain/`: every operation's accept and refuse cases, the fuel arithmetic,
  trusted time and the direction rule;
- `test/core/economy/fold_property_test.dart`: 1,000 seeded sequences, with zero mismatches
  (SC-001);
- `test/core/economy/kill_points_test.dart`: each kill point of each operation leaves the operation
  whole or absent (SC-002);
- `test/core/economy/idempotency_test.dart`: 100 repeats charge once (SC-004);
- `test/core/economy/fuel_week_test.dart`: 7 simulated days match the rules to the second (SC-003);
- `test/core/economy/perf/startup_budget_test.dart`: 50,000 operations, startup read ≤ 150 ms on the
  runner (SC-005, CI budget);
- `test/drift/`: the v1 schema matches the exported one;
- `test/repo/`: domain imports, economy writes, integer money and no `REAL` columns, and the backup
  rules (SC-008, FR-006, FR-013).

## Scenario 2: a schema change is caught

1. Add a column to any economy table without running `make-migrations`.
2. Run `fvm flutter test test/drift`. **Expected:** the schema test fails.
3. Revert.

## Scenario 3: offline play on a device (SC-007)

On a phone or emulator in airplane mode, with a dev build:

```bash
fvm flutter test integration_test/economy_offline_test.dart --flavor dev
```

**Expected.** The test:

1. starts a fresh install with a full tank;
2. plays `line_gamaa.02` (one liter fewer per start, 50 JENEHAT per finished result, progress
   set) three times;
3. buys the sample's `salon.sitara` (150 JENEHAT) with a style;
4. restarts the app;
5. finds every balance, the ownership, the progress and the tank unchanged: a relaunch takes
   seconds, and a liter 20 minutes.

## Scenario 4: the clock can't be moved (the second clarification)

On a dev build on a device:

1. Open the app, spend a liter (from a test hook or, after M02, a trip). Note the next-liter time.
2. With the phone on, set the system clock 3 hours ahead and reopen the app. **Expected:** the
   liters and the next-liter time are unchanged.
3. Set the clock back to the right time, restart the phone, and wait 20 minutes. **Expected:** one
   liter came back.

## Scenario 5: performance on the Galaxy A06 (owner)

```bash
fvm flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/economy_perf_test.dart --flavor dev --profile
```

**Expected.** With 50,000 seeded operations, opening the database and reading the balances takes
≤ 200 ms (SC-005), and each kind of operation applies in ≤ 100 ms (SC-006). The cold start to Home
stays ≤ 3 s (`tool/perf/cold_start.sh`, M03).

## Scenario 6: backup exclusion (owner)

```bash
adb shell bmgr backupnow com.wassalogra.app.dev
adb shell bmgr list sets
```

Or follow Android's "Test backup and restore" steps with `adb shell bmgr restore`. **Expected:**
after a restore, the app starts as a new player, with a full tank and 0 JENEHAT, while the digit
setting is restored.

## Done when

- [ ] Scenario 1 is green in CI.
- [ ] Scenario 3 passes on a device in airplane mode.
- [ ] Scenarios 4–6 are checked on the Galaxy A06 (owner actions, added to
  `docs/owner-actions.md` at `/speckit-implement`).
- [ ] The documents in research R21 are updated.
