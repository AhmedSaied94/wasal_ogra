# Contract: Storage

The app database, its migrations, the backup rules, the guards and CI. Tables are in
[data-model.md](../data-model.md).

## The file and its connection

| | |
| --- | --- |
| Path | `<getApplicationSupportDirectory()>/db/wassal.sqlite`, plus its `-wal` and `-shm` files |
| Class | `AppDatabase extends _$AppDatabase` in `lib/core/storage/app_database.dart` |
| Connection | `openDatabaseFile(file)` in `connection.dart`: `NativeDatabase.createInBackground(file, setup: configureConnection)` (research R2) |
| Pragmas | `journal_mode = WAL`, `synchronous = FULL`, `foreign_keys = ON` |
| Tests | the constructor takes any `QueryExecutor`: `NativeDatabase.memory()`, or a temp file to reopen |

Nothing deletes, renames or recreates the file (FR-004).

## Migrations

- `schemaVersion = 1`. `drift_schemas/app/drift_schema_v1.json` is committed.
- `onCreate`: create every table and the first rows (data-model.md "First open") and set
  `user_version`, in one transaction. A first open holds a new player: balances and fuel, nothing
  owned or played.
- `onUpgrade(from, to)`:
  - if `from > to`, throw `DatabaseFromNewerApp(from, to)`, before any statement;
  - otherwise run each entry of `upgradeSteps` from `from + 1` to `to`, each in its own
    transaction with its `user_version` bump, so a failure or a kill leaves the previous version
    whole.
- `beforeOpen`: the injected `openCheck`, which the app sets in debug builds only: compare the
  materialized tables with the fold (research R5), and throw `ProjectionMismatch`.
- After a schema change, run `fvm dart run drift_dev make-migrations` in `apps/mobile`. It writes
  the new `drift_schemas/app/drift_schema_vN.json`, the step helper and the verification tests
  under `test/drift/`. Commit all three. With a single version it writes no tests, so v1's schema
  helpers come from `fvm dart run drift_dev schema generate drift_schemas/app/
  test/drift/app/generated/`, and `test/drift/app/schema_v1_test.dart` checks v1.

A failure to open, migrate or read fails `appStartupProvider`. The boot screen shows M03's failure
state with a retry (FR-003, FR-004).

## Backup rules (research R14, FR-006)

`android/app/src/main/AndroidManifest.xml`, on `<application>`:

```xml
android:dataExtractionRules="@xml/data_extraction_rules"
android:fullBackupContent="@xml/backup_rules"
```

`res/xml/data_extraction_rules.xml` (Android 12+):

```xml
<data-extraction-rules>
  <cloud-backup><exclude domain="file" path="db/"/></cloud-backup>
  <device-transfer><exclude domain="file" path="db/"/></device-transfer>
</data-extraction-rules>
```

`res/xml/backup_rules.xml` (Android 11 and earlier):

```xml
<full-backup-content><exclude domain="file" path="db/"/></full-backup-content>
```

`path_provider`'s application support directory on Android is the `file` domain (`files/`).

## Guards (`test/repo/`)

| Guard | Checks |
| --- | --- |
| `domain_imports_test.dart` (extended) | Each domain folder imports only its allowed list. `lib/core/economy/domain/`: `dart:core`, `dart:collection`, `package:content_models/`, `package:trip_engine/`, `package:wassal/core/content/domain/`, and relative imports inside the folder. |
| `economy_writes_test.dart` (new) | Only `lib/core/economy/drift_economy_store.dart` calls `into(`, `update(`, `delete(`, `batch(` or `customStatement(` on the economy tables, `clock_anchor` included. Only `lib/core/storage/`, that store and `lib/core/economy/economy_providers.dart` import `app_database.dart`; the providers file only constructs the database and the store. `ledger_ops` is updated only in `sync_status` and `sync_reason`. |
| `integer_money_test.dart` (extended) | No `real()` column or `RealColumn` under `lib/core/storage/`. |
| `backup_rules_test.dart` (new) | The manifest names both XML files, and each excludes `db/` in every section. |

## CI

- No new job. `build_runner` already runs in the app's jobs and now also generates drift's code.
- The `sqlite3` build hook downloads its SQLite binary from GitHub on the runner's first build of a
  version, and checks it against the package's sha256.
- `flutter test` runs the schema-verification tests and the guards with everything else.
- The coverage gate stays at 80%. drift's generated `*.g.dart` is already excluded with the other
  generated parts.
