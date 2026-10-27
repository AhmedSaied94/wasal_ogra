# Contract: Guards, Tests and CI

What this feature adds to `flutter test`'s repo guards, the tests it owns, and the new CI job.
Research: R2, R20, R21, R23.

## Repo guards (`test/repo/`)

| Guard | File | Fails when |
| --- | --- | --- |
| Sync-only economy calls | `economy_sync_access_test.dart` (new) | `economySyncProvider`, `EconomySync` or its methods appear outside `lib/core/sync/`, `lib/core/account/` and `lib/core/economy/` |
| Account tables' one writer | `economy_writes_test.dart` (extended) | anything but `lib/core/account/drift_account_store.dart` writes `account` or `server_info`; the economy tables' rule is unchanged |
| Secrets stay out of logs | `no_secret_logging_test.dart` (new) | a `print`, `debugPrint`, `log(`, `FlutterError.report…` or `LogInterceptor` in `lib/` mentions `access`, `refresh`, `installId`, `install_id` or `Session` values; or `LogInterceptor` appears at all |
| Tokens never in the preference store | `no_secret_logging_test.dart` | a `SharedPreferences` or `SettingsStore` key in `lib/` contains `token`, `session`, `access`, `refresh` or `install` (except `wassal_install.xml`'s own Android store) |
| Backup rules | `backup_rules_test.dart` (extended) | `db/` or one of the secure-storage plugin's four files isn't excluded from both cloud backup and device transfer. The four (research R2) are `FlutterSecureStorage.xml`, `FlutterSecureKeyStorage.xml`, `FlutterSecureStorageConfiguration.xml` and `FlutterSecureStorageConfiguration:FlutterSecureStorage.xml`. It also fails when either file has an `<include>` (one would limit the backup to the listed files), or when `wassal_install.xml` is excluded. |
| Domain imports | `domain_imports_test.dart` (extended) | `lib/core/account/domain/` or `lib/core/sync/domain/` imports anything but `dart:core`, `dart:convert`, `content_models` and the economy and content domains |
| Plain HTTP | `cleartext_config_test.dart` (unchanged) | still covers every call, since `ApiClient` uses M04's factory |
| No REAL column | `integer_money_test.dart` (unchanged) | covers v3's new columns |

## Tests

| Area | Files | Covers |
| --- | --- | --- |
| Wire readers | `test/core/sync/domain/wire_test.dart` | every field in api-client.md; non-integers refused; unknown fields ignored |
| Op mapping | `test/core/sync/domain/op_wire_test.dart` | every op type; `content_version` for the three; `occurred_at` format |
| State mapping | `test/core/sync/domain/state_snapshot_test.dart` | sync.md's table; the open trip with and without a record; `""` variants |
| Rebase | `test/core/economy/apply_answer_test.dart` | R11; stale; divergence; kill before commit (M05's kill points) |
| Account change | `test/core/economy/adopt_account_test.dart` | pending → `account_changed`; base; fold |
| Comeback gift | `test/core/sync/comeback_gift_test.dart` | R16's guard; offline claim; full tank; direction test entry |
| Token rules | `test/core/account/authorized_api_test.dart` | every row of api-client.md's rules table, the race, the 60 s window |
| First open | `test/core/account/first_open_test.dart` | new, restored, offline, timed out, late restore, iOS stale session cleared |
| Install id | `test/core/account/install_id_store_test.dart` | read order, writes to the missing store, channel failures |
| Engine | `test/core/sync/sync_engine_test.dart` | gates, triggers, debounce, backoff, spacing, R13's table, toast rule |
| Server status | `test/core/sync/server_status_test.dart` | reach, maintenance, update transitions; precedence |
| Property | `test/core/sync/sync_property_test.dart` | SC-003: 1,000 seeded sequences against `ModelServer` |
| Screens | `test/features/home/home_status_area_test.dart`, `test/bootstrap/status_overlay_test.dart`, `test/goldens/server_states_goldens_test.dart` | server-states.md "Checks" |
| Migration | `test/drift/app/` (generated) | v2 → v3, rows kept, `account` and `server_info` inserted |
| Against the stack | `test/backend/*_test.dart`, tag `backend` | R23's three scenarios |

`dart_test.yaml` gains the `backend` tag. CI's normal `flutter test` excludes it
(`--exclude-tags backend`, alongside the existing tags).

## The `sync-e2e` job (`.github/workflows/mobile.yml`)

```text
on: the `changes` job reports a change under apps/mobile/lib/core/{account,sync,network,economy}/,
    apps/mobile/test/backend/, backend/apps/{accounts,economy,progress}/, contracts/openapi.yaml,
    or workflow_dispatch
steps:
  1. cd backend && cp .env.example .env
  2. docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait   (migrates first)
  3. uv run manage.py shell < ../apps/mobile/test/backend/seed_backend.py
     (creates the staff user `ci`, imports content/examples/sample, builds and publishes it as
     version 1, the version the dev app bundles, through apps.content.services, and writes the
     rules index; dev's solver stage is the stand-in)
  4. fvm flutter pub get; build content_models; build_runner (apps/mobile)
  5. WASSAL_E2E_API=http://localhost:8000 fvm flutter test --tags backend test/backend
  6. docker compose … logs on failure; down -v
```

Run it locally the same way: start the dev stack, then step 5 from `apps/mobile`. The e2e tests
create their own players through `POST /v1/auth/anonymous` with fresh install ids, so they don't
interfere with each other.
