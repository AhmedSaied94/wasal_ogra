---

description: "Task list for M06 Identity, Bootstrap and Sync"
---

# Tasks: Identity, Bootstrap and Sync (M06)

**Input**: Design documents from `specs/011-m06-identity-sync/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first** (constitution XIII). Tests come first for the token rules, the rebase,
  the state mapping, the comeback guard and the sync's refusal handling. Every phase writes its
  tests first, and they must fail before its implementation tasks start.
- **Real SQLite, fake edges.** Store and service tests use real drift databases
  (`NativeDatabase.memory()`, or a temp file when a test reopens it). Only the platform edges are
  faked:
  - the network (`FakeApi`, an `ApiClient`);
  - the install id and session stores (memory);
  - the route signal, the connectivity source, the uptime source and the store launcher.
- **Against the real stack.** `test/backend/` (tag `backend`) runs against the dev compose stack,
  with no Flutter test binding, so `dart:io` HTTP is real. CI runs it in the new `sync-e2e` job.
- **Coverage.** At least 80% of lines in `apps/mobile` (`tool/check_coverage.dart`).

**Organization**:

- **Paths** are from the repository root. Dart commands run with `fvm` in `apps/mobile/`.
- **Codegen.**
  - After adding or changing a `@riverpod` provider or a drift table, run
    `fvm dart run build_runner build -d`.
  - After the v3 tables, run `fvm dart run drift_dev make-migrations` and commit its output.
  - Before any app test, build `packages/content_models`.
- **Exactness.** Every number is from the contracts. Name each as a constant in `lib/`, never as a
  bare literal. The list:
  - `firstOpenWait` 3 s; the 60 s renewal margin and retry window;
  - 100 operations and 200 KiB per batch; ≥ 1 s between batches;
  - backoff 2 s doubling to 5 min, ±20%; the 2 s debounce;
  - 60 s between bootstraps; the 15 s link flush;
  - the timeouts in contracts/api-client.md.

  Wire names are the contracts', spelled exactly.
- **Shared files.** These grow story by story, so tasks that touch them are sequential:
  - `lib/core/economy/economy_service.dart`, `drift_economy_store.dart` and `economy_sync.dart`;
  - `lib/core/sync/sync_engine.dart`;
  - `lib/core/account/account_service.dart`;
  - `lib/core/storage/tables.dart`;
  - `lib/bootstrap/app.dart`;
  - `lib/core/routing/router.dart`;
  - `lib/l10n/app_ar.arb`.
- **One PR**, with a security review: auth, the ledger and sync (plan "Security & privacy").

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US6 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Dependencies, the test tag and the Gradle library (research R24).

- [X] T001 Update `apps/mobile/pubspec.yaml`:
  - add `flutter_secure_storage: ^11.2.0` and `url_launcher: ^6.3.3`, each with a comment naming
    research R2 or R18;
  - add `shared_preferences_android: ^2.5.1` as a direct dependency (it is transitive today), with
    a comment naming research R1: `AndroidInstallIdStore` imports its Android options to write
    `wassal_install.xml`;
  - run `fvm flutter pub get` and commit `pubspec.lock`;
  - confirm both iOS plugins come in as Swift Packages, with no `ios/Podfile` created (CLAUDE.md
    "iOS builds").
- [X] T002 [P] Add `implementation("com.google.android.gms:play-services-auth-blockstore:16.4.0")`
  to `apps/mobile/android/app/build.gradle.kts`, with a comment citing research R1, and check that
  `fvm flutter build apk --flavor dev --debug` still builds.
- [X] T003 [P] Add the `backend` tag to `apps/mobile/dart_test.yaml`, with a comment: "the dev
  compose stack must be running; `WASSAL_E2E_API` defaults to `http://localhost:8000`". Add
  `--exclude-tags backend` to the `flutter test` step of `.github/workflows/mobile.yml`'s `app` job,
  and to the "All tests" row of `CLAUDE.md`'s mobile commands.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database v3, the economy's split interface, the API client and wire readers, the
account store, and the guards. Every story needs these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Test helpers

- [X] T004 [P] Create `apps/mobile/test/helpers/fake_api.dart`: `FakeApi implements ApiClient`.
  - It takes a script of answers per `(method, path)`: `ApiOk(json)`, `ApiFailure(status, code,
    details, retryAfter)`, `ApiUnreachable(kind)`.
  - It can delay an answer, or "drop" one (the request reaches a recorded log, and the caller sees
    `ApiUnreachable.timeout`).
  - It records every request (path, body, bearer) for assertions.
- [X] T005 [P] Create `apps/mobile/test/helpers/account.dart`:
  - `MemoryInstallIdStore` and `MemorySessionStore`;
  - a `FakeRouteSignal` (`onTripScreen` as a `ValueNotifier<bool>`);
  - a `FakeStoreLauncher`;
  - a builder for an in-memory `AppDatabase` at schema v3, with M05's `test/helpers/economy.dart`
    service on it.

### Guards: tests first

- [X] T006 [P] Create `apps/mobile/test/repo/economy_sync_access_test.dart`. It fails when
  `economySyncProvider`, `EconomySync` or any of `applyAnswer`, `replaceFromServer`,
  `adoptAccount`, `setAside` or `grantComebackGift` appears in `lib/` outside
  `lib/core/sync/`, `lib/core/account/` and `lib/core/economy/` (contracts/ci-checks.md).
- [X] T007 [P] Extend `apps/mobile/test/repo/economy_writes_test.dart`: only
  `lib/core/account/drift_account_store.dart` may write the `account` and `server_info` tables. The
  economy tables' rule is unchanged, and `ledger_ops` still changes only in `sync_status` and
  `sync_reason`.
- [X] T008 [P] Create `apps/mobile/test/repo/no_secret_logging_test.dart`. It fails when:
  - a `print`, `debugPrint`, `log(`, `FlutterError.report…`, `developer.log` or string
    interpolation passed to them in `lib/` mentions `access`, `refresh`, `installId`, `install_id`
    or a `Session` value;
  - `LogInterceptor` appears anywhere in `lib/`;
  - a `SharedPreferences` or `SettingsStore` key in `lib/` contains `token`, `session`, `access`,
    `refresh` or `install`. Android's own `wassal_install.xml` is written by Kotlin and is outside
    the scan.
- [X] T009 [P] Extend `apps/mobile/test/repo/backup_rules_test.dart`. Both XML files must:
  - exclude `db/` from cloud backup **and** device transfer, as today;
  - exclude, in the same places, the four `sharedpref` files `flutter_secure_storage` 11.2.0 writes
    with no `storageNamespace` (research R2): `FlutterSecureStorage.xml`,
    `FlutterSecureKeyStorage.xml`, `FlutterSecureStorageConfiguration.xml` and
    `FlutterSecureStorageConfiguration:FlutterSecureStorage.xml`;
  - have no `<include>` element, since one would limit the backup to the listed files and drop the
    settings file;
  - not exclude `wassal_install.xml`, which the default backup carries.

  A comment says a plugin upgrade must re-check the four names. The test must fail now.
- [X] T010 [P] Extend `apps/mobile/test/repo/domain_imports_test.dart`:
  `lib/core/account/domain/` and `lib/core/sync/domain/` may import only `dart:core`,
  `dart:convert`, `dart:collection`, `package:content_models`, and the economy and content domain
  folders.

### Database v3 and the economy's sync interface: tests first

- [X] T011 [P] Create `apps/mobile/test/core/storage/schema_v3_test.dart`:
  - a new database has one `account` row (`id = 1`, `status = 'none'`, `providers = '[]'`) and one
    empty `server_info` row (`comeback_claimable = 0`);
  - `projection_base.player_id` is nullable TEXT;
  - `ownership.acquired_by` accepts NULL;
  - every new column is INTEGER or TEXT.

  The generated `test/drift/app/migration_test.dart` (T018) covers v2 → v3 with rows kept.
- [X] T012 [P] Extend `apps/mobile/test/core/economy/domain/economy_state_test.dart`: `Owned` with
  `acquiredBy: null` round-trips through `toJson` and `fromJson` and compares equal. Owning
  requirements are unchanged (an item needs a variant).
- [X] T013 [P] Create `apps/mobile/test/core/economy/economy_sync_test.dart` against
  `EconomySync` on a real database:
  - `baseInfo` starts `(stateVersion: null, playerId: null)`;
  - `pendingCount` and `pendingCounts` follow committed operations;
  - `pendingOps` keeps `seq` order;
  - `highestAnsweredSeq` is 0, then follows answers;
  - `setAside({id: 'validation_error'})` marks the row rejected with that reason and refolds, so
    the projection loses its effects;
  - a lifecycle `resumed` issued during a pending `buy` runs after it (the serial queue, R20).
- [X] T014 [P] Update M05's tests that call `markAccepted`, `markRejected` or `replaceBase` through
  `Economy` (`apps/mobile/test/core/economy/`) to call the store or `EconomySync`. They must not
  compile until T020 moves the methods.

### Database v3 and the economy's sync interface: implementation

- [X] T015 Add to `apps/mobile/lib/core/storage/tables.dart` (data-model.md "Tables (schema v3)"):
  - **`AccountTable`**: `id` INTEGER PK "always 1"; `status` TEXT CHECK in
    (`none`,`active`,`deleted`); `player_id` TEXT NULL; `providers` TEXT "a JSON array, `[]`
    until a token answer says otherwise"; `display_name` TEXT NULL; `driver_level` INTEGER NULL;
    `first_open_at_ms` INTEGER NULL; `restored_at_ms` INTEGER NULL; `updated_at_ms` INTEGER.
  - **`ServerInfoTable`**: `id` INTEGER PK; `received_at_ms`, `server_time_ms`, `state_version`
    and `content_version`, each INTEGER NULL; `client`, `entitlements` and `daily`, each TEXT NULL
    (canonical JSON); `comeback_claimable` INTEGER "0 or 1"; `comeback_claimed_at_ms` and
    `comeback_answered_at_ms`, each INTEGER NULL.
  - **`ProjectionBaseTable`**: add `player_id` TEXT NULL.
  - **`OwnershipTable`**: make `acquired_by` nullable.
- [X] T016 Bump `schemaVersion` to 3 in `apps/mobile/lib/core/storage/app_database.dart`, and add
  v3's step to `upgradeSteps`:
  - create `account`, inserting `(1, 'none', '[]', …)`;
  - create `server_info`, inserting `(1, comeback_claimable 0)`;
  - add `projection_base.player_id`;
  - rebuild `ownership` with a nullable `acquired_by` through drift's `TableMigration`, keeping every
    row.

  `onCreate` inserts the same two rows.
- [X] T017 Make `Owned.acquiredBy` a `TxnId?` in
  `apps/mobile/lib/core/economy/domain/economy_state.dart` (JSON `acquired_by` may be null), and
  read and write it in `drift_economy_store.dart`. Spend rules keep setting it to the op's id.
- [X] T018 Run `fvm dart run build_runner build -d` and `fvm dart run drift_dev make-migrations` in
  `apps/mobile`. Commit `drift_schemas/app/drift_schema_v3.json` and the generated
  `test/drift/app/` files. Run `fvm flutter test test/drift` until T011 and the generated migration
  test pass.
- [X] T019 Create `apps/mobile/lib/core/economy/economy_sync.dart` with the `EconomySync` interface
  exactly as contracts/sync.md "`EconomySync`":
  - `baseInfo`, `pendingCount`, `pendingCounts`, `pendingOps({limit = 100})`, `highestAnsweredSeq`;
  - `applyAnswer`, `replaceFromServer`, `adoptAccount`, `setAside`, `grantComebackGift`.

  Add `AnswerApplied` (`leftOutAccepted: List<TxnId>`, `before: EconomyView`,
  `after: EconomyView`).
- [X] T020 Move `pendingOps`, `markAccepted`, `markRejected` and `replaceBase` off `Economy` in
  `apps/mobile/lib/core/economy/economy.dart`. `EconomyService` implements `EconomySync` too
  (`apps/mobile/lib/core/economy/economy_service.dart`). For now, implement `baseInfo`,
  `pendingCount`, `pendingCounts`, `pendingOps`, `highestAnsweredSeq` and `setAside`, the last
  through the store's `rebuild(rejected:)`. Leave the others throwing `UnimplementedError` until
  their story. Route `handleLifecycle`'s clock resync and `TrustedClock.anchorOnServer` through
  `_serial` (R20). Make T013 and T014 pass.
- [X] T021 Add `economySyncProvider` to `apps/mobile/lib/core/economy/economy_providers.dart`, on
  the same `EconomyService` instance as `economyProvider`, with a doc comment that only
  `lib/core/sync/` and `lib/core/account/` read it. Make T006 pass.

### The API client and the wire readers: tests first

- [X] T022 [P] Create `apps/mobile/test/core/network/api_client_test.dart`. `DioApiClient` over a
  Dio test adapter:
  - `ApiOk` with the JSON, and the elapsed times at send and receive;
  - an envelope error becomes `ApiFailure(status, code, details)`;
  - a non-envelope error body is `server_error`;
  - `Retry-After` is parsed into `retryAfter`;
  - a `2xx` non-object body is `server_error`;
  - a timeout, a connection error and DNS each give `ApiUnreachable` of their kind;
  - the bearer header is present only when given;
  - the headers `X-Client-Version` (with the build) and `X-Platform` are always present;
  - an `http://` URL on staging is refused by the URL check;
  - the timeouts follow contracts/api-client.md "Timeouts".
- [X] T023 [P] Create `apps/mobile/test/core/sync/domain/wire_test.dart` for the readers in
  `lib/core/sync/domain/wire/`:
  - `TokenPair`, with and without `created`;
  - `ServerWallet`, with times with and without milliseconds, and `fuel_unlimited_until` null;
  - `BootstrapSnapshot` with the neutral blocks;
  - `StateSnapshot` with `open_trip` and `last_result` null and present, and `story`, `grants` and
    `stats` kept raw;
  - `SyncAnswer` with `granted`, an unknown `reason`, and `state_stale`;
  - the 409 `provider_in_use` details.

  Each must refuse a float, a boolean or a string where an integer is expected, and must ignore
  unknown fields.

### The API client and the wire readers: implementation

- [X] T024 Create `apps/mobile/lib/core/network/api_client.dart`:
  - `ApiClient`, `ApiRequest`, the sealed `ApiResult` (`ApiOk`, `ApiFailure`, `ApiUnreachable`
    with `UnreachableKind { noConnection, timeout, dns }`) and `DioApiClient`, built on
    `createHttpClient(flavor, info)`;
  - the bearer per request; no logging interceptor;
  - elapsed times from M05's `UptimeSource` (or a stopwatch where it's absent);
  - a provider `apiClientProvider`.

  Update the comment at the top of `apps/mobile/lib/core/network/http_client.dart`: the player token
  is added per request by `AuthorizedApi`, and the content endpoints stay public. Make T022 pass.
- [X] T025 Create the strict readers in `apps/mobile/lib/core/sync/domain/wire/`:
  - `token_pair.dart`, `server_wallet.dart`, `bootstrap.dart`, `state.dart`, `sync_answer.dart`
    and `link.dart`, plus `iso_time.dart` (ISO-8601 UTC → integer ms);
  - the domain values of data-model.md "Domain values", in `apps/mobile/lib/core/account/domain/`
    (`InstallId`, `Session` whose `toString()` prints only the player id, `AccountStatus`,
    `Profile`, `FirstOpenOutcome`, `LinkOutcome`, `ConflictSummary`) and
    `apps/mobile/lib/core/sync/domain/` (`SyncBatch`, `PassOutcome`, `SyncTrigger`).

  Make T023 and T010 pass.

### The account store: tests first, then implementation

- [X] T026 [P] Create `apps/mobile/test/core/account/drift_account_store_test.dart`:
  - read and write the profile and status, with `updated_at_ms` set;
  - `first_open_at_ms` is set once and never changed;
  - write the bootstrap cache, and read it back synchronously after `load()`;
  - set `comeback_claimed_at_ms` and `comeback_answered_at_ms`;
  - every write is one transaction.
- [X] T027 Create `apps/mobile/lib/core/account/drift_account_store.dart`, the only writer of
  `account` and `server_info` (data-model.md), plus `apps/mobile/lib/core/account/account_providers.dart`
  with `accountStoreProvider`. Make T026 and T007 pass.

**Checkpoint**: Schema v3 migrates, the guards are green, the economy exposes `EconomySync`, and
the API client and readers are tested. User stories can begin.

---

## Phase 3: User Story 1 - An account appears in the background and stays (Priority: P1) 🎯 MVP

**Goal**: An install id kept across re-installs, an anonymous account created in the background,
and a session that renews itself and signs in again by B02's rules.

**Independent Test**: A fresh install with the network off plays its first trip. With the network
on, an account exists within seconds, with no screen shown. A restart reuses it, and a re-install
on the same phone gets the same player (spec US1; quickstart Part B 1–3, 7).

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T028 [P] [US1] Create `apps/mobile/test/core/account/install_id_store_test.dart` (contracts/account.md
  "Stores"). Against a mock `wassal/install_id` channel and an in-memory preference file:
  - read order Block Store → `wassal_install.xml` → new;
  - whichever store lacks the id is written;
  - a channel error or `null` falls back to the file;
  - a new id is a lowercase v4 (`InstallId.parse` accepts it; version nibble 4);
  - `CryptoRNG` is used;
  - two `readOrCreate` calls on a fresh install return the same id.

  Also cover the iOS store over a fake keychain, with the key `wassal.install_id`.
- [X] T029 [P] [US1] Create `apps/mobile/test/core/account/session_store_test.dart`:
  - `wassal.session` is written in one call holding `player_id`, `access`, `refresh` and
    `access_expires_at_ms`;
  - `read` after `write` returns it;
  - `clear` removes it;
  - a corrupted value reads as null;
  - the iOS options are `first_unlock_this_device` and not synchronizable;
  - the Android options leave `storageNamespace` unset, so the plugin writes the four files the
    backup rules exclude (T009).
- [X] T030 [P] [US1] Create `apps/mobile/test/core/account/authorized_api_test.dart`, with one test
  per row of contracts/api-client.md "The token rules", against `FakeApi` and a fake trusted clock:
  - no session → sign in first;
  - < 60 s left → renew first;
  - a lost renewal → the same refresh token retried at most twice within 60 s, then sign in;
  - the renewal pair is stored before the next call;
  - `token_expired` → renew and repeat once;
  - `token_invalid` → renew once, repeat once, a second one → sign in;
  - renewal `token_expired` or `token_invalid` → sign in;
  - `403 account_deleted` → status deleted, and later calls answer it without a request;
  - three concurrent callers → one renewal;
  - creation `429` → waits `retry_after_s`.
- [X] T031 [P] [US1] Create `apps/mobile/test/core/account/account_service_test.dart` for US1's part
  (contracts/account.md):
  - `ensureSession` creates the account with `{install_id, platform, locale: "ar-EG"}` and sets
    `status = active`, the player and the providers;
  - a second `ensureSession` makes no request;
  - a creation that fails (a `5xx`, or unreachable) leaves the status `none` and returns false, the
    next `ensureSession` tries again, and play goes on (FR-004; the waits between tries are the
    sync's backoff, T045);
  - a restart (new service, same stores) reuses the session;
  - the request body never contains the install id outside `POST /v1/auth/anonymous` (assert over
    `FakeApi`'s log);
  - `firstOpen()` on a `none` row: it clears `wassal.session` first, answers `offline` when the
    link is down, and `newPlayer` on `created: true`; on a later launch it answers `notFirstOpen`
    with no request.
- [X] T032 [P] [US1] Create `apps/mobile/test/features/boot/first_open_wait_test.dart` (R6):
  - the boot screen hands over at once on a later launch;
  - on a first open with a network it waits for `firstOpen()` up to `firstOpenWait` (3 s) after
    startup completes, and hands over as soon as `newPlayer` arrives;
  - past 3 s it hands over with `timedOut`;
  - with no network there is no wait;
  - the road bar's `account` step completes when the wait ends;
  - boot calls `AccountService.handOver()` just before it navigates.
- [X] T033 [P] [US1] Create the backend e2e base: `apps/mobile/test/backend/e2e.dart` builds the app's
  account and sync services on an in-memory database against `WASSAL_E2E_API`, with no Flutter test
  binding. Then create `apps/mobile/test/backend/session_recovery_test.dart` (tag `backend`,
  scenario 3 of R23):
  - create an account;
  - end its sessions through `apps/mobile/test/backend/backend_shell.dart`, which runs
    `docker compose … exec -T api uv run manage.py shell -c …`;
  - expire the access token by advancing the fake trusted clock;
  - check that the next call signs in again and gets the same `player_id`.

### Implementation for User Story 1

- [X] T034 [US1] Add the `wassal/install_id` method channel to
  `apps/mobile/android/app/src/main/kotlin/com/wassalogra/app/MainActivity.kt`, next to
  `wassal/clock`:
  - `read` uses `Blockstore.getClient(context).retrieveBytes` for the key
    `com.wassalogra.install_id`, returning a UTF-8 string or null on any failure;
  - `write({id})` uses `storeBytes` with that key, and `setShouldBackupToCloud(true)` only when
    `isEndToEndEncryptionAvailable()` is true, returning `true` or `false`;
  - neither method throws to Dart.
- [X] T035 [US1] Create `apps/mobile/lib/core/account/install_id_store.dart`:
  - `InstallIdStore`;
  - `AndroidInstallIdStore`: the channel, then the key `install_id` in `wassal_install.xml`, through
    `SharedPreferencesAsync(options: SharedPreferencesAsyncAndroidOptions(backend:
    SharedPreferencesAndroidBackendLibrary.SharedPreferences, originalSharedPreferencesOptions:
    AndroidSharedPreferencesStoreOptions(fileName: 'wassal_install')))` (research R1);
  - `KeychainInstallIdStore` (`flutter_secure_storage`, key `wassal.install_id`,
    `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false)`);
  - `MemoryInstallIdStore`;
  - new ids via `Uuid().v4(config: V4Options(null, CryptoRNG()))`.

  Make T028 pass.
- [X] T036 [US1] Create `apps/mobile/lib/core/account/session_store.dart`: `SessionStore`,
  `SecureSessionStore` (key `wassal.session`, one JSON value, the iOS options of T035, Android
  `resetOnError` left on) and `MemorySessionStore`. Make T029 pass.
- [X] T037 [US1] Update both backup XMLs, `apps/mobile/android/app/src/main/res/xml/data_extraction_rules.xml`
  and `backup_rules.xml`:
  - exclude the four secure storage files T009 names (`domain="sharedpref"`) from cloud backup and
    device transfer;
  - add no `<include>`, so `wassal_install.xml` and the settings file stay in the default backup;
  - keep `db/` excluded;
  - each comment cites research R1 and R2.

  Make T009 pass.
- [X] T038 [US1] Create `apps/mobile/lib/core/account/authorized_api.dart`, implementing
  contracts/api-client.md "The token rules":
  - the 60 s margin on trusted time;
  - a single-flight renewal;
  - the retry window measured on the uptime stopwatch;
  - repeat-once on `401`;
  - sign-in through `AccountService`;
  - `account_deleted` handling;
  - token answers stored before use.

  Make T030 pass.
- [X] T039 [US1] Create `apps/mobile/lib/core/account/account_service.dart`: `AccountService` with
  `status`, `statuses`, `profile`, `ensureSession`, `handOver()` and `firstOpen()`.
  - `firstOpen()` covers `notFirstOpen`, `offline` and `newPlayer` now; US3 adds `restored`.
  - Creation is retried with growing waits, `429` after `retry_after_s`.
  - Add the providers `accountServiceProvider`, `accountStatusProvider`, `profileProvider` and
    `firstOpenOutcomeProvider` in `account_providers.dart`.

  Make T031 pass.
- [X] T040 [US1] Wire startup:
  - add `BootStep.account` to `apps/mobile/lib/bootstrap/boot_progress.dart`;
  - in `apps/mobile/lib/bootstrap/startup.dart`, start `firstOpen()` once the database step is done,
    without adding it to `appStartup`'s awaited steps;
  - in `apps/mobile/lib/features/boot/boot_screen.dart`, make `_handOver` wait for the outcome up to
    `firstOpenWait` (a named `Duration(seconds: 3)` constant in `account_service.dart`), mark the
    step done, call `AccountService.handOver()`, then go as before;
  - add `retryAppStartup` invalidation for the new providers.

  Make T032 pass.
- [X] T041 [US1] Create `apps/mobile/test/backend/seed_backend.py`, run by `manage.py shell` on the
  dev stack. It:
  - creates staff `ci`;
  - imports `content/examples/sample`;
  - builds it and publishes it as version 1 through `apps.content.services`;
  - writes the rules index (`content_index --rebuild`'s service);
  - prints the published version, failing if it isn't 1.

  Then add the `sync-e2e` job to `.github/workflows/mobile.yml` exactly as contracts/ci-checks.md
  "The `sync-e2e` job", with the path filter added to the `changes` job and logs on failure. Make
  T033 pass locally.

**Checkpoint**: US1 works alone. The phone has an account and keeps its session.

---

## Phase 4: User Story 2 - Offline progress reaches the server once, in order (Priority: P1)

**Goal**: Pending operations go out in order, in batches within the limits; each answer is applied
in one transaction that rebases on the server's wallet; refusals of a whole request are handled;
nothing syncs on the trip screen; one neutral toast follows a visible rollback.

**Independent Test**: Three trips and a booster bought offline, then online: the server holds each
operation once and the balances agree, also when the network is cut mid-send (spec US2;
quickstart Part A e2e, Part B 4, 9, 10).

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T042 [P] [US2] Create `apps/mobile/test/core/sync/domain/op_wire_test.dart` (contracts/sync.md
  "The wire"):
  - each of the seven op types maps to `{client_txn_id, op_type, occurred_at, payload}`;
  - `content_version` is added from the row's column for `trip_start`, `spend_jenehat` and
    `spend_bonat` only;
  - `occurred_at` is ISO-8601 UTC with milliseconds and `Z`;
  - no local column leaks (deltas, `fuel_max`, `fuel_regen_minutes`, `max_earnings_jenehat`,
    reason).
- [X] T043 [P] [US2] Create `apps/mobile/test/core/sync/domain/batching_test.dart`:
  - at most 100 operations;
  - the encoded body stays ≤ 200 KiB (with 8 KB trip results, fewer than 100 fit);
  - halving after a size refusal; a single oversized operation is reported for setting aside;
  - `base_state_version` is the base's, or 0.
- [X] T044 [P] [US2] Create `apps/mobile/test/core/economy/apply_answer_test.dart` (R11, on a real
  database):
  - all accepted: the rows are `accepted`, and the base's JENEHAT, BONAT and `FuelState` equal the
    answer's wallet (`fuel`, `fuel_updated_at`, `fuel_unlimited_until`), with `after_seq` the
    batch's highest `seq`, `state_version` the answer's and `player_id` the given one;
  - pending operations after the batch are folded on top;
  - one rejected: its effects and its dependents' are gone, through the fold;
  - `state_stale`: results marked, no rebase;
  - divergence: an accepted operation the fold leaves out is reported in `leftOutAccepted`;
  - a kill at each M05 kill point leaves the answer fully applied or not at all;
  - applying the same answer a second time, with its rows already answered, changes nothing: the
    base, the rows and the tables stay as they were (constitution VI on the phone's side);
  - the materialized tables equal the fold afterwards (`checkProjection`).
- [X] T045 [P] [US2] Create `apps/mobile/test/core/sync/sync_engine_test.dart` against `FakeApi`, a
  fake `AuthorizedApi` session, a fake route signal and fake time:
  - **Gates** (contracts/sync.md "Gates"): no pass while the account isn't active, while deleted,
    on `/trip/:tripId`, in maintenance, in the background, or during a backoff (except `online` and
    `manual`); a pass in flight stops before its next request when the trip route opens.
  - **Triggers:** each `SyncTrigger` starts a pass; `opsRecorded` is debounced 2 s; a trigger during
    a pass gives exactly one more pass; leaving the trip route triggers one.
  - **Spacing and backoff:** ≥ 1 s between an answer and the next batch; backoff 2, 4, 8 … ≤ 300 s
    with ±20%; `Retry-After` respected; reset on success. A failed account creation in step 1
    (`5xx`, unreachable) sets the same backoff, and a creation `429` waits at least
    `retry_after_s` (FR-004).
  - **Backlog (SC-005):** 5,000 pending operations in real play's mix against a `FakeApi` handler
    that models B03's limits (60 syncs per player in any 60 s, a 256 KB body) and answers in
    300 ms:
    - the mix is each trip a `trip_start` and a `trip_result` of about 0.6 KB, the size of the
      parity fixtures' results, plus a spend every fifth trip;
    - no `429` or `413`, at most 50 batches, all answered within 120 s of fake time;
    - the same backlog with every result at the 8 KB maximum: still no `429` or `413`.
  - **Refusals:** every row of research R13's table (`batch_too_large`, `413`, `validation_error`
    naming `ops.N.…` sets N aside, `validation_error` naming none holds until the next launch,
    `415`, `406`, `426`, `429`, `503 maintenance`, `503 dependency_unavailable`, `5xx`, unreachable,
    a malformed `200`).
  - **A lost answer:** the same ids are resent and the stored results applied once.
  - **Toast:** shown once after a pass with a visible rejection; not for `trip_revive` or
    `traffic_jam` ad rewards alone; not for `account_changed`; never on the trip route.
- [X] T046 [P] [US2] Create `apps/mobile/test/helpers/model_server.dart`: `ModelServer`, a Dart model
  of B03's batch semantics (research R23).
  - It is idempotent by id, including within a batch, and processes in order.
  - It draws rejections from a seed, and rejects dependents as `dependency_rejected`.
  - Its wallet and state come from M05's own rules.
  - It keeps a `state_version` that changes only when something changed, and answers `state_stale`
    when a second client wrote.
  - It answers through `FakeApi`.

  Then create `apps/mobile/test/core/sync/sync_property_test.dart`: 1,000 seeded sequences of
  recorded operations, lost answers, retries, kills before an answer is applied, and second-client
  writes. After the queue drains, the device's JENEHAT, BONAT, fuel, boosters, ownership and trip
  progress equal the model's, and the model applied no id twice (SC-003).
- [X] T047 [P] [US2] Create `apps/mobile/test/backend/offline_sync_test.dart` (tag `backend`,
  scenario 1, SC-004):
  - record 50 operations offline (trips and purchases of the sample pack, version 1);
  - sync with the connection cut at seeded random points, through a dropping wrapper around the
    real `ApiClient`;
  - check that every id is accepted exactly once and the phone's balances equal `GET /v1/state`'s
    wallet.

### Implementation for User Story 2

- [X] T048 [US2] Create `apps/mobile/lib/core/sync/domain/op_wire.dart` and
  `apps/mobile/lib/core/sync/domain/batching.dart` (pure; constants `maxBatchOps = 100` and
  `maxBatchBytes = 200 * 1024`). Make T042 and T043 pass.
- [X] T049 [US2] Add a pure `rebase(base, answeredOps, wallet)` to
  `apps/mobile/lib/core/economy/domain/fold.dart`, or a new `rebase.dart` next to it. Implement
  `applyAnswer` in `apps/mobile/lib/core/economy/drift_economy_store.dart`, as one transaction:
  mark the results, rebase unless stale, write the base (`after_seq`, `state_version`,
  `player_id`), refold the pending ones, and write the tables. Expose it through `EconomyService`'s
  `EconomySync.applyAnswer` on the serial queue, returning `AnswerApplied`. Make T044 pass.
- [X] T050 [US2] Create `apps/mobile/lib/core/sync/sync_engine.dart`, implementing contracts/sync.md
  "A pass", "Gates", backoff, spacing, debounce, the refusal table (R13), the `SyncEvent` stream and
  `SyncSnapshot`. It uses `AuthorizedApi`, `EconomySync`, a route signal and `ServerStatus` inputs
  (a small `SyncStatusSink` interface US4 fills in). Steps 2, 2b and 4 (account change, the
  first-open restore, the state fetch) call stubs that US3 and US5 complete. Make T045 pass (its US3 and US5 rows stay pending).
- [X] T051 [US2] Create `apps/mobile/lib/core/sync/sync_lifecycle.dart`:
  - a route signal from the router (`/trip/:tripId` visible), like M04's `HomeArrival`;
  - `AppLifecycleListener` resume and background;
  - `ConnectivitySource.online`;
  - `EconomySync.pendingCounts` changes;
  - account `statuses` turning `active`.

  Each becomes a `SyncTrigger` or a gate. Add `syncEngineProvider` and `syncLifecycleProvider` in
  `apps/mobile/lib/core/sync/sync_providers.dart`, and start the lifecycle in
  `apps/mobile/lib/bootstrap/app.dart`'s `_afterStartup`, disposing it in `dispose`.
- [X] T052 [US2] Add the string `syncBalanceCorrected` («رصيدك اتظبط على آخر حساب», description
  "proposed in specs/011 research R14; owner approves") to `apps/mobile/lib/l10n/app_ar.arb`. Show
  it with `showAppToast` from the engine's pass end (R14), never on the trip route.
- [X] T053 [US2] Run T046's property test and T047 against the stack, fix what they find, and record
  the property test's seed range in its file header.

**Checkpoint**: US1 + US2 make the MVP. Offline trips sync without duplicates (the step's "done
when").

---

## Phase 5: User Story 3 - The phone stays in step with the server (Priority: P2)

**Goal**: The bootstrap anchors trusted time, caches its blocks and forces a pack check. The full
state is fetched and taken when stale, ahead, diverged or restored. The first open restores a
returning player. The comeback gift has its local operation and guard.

**Independent Test**: A change made from a second session or by staff reaches the phone at the
next launch, with its own pending operations applied once; a re-install lands on Home with its
progress (spec US3; quickstart Part B 5–8).

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T054 [P] [US3] Create `apps/mobile/test/core/sync/domain/state_snapshot_test.dart`, checking
  every row of contracts/sync.md "Taking the full state":
  - `""` variants become null, and items keep theirs;
  - `acquiredAtMs` is the snapshot's `server_time`, and `acquiredBy` is null;
  - `firstCompletedAtMs` is null;
  - `open_trip` is kept only when `hasTripRecord(startTxn)` is true, with `maxEarningsJenehat` from
    the sample pack's trip, and is left out otherwise;
  - ids missing from the pack are kept;
  - `story`, `grants` and `stats` are ignored.
- [X] T055 [P] [US3] Create `apps/mobile/test/core/economy/replace_from_server_test.dart`:
  - `replaceFromServer` sets `after_seq` to `highestAnsweredSeq`;
  - pending operations stay folded on top;
  - a base with a null player adopts the operations and sets the player;
  - the fold equals the tables afterwards.
- [X] T056 [P] [US3] Create `apps/mobile/test/core/sync/bootstrap_service_test.dart` (R15):
  - no bootstrap within 60 s of the last success, except when forced;
  - `anchorOnServer(server_time + rtt / 2, …)` is called;
  - the cache row is written (`received_at_ms`, `state_version`, `content_version`, the `client`,
    `entitlements` and `daily` JSON, `comeback_claimable`);
  - the profile goes to `account`;
  - a newer `content.version` calls `ContentUpdater.check(force: true)` (fake updater);
  - a `state_version` above the base's with nothing pending marks the state for fetching;
  - the bootstrap's wallet is never applied;
  - cached blocks read offline.
- [X] T057 [P] [US3] Extend `apps/mobile/test/core/sync/sync_engine_test.dart` with the state rows:
  - after a `state_stale` answer, the engine fetches `GET /v1/state` and calls
    `replaceFromServer`;
  - when the server is ahead with nothing pending, it fetches;
  - after a divergence it fetches;
  - after `requestRestore()`, the next pass fetches the state before it sends anything (step 2b),
    and never while the trip route shows;
  - each emits `StateTaken` with its reason (`firstOpen` for the restore).
- [X] T058 [P] [US3] Extend `apps/mobile/test/core/account/account_service_test.dart` and
  `apps/mobile/test/features/boot/first_open_wait_test.dart` with the restore path:
  - `created: false` → `GET /v1/state` → `replaceFromServer` → `restored`, with
    `account.restored_at_ms` set;
  - within 3 s, boot goes on with the state in place (the view shows the player's progress);
  - after 3 s, the outcome is `timedOut`;
  - a `created: false` answer, or a state answer, that arrives after `handOver()` isn't applied by
    `firstOpen()`, which calls `SyncEngine.requestRestore()` instead;
  - with a trip on screen when it arrives, nothing changes until the trip route closes; then the
    engine takes the state, `restored_at_ms` is set and `progressRestoredProvider` emits once.
- [X] T059 [P] [US3] Create `apps/mobile/test/core/sync/comeback_gift_test.dart` and extend
  `apps/mobile/test/core/economy/domain/direction_test.dart` (R16):
  - `comeback_gift` fills the tank (a full tank stays full and the op still applies) and adds one
    `change_bag`, with no BONAT;
  - the claim is allowed only when the cached flag is true, none is pending, and the flag arrived
    after `comeback_answered_at_ms` and `comeback_claimed_at_ms`;
  - a second claim while one is pending is refused `not_eligible`;
  - a "claimable" bootstrap received while the claim waits doesn't re-arm it;
  - an offline claim works from the cache;
  - the claim's answer sets `comeback_answered_at_ms`.
- [X] T060 [P] [US3] Create `apps/mobile/test/backend/stale_state_test.dart` (tag `backend`,
  scenario 2):
  - two services sign in with the same install id (two sessions of one player);
  - the second syncs a trip;
  - the first's next batch gets `state_stale`, takes the state, and converges, with its own
    operations applied once.

### Implementation for User Story 3

- [X] T061 [US3] Create `apps/mobile/lib/core/sync/domain/state_snapshot.dart` (pure), mapping
  `StateSnapshot` to `EconomyState` with a `hasTripRecord` callback and the content source for
  `maxEarningsJenehat`. Add `has(TxnId startTxn)` to M02's `TripRecords`
  (`apps/mobile/lib/features/trip/data/trip_records.dart` and `drift_trip_records.dart`), a read
  only. Make T054 pass.
- [X] T062 [US3] Implement `replaceFromServer` in `drift_economy_store.dart` and `EconomyService`, as
  one transaction: base = snapshot, `after_seq = highestAnsweredSeq`, `state_version`, and
  `player_id` (adopted when null). Then fold the pending operations. Make T055 pass.
- [X] T063 [US3] Create `apps/mobile/lib/core/sync/bootstrap_service.dart` (R15): the 60 s spacing,
  the forced mode, the RTT midpoint anchor, the cache write through `DriftAccountStore`, the
  profile, `ContentUpdater.check(force: true)`, the client block to a `ClientBlockSink` (filled by
  US4), the ahead mark, and the providers `bootstrapServiceProvider`, `entitlementsProvider`,
  `dailyBlockProvider` and `serverInfoProvider`. Call it from the sync lifecycle before each pass
  when due. Make T056 pass.
- [X] T064 [US3] Complete the engine's step 4, the stale and divergence fetches, and
  `requestRestore()` with its step 2b in `apps/mobile/lib/core/sync/sync_engine.dart`, re-anchoring
  time on the state's `server_time`. Make T057 pass.
- [X] T065 [US3] Add the restore path to `AccountService.firstOpen()`, and
  `progressRestoredProvider`, in `apps/mobile/lib/core/account/account_service.dart` (research R6).
  `firstOpen()` calls `replaceFromServer` only before `handOver()`. After it, the state is left to
  `SyncEngine.requestRestore()`; on `StateTaken(firstOpen)`, the service sets `restored_at_ms` and
  emits `progressRestoredProvider`. Make T058 pass.
- [X] T066 [US3] Add the local `comeback_gift` operation:
  - `OpType.comebackGift('comeback_gift')` in `apps/mobile/lib/core/economy/domain/op.dart`;
  - its rule in a new `apps/mobile/lib/core/economy/domain/gift_rules.dart` (fuel to the maximum,
    or unchanged when full; `change_bag` + 1; no reason, no ref; always valid in the fold),
    dispatched from `rules.dart`;
  - `grantComebackGift` on `EconomySync`.

  Then create `apps/mobile/lib/core/sync/comeback_gift.dart` (`ComebackGift`: `claimable`,
  `claimables`, `claim(TxnId)`), with `comebackGiftProvider`. It writes the claim and answer times
  through `DriftAccountStore`. Make T059 pass.
- [X] T067 [US3] Run T060 against the stack, and fix what it finds.

**Checkpoint**: US1–US3 work. The phone follows the server, and a re-install comes back.

---

## Phase 6: User Story 4 - Offline, update required and maintenance are shown honestly (Priority: P2)

**Goal**: The offline banner and the maintenance card on Home, the forced and optional update cards
over everything but the trip, with 008.5's components, the strings and the checks.

**Independent Test**: With a fake server, each state appears as its artboard block, in RTL with
both digit styles. The offline banner hides once the bootstrap and a sync succeed (spec US4;
quickstart Part B 1, 11, 12).

### Tests for User Story 4 ⚠️ (write first, must fail)

- [X] T068 [P] [US4] Create `apps/mobile/test/core/sync/server_status_test.dart` (data-model.md
  "State transitions"):
  - reach goes `offline` on the link down or an `ApiUnreachable`, and `online` only after a
    successful bootstrap followed by a pass with no network failure;
  - maintenance turns on with `503 maintenance` (`details.until` parsed to ms, absent or malformed
    ignored) and clears on the next successful pass;
  - update is `forced` from a live `force_update` or a `426` (memory only: a new instance starts
    `none`);
  - update is `optional(v)` when `latest_version` is above the app's and the update isn't forced,
    until `v` is dismissed (`update.dismissedVersion` in `SettingsStore`);
  - `isOnlineProvider` follows reach.
- [X] T069 [P] [US4] Create `apps/mobile/test/features/home/home_status_area_test.dart`:
  - nothing (zero height) when online with no maintenance;
  - `OfflineBanner` with `homeOffline` when offline;
  - `StatusCard.maintenance` with `maintenanceMessageAt` and the local time in the player's digit
    style when `until` is known, and `maintenanceMessage` otherwise;
  - offline wins over maintenance;
  - `liveRegion` status semantics.
- [X] T070 [P] [US4] Create `apps/mobile/test/bootstrap/status_overlay_test.dart`:
  - forced: a dialog over Home with `updateTitle`, `updateMessage` and `updateCta`; back does
    nothing; a tap outside does nothing; the CTA calls `StoreLauncher.openListing`; no CTA when
    `hasListing` is false;
  - optional: the same plus `updateLater`, which closes it and stores the version;
  - not shown while `/trip/:tripId` is visible, and shown on leaving it;
  - the CTA is ≥ 44 pt tall;
  - reduced motion fades without movement.
- [X] T071 [P] [US4] Create `apps/mobile/test/core/platform/store_launcher_test.dart`:
  - Android builds `https://play.google.com/store/apps/details?id=<applicationId>` from `AppInfo`,
    for each flavor's id;
  - iOS has `hasListing == false` while `iosAppStoreId` is empty;
  - it uses `LaunchMode.externalApplication`, against a fake `url_launcher` platform.
- [X] T072 [P] [US4] Create `apps/mobile/test/goldens/server_states_goldens_test.dart`, in RTL at
  390×844 with both digit styles (contracts/server-states.md "Checks"):
  - Home with the offline banner;
  - Home with the maintenance card, with a time and without;
  - the forced update card over Home;
  - the optional update card;
  - the toast over Home.

  Add a layout check that each placed component matches its `States` box within ±2 pt
  (`docs/design/boxes/States.json`: the banner, the update card and its button, the maintenance
  card), using `test/design/boxes.dart`.

### Implementation for User Story 4

- [X] T073 [US4] Create `apps/mobile/lib/core/sync/server_status.dart`: `ServerStatus` (a Riverpod
  notifier holding `ServerStatusState`: `Reach`, `Maintenance?`, `UpdateState`), `serverStatusProvider`
  and `isOnlineProvider`. It implements US2's `SyncStatusSink` and US3's `ClientBlockSink`, and
  observes `AuthorizedApi` results and `ConnectivitySource`. Make T068 pass.
- [X] T074 [US4] Create `apps/mobile/lib/core/platform/store_launcher.dart`: `StoreLauncher`,
  `UrlStoreLauncher` over `url_launcher` with `LaunchMode.externalApplication`, the constant
  `iosAppStoreId = ''` with a comment naming the owner action, and `storeLauncherProvider`. Make T071
  pass.
- [X] T075 [US4] Add the strings to `apps/mobile/lib/l10n/app_ar.arb`, exactly as
  contracts/server-states.md "Strings": `homeOffline`, `updateTitle`, `updateMessage`, `updateCta`,
  `updateLater`, `maintenanceTitle`, `maintenanceMessageAt` (placeholder `time`) and
  `maintenanceMessage`. Each gets a description citing HANDOFF `States` 1, 7 or 8. Run
  `fvm flutter pub get` to regenerate l10n.
- [X] T076 [US4] Create `apps/mobile/lib/features/home/home_status_area.dart`: `HomeStatusArea`, a
  column with no reserved height. It shows `OfflineBanner` or `StatusCard.maintenance` (picture and
  layout as `test/design/samples/states.dart` draws block 31), with the time formatted by the digit
  style. In `apps/mobile/lib/core/routing/router.dart`'s `_page`, wrap Home's screen in every flavor
  with it. Make T069 pass.
- [X] T077 [US4] Create `apps/mobile/lib/bootstrap/status_overlay_host.dart`: `StatusOverlayHost`,
  placed in `WassalApp.builder` (`apps/mobile/lib/bootstrap/app.dart`) above the router's child. It
  shows the forced or optional `AppDialog` with `StatusCard.update` (as the sample's block 26), with
  `PopScope(canPop: false)` and absorbed touches when forced, and «بعدين» when optional. It waits
  while the trip route is visible. Make T070 pass.
- [X] T078 [US4] Generate the goldens on Linux (`fvm flutter test --update-goldens
  test/goldens/server_states_goldens_test.dart`), review them beside `docs/design/png/States.png`,
  commit them, and make T072 pass.

**Checkpoint**: US1–US4 work. Every server state the player can see is honest and designed.

---

## Phase 7: User Story 5 - Account changes never mix two players' progress (Priority: P3)

**Goal**: A changed player gets its own state with the old operations dropped; `account_deleted`
stops everything; the link request flushes first, and its outcomes are ready for M14.

**Independent Test**: With a fake server, a sign-in that answers another player never sends the
old operations and shows the new player's state; a link with pending operations sends them first
(spec US5).

### Tests for User Story 5 ⚠️ (write first, must fail)

- [X] T079 [P] [US5] Create `apps/mobile/test/core/economy/adopt_account_test.dart`:
  - `adoptAccount` marks every pending operation `rejected` with `account_changed` and returns
    their count;
  - the base becomes the snapshot for the new player, with `after_seq` the last `seq`;
  - the fold equals the tables;
  - one transaction (a kill leaves the old state whole).
- [X] T080 [P] [US5] Extend `apps/mobile/test/core/account/account_service_test.dart` and
  `apps/mobile/test/core/sync/sync_engine_test.dart` with the change rows of contracts/account.md
  "Account changes":
  - operations recorded before any account are sent for the first player;
  - a token answer for another player stores the session and the player, blocks the sync, and the
    next pass fetches the new player's state and calls `adoptAccount`, emitting `OpsDropped`;
  - a kill between the two (a new engine on the same stores) completes the change at the next
    pass;
  - no request for the old player's operations carries the new bearer;
  - `403 account_deleted` sets `deleted`, stops the sync, and stays stopped after a restart.
- [X] T081 [P] [US5] Create `apps/mobile/test/core/account/link_test.dart` (contracts/account.md "Link
  outcomes"):
  - pending operations are flushed first (`flush` up to 15 s), and `flushed` is reported true or
    false;
  - every answer maps to its `LinkOutcome`;
  - the retry sends `resolve` and `existing_player_id`;
  - `switch_to_existing`'s `TokenPair` triggers an account change;
  - `422 provider_token_invalid` never renews the session.

### Implementation for User Story 5

- [X] T082 [US5] Implement `adoptAccount` in `drift_economy_store.dart` and `EconomyService`, as one
  transaction: pending → `rejected('account_changed')`, base = snapshot for the new player, fold.
  Make T079 pass.
- [X] T083 [US5] Complete the account change in `apps/mobile/lib/core/account/account_service.dart`
  and the engine's step 2 in `apps/mobile/lib/core/sync/sync_engine.dart`: detect the other player
  in `AuthorizedApi`'s token answers, block while `account.player_id ≠ base.player_id` (both set),
  then fetch and adopt. Keep the deleted status permanent. Make T080 pass.
- [X] T084 [US5] Add `SyncEngine.flush({timeout = 15 s})`, and `AccountService.link(...)` with the
  `LinkOutcome` mapping and `existing_player_id`, in `account_service.dart`. Make T081 pass.

**Checkpoint**: US1–US5 work. M14 can build linking and deletion screens on them.

---

## Phase 8: User Story 6 - Testers can see where the account and the queue stand (Priority: P3)

**Goal**: A status card on the playtest Home with the account and sync status and «sync now».

**Independent Test**: On a staging build, the card's pending count rises with an offline trip and
falls to 0 after «sync now», with the state version moving (spec US6; quickstart Part B 2).

### Tests for User Story 6 ⚠️ (write first, must fail)

- [X] T085 [P] [US6] Create `apps/mobile/test/features/dev/sync_status_card_test.dart`:
  - it shows the player id's first 8 characters, the providers, the pending count, the base's
    state version, the last pass's times and outcome, the last error code and the set-aside count;
  - «sync now» calls `SyncEngine.syncNow`;
  - no token or install id is in its text or semantics;
  - it isn't routed in the prod flavor (router test).

### Implementation for User Story 6

- [X] T086 [US6] Create `apps/mobile/lib/features/dev/sync_status_card.dart`, with English
  identifier labels as the trip's debug panel uses. Add it to the playtest Home's `extra` column in
  `apps/mobile/lib/core/routing/router.dart`, beside `TripList` and `GalleryEntry`. Implement
  `SyncEngine.syncNow` (a forced bootstrap, then a pass). Make T085 pass.

**Checkpoint**: All six stories work.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documents, the full checks, the reviews and the owner's list.

- [X] T087 [P] Update `docs/architecture-mobile.md`:
  - §11: the `account` and `server_info` tables, `projection_base.player_id`, the nullable
    `acquired_by`, and the secure storage backup rule;
  - §12: the rebase, the trip-route gate, the toast, the local reasons `validation_error`,
    `payload_too_large` and `account_changed`, and `comeback_gift`;
  - §16: the install id per platform, `wassal.session`, the first open's 3 s wait, and the link
    request here with its screens in M14.
- [X] T088 [P] Update `docs/architecture-backend.md` §22.6 with a line saying the device side is
  resolved in M06 (`specs/011-m06-identity-sync/research.md` R1). Then update `docs/delivery-plan.md`:
  - step 6's "Resolved in M06" line;
  - the Progress list: `009-b02-accounts-auth` merged in #15 and `010-b03-ledger-sync` merged in
    #16, 2026-10-26, and M06's line when it merges;
  - the Design sources row for M06 (`States` 1, 7, 8 placed, not redrawn).
- [X] T089 [P] Update `CLAUDE.md`:
  - the mobile commands table: the `sync-e2e` command (stack up, seed, `--tags backend`) and
    `--exclude-tags backend`;
  - the writers rule: `lib/core/account/drift_account_store.dart` is the only writer of `account`
    and `server_info`;
  - the guards list: sync-only access, no secrets in logs or preferences.
- [X] T090 Add M06's section to `docs/owner-actions.md`, each item with its task id.
  - **Before merge:** approve the toast line «رصيدك اتظبط على آخر حساب» and «بعدين» (T052, T075);
    quickstart Part B 1–14 on the Redmi Note 7 with Google backup on (T091).
  - **After merge:**
    - steps 2, 7 and 14 on a staging build;
    - fill `iosAppStoreId` when the App Store listing exists (T074);
    - one Codemagic `ios-dev-unsigned` build (T093), then quickstart step 15, the iOS re-install,
      on the sideloaded IPA (SC-006);
    - on the Galaxy A06, `tool/perf/cold_start.sh com.wassalogra.app.dev 10` with a median
      ≤ 3,000 ms, and one first open of a returning player, at most 3 s longer (SC-001).

  Update "Open now".
- [X] T091 Run quickstart.md Part A in full (format, analyze with `--fatal-infos`, `flutter test
  --coverage --exclude-tags backend`, coverage ≥ 80%, and the e2e against the dev stack). Fix
  anything it finds. Measure `applyAnswer` for a 100-operation batch in a test with a 50,000-row log,
  under 100 ms on CI's machine, and record the number in research R11.
- [X] T092 Security review of the diff (auth, sync, the ledger, secrets), with the `security-reviewer`
  agent. Check:
  - tokens only in secure storage;
  - the install id sent only to account creation;
  - no logging of either;
  - the backup rules;
  - no BONAT path but the server's wallet;
  - `EconomySync`'s reach.

  Fix CRITICAL and HIGH findings, then run the `flutter-reviewer` agent over the Dart diff.
- [ ] T093 Make the iOS dev IPA reach a server, then build it.
  - In `codemagic.yaml`, add `--dart-define=WASSAL_DEV_API_BASE=$WASSAL_DEV_API_BASE` to the
    `ios-dev-unsigned` build script. Set the workflow variable to staging's
    `https://staging-api.141-147-129-92.sslip.io` (`stagingApiBase` in `api_environment.dart`),
    since a dev build's `localhost` is the phone itself. An empty value keeps `localhost`.
  - Note it in `docs/runbooks/ios-test-build.md`.
  - Trigger the workflow on the branch (no Podfile), and confirm `flutter_secure_storage_darwin`
    and `url_launcher_ios` resolve as Swift Packages and the IPA builds. Quickstart step 15 runs on
    it.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. Blocks every story.
- **US1 (Phase 3)**: after Foundational. The sync needs its session.
- **US2 (Phase 4)**: after Foundational. Its tests use a fake `AuthorizedApi`, but the app wiring
  (T051) and the e2e (T047, T053) need US1.
- **US3 (Phase 5)**: after US2. The state fetch extends the engine, and the restore extends US1's
  first open.
- **US4 (Phase 6)**: after Foundational. Its tests run on fakes. The status inputs (T073) plug into
  US2's and US3's sinks, so they land after T050 and T063.
- **US5 (Phase 7)**: after US1 and US2 (the account and the engine).
- **US6 (Phase 8)**: after US2 (the engine's snapshot).
- **Polish (Phase 9)**: after the stories that ship.

### Within Each User Story

- Tests first, and failing, before implementation.
- Domain (pure) before the stores, before the services, before the wiring and the screens.
- Shared files (Organization) in task order.

### Parallel Opportunities

- Setup: T002 and T003.
- Foundational: the helpers T004 and T005; the guards T006–T010; the tests T011–T014, T022, T023
  and T026, all before their implementations.
- Within each story, every test task marked [P].
- US4's implementation (T073–T077) can proceed beside US3's once T050 exists, since it touches
  different files except `app.dart` and `router.dart`.
- Polish's docs: T087, T088 and T089.

---

## Parallel Example: Foundational tests

```text
T006 test/repo/economy_sync_access_test.dart
T007 test/repo/economy_writes_test.dart
T008 test/repo/no_secret_logging_test.dart
T009 test/repo/backup_rules_test.dart
T010 test/repo/domain_imports_test.dart
T011 test/core/storage/schema_v3_test.dart
T012 test/core/economy/domain/economy_state_test.dart
T013 test/core/economy/economy_sync_test.dart
T022 test/core/network/api_client_test.dart
T023 test/core/sync/domain/wire_test.dart
T026 test/core/account/drift_account_store_test.dart
```

## Parallel Example: User Story 2

```text
T042 test/core/sync/domain/op_wire_test.dart
T043 test/core/sync/domain/batching_test.dart
T044 test/core/economy/apply_answer_test.dart
T045 test/core/sync/sync_engine_test.dart
T046 test/helpers/model_server.dart + test/core/sync/sync_property_test.dart
T047 test/backend/offline_sync_test.dart
```

---

## Implementation Strategy

### MVP First (User Stories 1 and 2)

1. Phase 1 and Phase 2.
2. Phase 3 (US1): the account and its session.
3. Phase 4 (US2): the sync. With US1, this is the step's "done when": the first online launch
   creates an account in the background, and offline trips sync without duplicates.
4. **Stop and validate**: quickstart Part A's e2e, and Part B steps 1–4.

### Incremental Delivery

1. US1 + US2: the MVP.
2. US3: the stale path (the step's last "done when"), the restore, the bootstrap, the comeback gift.
3. US4: the three states the player sees.
4. US5: account changes and the link request, ready for M14.
5. US6: the testers' card, which helps every Part B step. It can come right after US2 if useful.
6. Polish, the reviews, then one PR.

### Notes

- **[P]** tasks are in different files with no dependencies on incomplete tasks.
- Never edit a generated file: `*.g.dart`, `lib/l10n/generated/`, `drift_schemas/` (only
  `make-migrations` writes it) and the generated `test/drift/` files.
- Never stash, reset or discard to get past a failing hook. Ask the owner.
- Commit after each task or logical group, with Conventional Commits.
