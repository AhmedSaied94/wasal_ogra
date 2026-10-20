# Contract: CI Checks

Research R17. These checks extend M03's and B04's (`specs/001-m03-app-shell/contracts/ci-checks.md`,
`specs/003-b04-content-pipeline/contracts/ci-checks.md`). Every check below must pass before a
merge.

## `.github/workflows/mobile.yml`

**The `changes` filter** adds `fixtures/`:

```text
^(apps/mobile/|packages/|content/|fixtures/|\.fvmrc$|\.github/workflows/mobile\.yml$)
```

**The jobs.** To keep CI short, the workflow runs three jobs in parallel after `changes`, and one
that sums them up:

| Job | Runs |
| --- | --- |
| `app` | The app: `pub get`, `build_runner`, the format check, `analyze`, `test --coverage` with the goldens, and the 80% gate. |
| `packages` | `packages/content_models` (B04's steps), then `packages/trip_engine` (the steps below). |
| `build-android` | The dev debug APK, with the Gradle cache of `gradle/actions/setup-gradle` (written by `master` runs, read by pull requests) and Gradle's build cache. |
| `check` | Passes when every job above passed or was skipped, like `backend.yml`'s `backend` job. |

The ruleset on `master` requires `backend` and `gitleaks`, not a mobile job. `check` is the one to
require if mobile should block merges.

**The `trip_engine` steps** run in `packages`, after the `content_models` steps, so its generated
parts exist:

| Step | Command (in `packages/trip_engine`) | Fails when |
| --- | --- | --- |
| trip_engine dependencies | `dart pub get` | Resolution fails. |
| trip_engine format check | `dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` | Any file isn't formatted. |
| trip_engine analyze | `dart analyze --fatal-infos` | Any issue is found. |
| trip_engine tests and coverage gate | `dart test --coverage=coverage`, then `dart run coverage:format_coverage --lcov --report-on=lib --in=coverage --out=coverage/lcov.info`, then `dart run ../../apps/mobile/tool/check_coverage.dart --min 90 --lcov coverage/lcov.info` | Any test fails, or line coverage of `lib/` is below 90% (constitution XIII). |

The test run includes everything below. Together it should finish within the job's 15-minute
limit, with the engine's share well under a minute.

| Test | Asserts | Spec |
| --- | --- | --- |
| `test/fixtures/fixtures_test.dart` | Every `fixtures/parity/*.json` replays to its `expected_result`. | FR-062, SC-001 |
| `test/fixtures/fixture_coverage_test.dart` | The SC-002 list is covered. | SC-002 |
| `test/fixtures/fixture_expectations_test.dart` | Each fixture's rule holds. | FR-062 |
| `test/replay/pacing_invariance_test.dart` | Pacings of 1, 7 and all-at-once give identical results, events and fingerprint. | FR-010, FR-061 |
| `test/replay/rebuild_test.dart` | Rebuilding at 10 cuts per fixture gives identical states and final results. Malformed records are refused. | FR-070, SC-009 |
| `test/fuzz/fuzz_test.dart` | Random logs never throw, conserve money, and replay identically. | FR-061, SC-007 |
| `test/perf/replay_budget_test.dart` | The stress fixture replays in < 1 s, and its log is ≤ 64 KB. | SC-004, SC-005 |
| `test/guards/imports_test.dart` | `lib/` imports only the allowed libraries, and `pubspec.yaml` has no Flutter dependency. | FR-072, SC-006 |
| `test/guards/integer_money_test.dart` | No `double`, `num`, `toDouble` or `/` operator in `lib/`. | SC-007 |
| `test/guards/no_clock_test.dart` | No `DateTime`, `Stopwatch`, `Random`, `dart:io` or `dart:async` in `lib/`. | FR-001 |
| `test/guards/no_arabic_test.dart` | No Arabic characters in `lib/` outside comments. | FR-064 |
| `test/capabilities_test.dart` | `EngineCapabilities` equals `content/engine/capabilities.json`. | FR-064 |
| `test/params/params_tunables_test.dart` | `TripParams` resolves from the app's `tunables.json` for every line. | FR-067 |

The app's existing steps also cover the registry change: `tunables_defaults_test.dart` and
`config_source_test.dart` (contracts/tunables.md).

## `.github/workflows/backend.yml`

**The `changes` filter** adds `fixtures/`, so the content-kit job runs when fixtures change:

```text
^(backend/|contracts/|content/|fixtures/|tools/content_kit/|packages/content_models/|\.dockerignore$|\.github/workflows/backend[^/]*\.yml$)
```

**The content-kit job's** existing commands cover the new work:

- `codegen --check` covers the packaged `capabilities.json`;
- `pytest` covers V-T8 to V-T11 and `test_parity_fixture_definitions.py`, which validates every
  fixture's definition;
- `golden` checks the sample pack's new checksums.

**The backend job's** existing `pytest`, `makemigrations --check` and OpenAPI diff cover the new
field and its migration. The OpenAPI file doesn't change.

## Arrives later

- **B05:** a pytest job that replays `fixtures/parity/*.json` through `tools/solver`. CI then fails
  on any Dart/Python mismatch (constitution III).
