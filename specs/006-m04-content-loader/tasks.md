---

description: "Task list for M04 Content Pack Loader"
---

# Tasks: Content Pack Loader (M04)

**Input**: Design documents from `specs/006-m04-content-loader/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Constitution XIII requires tests. Every phase writes its tests
  first, and they must fail before its implementation tasks start.
- **Real files and a real HTTP server.** Store tests use real temp directories. The network
  client is tested against a `dart:io` `HttpServer` on `127.0.0.1`, not mocks.
- **Coverage.** At least 80% of lines in `apps/mobile`, `packages/content_models` and
  `tools/content_kit`. Generated parts stay excluded.

**Organization**:

- **Paths** are from the repository root.
  - Dart commands run with `fvm` in `apps/mobile/` or `packages/content_models/`.
  - `uv` commands run in `tools/content_kit/`.
- **Codegen.** After adding or changing a `@riverpod` provider, run
  `fvm dart run build_runner build -d` in `apps/mobile`. Before any app test, build
  `packages/content_models` (`fvm dart pub get && fvm dart run build_runner build -d`).
- **Exactness.** Every number in a task (caps, timeouts, the 15-minute interval, the 3 attempts,
  the 20 events) is from the contracts. Name each one as a constant in `lib/`, never a bare literal.
- **Shared files.** `content_controller.dart`, `pack_store.dart` and `content_updater.dart` grow
  story by story, so tasks that touch them are sequential across stories.
- **One PR.** This feature merges as one PR.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US4 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The app's version and dependencies, the asset directories, and CI (plan "Project
Structure").

- [x] T001 Update `apps/mobile/pubspec.yaml` (research R1, R2, contracts/bundling.md):
  - `version: 1.0.0+2` (spec Clarifications, FR-035);
  - dependencies `content_models: {path: ../../packages/content_models}`, `dio: ^5.11.1`,
    `crypto: ^3.0.7`, `path_provider: ^2.1.6`, `connectivity_plus: ^7.3.2` and
    `package_info_plus: ^10.2.2`;
  - dev dependency `integration_test: {sdk: flutter}`;
  - under `flutter: assets:`, add `- path: assets/content/dev/` with `flavors: [dev]`, and
    `- path: assets/content/release/` with `flavors: [staging, prod]`, next to the existing
    `tunables.dev.json` entry.

  Then run `fvm flutter pub get` and commit `pubspec.lock`.
- [x] T002 [P] Create `apps/mobile/assets/content/dev/README.md` and
  `apps/mobile/assets/content/release/README.md`. Each, in English, says:
  - which flavors bundle the directory;
  - which command fills it (`wassal-content bundle dev` or `bundle release`);
  - that its files are generated and must not be edited by hand, with a link to
    `specs/006-m04-content-loader/contracts/bundling.md`.

  The release README also says that until production's first promotion it is the only file there,
  and that staging and prod builds are refused until then.
- [x] T003 [P] In `.github/workflows/mobile.yml`, add a step named `content_models build` to the
  `app`, `build-android` and `update-goldens` jobs, before their `flutter pub get`. It has
  `working-directory: packages/content_models` and runs `dart pub get` then
  `dart run build_runner build -d` (contracts/ci-checks.md). The change filter is unchanged.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: What every story uses: the strict decoder, the sample pack as a bundled file, the
content source, the pack decoder, version parsing, app info and test helpers.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Strict content JSON: tests first

- [x] T004 [P] Write `packages/content_models/test/strict_json_test.dart` for
  `decodeContentJson(String text)` (contracts/loading.md, research R3):
  - **Accepts:** every `canonical` string in `content/examples/canonical-vectors.json`, decoding
    to a value equal to its `input`; the integers 9007199254740991 and -9007199254740991; nesting of
    exactly 32 levels.
  - **Refuses with `ContentJsonError`,** each with its JSON path in `canonicalJson`'s form
    (`$.a[2].b`):
    - `null` at `$.a`;
    - the numbers `1.0`, `1.5` and `1e3`;
    - the integers 9007199254740992 and -9007199254740992;
    - a lone surrogate in a value, and one in a key;
    - nesting of 33 levels;
    - a root that is an array, a string or a number;
    - text that isn't JSON, wrapped as `ContentJsonError`, not a `FormatException`.
  - The result is a `Map<String, Object>`.
- [x] T005 Create `packages/content_models/lib/src/strict_json.dart` with
  `Map<String, Object> decodeContentJson(String text)` and `final class ContentJsonError implements
  Exception {path, message}`. It runs `jsonDecode`, then a recursive walk with the same refusals as
  `canonicalJson`'s `_sorted`, plus a depth limit of 32 and an object root. The refusals are
  "`null`, any `double`, integers outside ±(2^53 - 1), lone surrogates in strings or keys, nesting
  deeper than 32, and a root that isn't an object". Export it from
  `packages/content_models/lib/content_models.dart`, and list it as hand-written in
  `packages/content_models/README.md`. T004 passes, and the package's coverage stays ≥ 80%.

### The dev bundle: tests first

- [x] T006 [P] Write `tools/content_kit/tests/test_bundle.py`, dev mode (contracts/bundling.md):
  - **The written files.** `bundle dev --out <tmp>` writes `core-1.json.gz`, and `bundled.json` in
    canonical JSON with exactly these fields:
    - `pack_id: "core"`, `version: 1`, `file: "core-1.json.gz"`;
    - `size` and `sha256` equal to the file's;
    - `min_client_version` equal to `min_client_version_by_major["1"]` from
      `content/schemas/schema-set.json`;
    - `source: "sample"`.
  - **Golden.** The file's sha256 and size equal `content/examples/sample.golden.json`.
  - **`--check dev`** passes on fresh output. It fails, with exit code 1 and one line per problem,
    on: one changed byte in the file; a changed field in `bundled.json`; a missing file. It leaves a
    `README.md` in the directory alone.
- [x] T007 Create `tools/content_kit/src/wassal_content/bundle.py`. Dev mode reuses `read_layout`,
  `assemble_pack`, `canonical_bytes`, `build_pack_file` and `sha256_hex`, with no second builder.
  Add the subcommand `bundle {dev,release} --out DIR [--check] [--packs-url URL]` to
  `tools/content_kit/src/wassal_content/cli.py`:
  - `release` fails with "not implemented" until T053;
  - the sample path defaults to `content/examples/sample/`, relative to the repository root, as
    `golden` finds it.

  T006 passes, and ruff, mypy and the 80% gate stay green.
- [x] T008 Run `uv run wassal-content bundle dev --out ../../apps/mobile/assets/content/dev` and
  commit `core-1.json.gz` and `bundled.json`. In `.github/workflows/backend.yml`:
  - in the `content-kit` job, after `validate-source`, add a step named
    `Bundled packs match their sources` that runs
    `uv run wassal-content bundle dev --check --out ../../apps/mobile/assets/content/dev`;
  - add `apps/mobile/assets/content/` to the `changes` filter's regular expression.

### Content source and decoder: tests first

- [x] T009 [P] Create `apps/mobile/lib/core/content/refusal_reason.dart` with two enums, each
  value holding its snake_case wire code (contracts/loading.md "Reason codes"):
  - `RefusalReason`: `manifestFailed`, `entryIgnored`, `tooLarge`, `downloadFailed`,
    `sizeMismatch`, `sha256Mismatch`, `checksumFailed`, `decompressTooLarge`, `unreadable`,
    `wrongIdentity`, `schemaUnsupported`, `storageError`, `storedCheckFailed`,
    `bundledCheckFailed`;
  - `RefusalDetail`: `unreachable`, `status`, `tooLarge`, `unreadable`, `redirect`,
    `insecureUrl`, `minClientVersion`, `unusable`, `timeout`.

  Each enum has a `fromWire` that returns null for an unknown code.
- [x] T010 [P] Write `apps/mobile/test/helpers/content.dart`:
  - `sampleBundledBytes()`: reads `assets/content/dev/core-1.json.gz` from disk;
  - `samplePackJson()`: its decoded map;
  - `encodePackFile(Map<String, Object?> json)`: `jsonEncode`, then `GZipCodec(level: 9)`. Returns
    the bytes and an `ExpectedPack` built from them;
  - `samplePackVersion(int v)`: the sample with `version` set to `v`, as `encodePackFile`
    returns it;
  - `sampleActiveContent()`: an `ActiveContent` for version 1, origin bundled;
  - `sampleBundledAssets()`: a map from `assets/content/dev/bundled.json` and
    `assets/content/dev/core-1.json.gz` to their bytes, read from disk. Tests copy it, then damage
    or remove entries;
  - `fakeAssetBytesReader(Map<String, Uint8List?> assets)`: an `AssetBytesReader` (the typedef T024
    adds) that returns the mapped bytes, or null for a path it doesn't list. Tests override
    `assetBytesReaderProvider` with it.

  Grow the file in later tasks with the fakes they name.
- [x] T011 [P] Write `apps/mobile/test/core/content/pack_content_source_test.dart` on the sample
  pack (contracts/content-source.md):
  - `version == 1`;
  - `lines` in `order`: `line_hay`, then `line_gamaa`;
  - `tripsOf(LineId.lineHay)` is `[line_hay.01]`;
  - `tripsOf(LineId.lineGamaa)` is `[line_gamaa.01, line_gamaa.02]`, also when the pack's `trips`
    array is shuffled first;
  - `tripsOf` a line with no trips is empty;
  - `trip('line_gamaa.02')` is found, and `trip('nope')` is null;
  - `vehicles` in order: `tuktuk`, then `micro_old`;
  - `price(SkuKind.vehicle, 'micro_old')` is found, and `price(SkuKind.vehicle, 'tuktuk')`, the
    starter, is null;
  - `price(SkuKind.item, 'salon.nish')` and `price(SkuKind.booster, 'ledger_peek')` are found;
  - `speechPool('passenger.pays')` is found, and an unknown key is null;
  - `chapters` are the four in order, with `chapter(ChapterId.ch3Shabka)` found;
  - `rooms` is `[salon]`, and `itemsOf(RoomId.salon)` is `salon.nish` then `salon.sitara`, by
    `order`;
  - `item('salon.nish')` is found;
  - `familyRequests` is `[req_nish_crystal]`;
  - `dailyRewards` has `day_index` 1 to 7 in order;
  - `tasks` has 3 entries in authored order;
  - every returned list throws `UnsupportedError` on `add`.

  Use the generated enum spellings from `packages/content_models/lib/src/generated/`.
- [x] T012 [P] Write `apps/mobile/test/core/content/decode_pack_file_test.dart` (contracts/loading.md
  "Steps, in order"):
  - **The passing case.** The sample bytes against `bundled.json`'s values give `PackDecoded`, whose
    source has version 1.
  - **One case per step, each with its reason:**
    - size + 1 → `sizeMismatch`;
    - one flipped byte with the same size → `sha256Mismatch`;
    - a gzip of 33,554,433 zero bytes, with its own size and sha256 → `decompressTooLarge`;
    - truncated gzip → `unreadable`;
    - invalid UTF-8 inside valid gzip → `unreadable`;
    - a trip's `at_seconds` set to `38.5` → `unreadable`;
    - an archetype set to `"wizard"` → `unreadable`;
    - `catalog` removed → `unreadable`;
    - `pack_id: "other"` → `wrongIdentity`;
    - `version: 2` when 1 is expected → `wrongIdentity`;
    - `schema_version: "2.0"` → `schemaUnsupported`.
  - **Unknown fields are ignored.** An extra field on a trip still decodes.
  - **Nothing is decompressed before the checksum.** The 33 MiB gzip with a wrong sha256 gives
    `sha256Mismatch`.
  - **`supportedSchemaMajors`** equals the set of keys in `content/schemas/schema-set.json`'s
    `min_client_version_by_major`.
- [x] T013 [P] Write `apps/mobile/test/repo/domain_imports_test.dart`. Every file under
  `lib/core/content/domain/` imports only `dart:core`, `dart:collection` and
  `package:content_models/…`. Any `package:flutter`, other `package:` or `dart:io` import fails, and
  the message names the file and line. Include a self-test of the scanner on sample sources, as
  `integer_money_test.dart` does.
- [x] T014 [P] Write `apps/mobile/test/core/content/client_version_test.dart` for
  `ClientVersion`:
  - `parse('1.0.0')` and `parse('1.0.0+2')` give the same version, and `+BUILD` is kept separately;
  - malformed values (`'1.0'`, `'v1.0.0'`, `'1.0.0-beta'`, `''`) return null;
  - comparison is numeric: `1.10.0 > 1.9.0`;
  - `atLeast(min)` ignores the build.
- [x] T015 Create `apps/mobile/lib/core/content/domain/content_source.dart` with the
  `ContentSource` interface exactly as in contracts/content-source.md, and
  `apps/mobile/lib/core/content/pack_content_source.dart` with `PackContentSource(Pack pack)`:
  - maps and sorted, unmodifiable lists are built in the constructor;
  - trips are sorted by the numeric suffix of `trip_id`;
  - unknown ids return null or an empty list and never throw.

  T011 and T013 pass.
- [x] T016 [P] Create `apps/mobile/lib/core/content/client_version.dart` with `ClientVersion`
  (parse, compare, `atLeast`, `build`). T014 passes.
- [x] T017 Create `apps/mobile/lib/core/content/decode_pack_file.dart`:
  - `ExpectedPack {version, size, sha256, minClientVersion}`;
  - the sealed `PackDecodeResult` with `PackDecoded {source, canonicalBytes}` and
    `PackRefused {reason}`;
  - `const supportedSchemaMajors = {1}`, `const maxDecompressedBytes = 33554432`;
  - `PackDecodeResult decodePackFile(Uint8List bytes, ExpectedPack expected)`, running steps 1–7 in
    order with a streaming `GZipCodec().decoder` that counts output and stops past the cap.

  Every exception or error thrown in steps 3–5 maps to `unreadable` inside this one function, with
  a comment explaining why this boundary catches broadly (research R3). T012 passes.
- [x] T018 [P] Create `apps/mobile/lib/core/platform/app_info.dart`:
  - the `AppInfo` interface {`version`, `buildNumber`, `versionWithBuild` (`<version>+<build>`),
    `platform` (`android` or `ios`)};
  - `PackageInfoAppInfo.load()` over `package_info_plus`;
  - a keep-alive `@riverpod Future<AppInfo> appInfo(Ref ref)`.

  Add `FakeAppInfo('1.0.0+2')` to `apps/mobile/test/helpers/content.dart`.

**Checkpoint**: The strict decoder, the dev bundle, the content source and the pack decoder are
green. User stories can start.

---

## Phase 3: User Story 1 - The game always has content, even offline on first launch (Priority: P1) 🎯 MVP

**Goal**: Every launch, online or not, reaches Home with the bundled pack checked, decoded off the
UI isolate and served through the content source (FR-001 to FR-014).

**Independent Test**: A dev build in airplane mode reaches الموقف, with `content: active v1
(bundled)` in `flutter logs` (quickstart scenario 2). In CI, `startup_test.dart` does the same with
no network.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [x] T019 [P] [US1] Write `apps/mobile/test/core/content/bundled_pack_test.dart` for
  `loadBundledPack(reader, flavor)`:
  - dev reads `assets/content/dev/bundled.json`, and staging and prod read
    `assets/content/release/bundled.json`;
  - it returns the record and the file bytes;
  - a missing record → `BundledPackMissing`;
  - a record that breaks a data-model rule → `BundledPackInvalid`. The rules are "`pack_id`
    `"core"`; `version` ≥ 1; `file` `core-<version>.json.gz`; `size` ≥ 1; `sha256` 64 lowercase
    hex; `min_client_version` `MAJOR.MINOR.PATCH`; `source` `sample` or `content_source`". Test one
    case per rule, plus a `float` size and an unknown `source`;
  - a record that names a missing file → `BundledPackMissing`.
- [x] T020 [P] [US1] Write `apps/mobile/test/core/content/content_controller_bundled_test.dart`,
  with an inline `PackDecoder` and `fakeAssetBytesReader(sampleBundledAssets())` from T010:
  - a fresh install gives `ActiveContent(version: 1, origin: bundled)`;
  - `contentSourceProvider` and `contentVersionProvider` read it synchronously after the future
    completes;
  - a bundled file with one flipped byte makes the provider's future fail with
    `ContentUnavailable`;
  - in debug mode, `debugPrint` receives `content: active v1 (bundled) in <n> ms`. Capture it by
    overriding `debugPrint`;
  - **off the UI isolate (FR-007):** the default `packDecoderProvider` value is the top-level
    `isolatePackDecoder`, and `isolatePackDecoder` decodes the sample pack to version 1. Its body is
    only `Isolate.run(() => decodePackFile(bytes, expected))`, which T065's review checks.
- [x] T021 [P] [US1] Write `apps/mobile/test/core/content/startup_test.dart`, widget tests with
  `pumpApp` from `test/helpers/pump_app.dart`:
  - the boot screen stays until `activeContentProvider` completes, then hands over to `/home`;
  - a damaged bundled pack shows `l10n.bootErrorMessage` and the `l10n.bootRetry` button, and never
    shows Home;
  - after repairing the fake asset, retry reaches Home, because `retryAppStartup` invalidated
    `activeContentProvider`.
- [x] T022 [P] [US1] Write `apps/mobile/test/repo/bundled_pack_test.dart`, the dev and app-version
  part (contracts/bundling.md "What refuses a wrong build"):
  - `assets/content/dev/bundled.json` agrees with `core-1.json.gz`'s size and sha256;
  - its sha256, size and version equal `content/examples/sample.golden.json`'s;
  - the pubspec `version` matches `^\d+\.\d+\.\d+\+\d+$`;
  - the version is at least `min_client_version_by_major["1"]` in `content/schemas/schema-set.json`,
    and at least every bundled `min_client_version`.

  Leave a marked place for the release rules (T052).
- [x] T023 [P] [US1] Write `apps/mobile/test/helpers/synthetic_packs.dart` (research R15):
  - **`mvpSizePack()`**: the sample, with trips cloned and renumbered to `line_hay.01`–`.20` and
    `line_gamaa.01`–`.30`, chapters 1–4, and every pool;
  - **`twoMebibytePack()`**: like `mvpSizePack()`, plus speech lines of pseudo-random Arabic letters
    from a seeded xorshift32 (seed 20261021), added until the gzip is ≥ 2,097,152 bytes.

  Both return bytes plus `ExpectedPack`. Then write
  `apps/mobile/test/core/content/perf/load_budget_test.dart`: `decodePackFile` on `mvpSizePack()`
  takes < 300 ms, and on `twoMebibytePack()` < 1,000 ms, the median of 5 runs after one warm-up.

### Implementation for User Story 1

- [x] T024 [US1] Create `apps/mobile/lib/core/content/bundled_pack.dart`:
  - `BundledPackRecord`, parsed with `decodeContentJson` and checked against the data-model rules;
  - `BundledPackMissing` and `BundledPackInvalid`;
  - `Future<BundledPack> loadBundledPack(AssetBytesReader read, Flavor flavor)`, choosing
    `assets/content/dev/` for dev and `assets/content/release/` for staging and prod.

  In `apps/mobile/lib/core/config/config_providers.dart`, add
  `typedef AssetBytesReader = Future<Uint8List?> Function(String path)` and a keep-alive
  `assetBytesReaderProvider`. It returns null when the asset isn't in the `AssetManifest`, as
  `_readBundledAsset` does. T019 passes.
- [x] T025 [US1] Create `apps/mobile/lib/core/content/content_controller.dart` and
  `apps/mobile/lib/core/content/content_providers.dart` (contracts/content-source.md "Providers"):
  - `ActiveContent {version, origin (ContentOrigin.bundled | stored), source}`;
  - `ContentUnavailable`;
  - `typedef PackDecoder = Future<PackDecodeResult> Function(Uint8List, ExpectedPack)`, and a
    `packDecoderProvider` whose default is the top-level `isolatePackDecoder`. That function only
    runs `decodePackFile` through `Isolate.run` (FR-007);
  - the keep-alive `ContentController` (`@Riverpod(keepAlive: true)` `AsyncNotifier`) whose
    `build()` loads and decodes the bundled pack, throws `ContentUnavailable` if it is refused, and
    times itself with a `Stopwatch`. In `kDebugMode || kProfileMode` it prints
    `content: active v<N> (<origin>) in <ms> ms` with `debugPrint`;
  - `contentSourceProvider` and `contentVersionProvider` (keep-alive, `requireValue`).

  Run build_runner. T020 passes.
- [x] T026 [US1] In `apps/mobile/lib/bootstrap/startup.dart`, add
  `ref.watch(activeContentProvider.future)` to `appStartup`'s `Future.wait`, and
  `..invalidate(activeContentProvider)` to `retryAppStartup`. T021 and T022 pass, and so do the
  existing boot screen tests and goldens unchanged (FR-040). Update any test that pumps the app
  without content to override `activeContentProvider` with `sampleActiveContent()`.
- [x] T027 [P] [US1] Create `apps/mobile/integration_test/content_load_perf_test.dart` and
  `apps/mobile/test_driver/integration_test.dart` (research R15):
  - the test builds `mvpSizePack()` and `twoMebibytePack()` from `../test/helpers/synthetic_packs.dart`;
  - it times `decodePackFile` through `Isolate.run`, 5 runs each after a warm-up;
  - it reports the medians with `IntegrationTestWidgetsFlutterBinding.reportData` and expects
    ≤ 500 ms and ≤ 1,500 ms.

  It isn't run in CI (contracts/ci-checks.md).

**Checkpoint**: US1 is complete. The app always reaches Home with the bundled pack, and every
reader can use `contentSourceProvider`.

---

## Phase 4: User Story 2 - New content arrives without an app update (Priority: P2)

**Goal**: The app checks the manifest, downloads a newer pack from its URL, verifies it and makes
it active at launch or on arrival at Home (FR-015 to FR-027, FR-036, FR-037).

**Independent Test**: Quickstart scenario 3 against the local stack. In CI,
`content_updater_test.dart` and `home_arrival_test.dart` run against fakes, and
`dio_content_remote_test.dart` against a local `HttpServer`.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [x] T028 [P] [US2] Write `apps/mobile/test/core/network/api_environment_test.dart` (research R11):
  - `apiBaseUrl(Flavor.dev)` is `http://localhost:8000`, or the injected
    `WASSAL_DEV_API_BASE` value;
  - staging is `https://staging-api.141-147-129-92.sslip.io`, and prod is
    `https://api.193-122-74-125.sslip.io`;
  - `isAllowedUrl(flavor, uri)`:
    - staging and prod allow only `https`;
    - dev also allows `http` for `localhost`, `127.0.0.1` and `10.0.2.2`;
    - `ftp:`, `file:`, a relative URL and `http://example.com` in dev are refused.
- [x] T029 [P] [US2] Write `apps/mobile/test/core/network/dio_content_remote_test.dart` against a
  `dart:io` `HttpServer` bound to `127.0.0.1` (dev flavor, contracts/updates.md "Requests"):
  - **Manifest.**
    - A `200` with a valid body → `ManifestOk`. The request carries `Accept: application/json`,
      `X-Client-Version: 1.0.0+2` and `X-Platform: android`.
    - `302` → `redirect`, and the target is never requested.
    - `500` and `429` → `status`.
    - 65,537 bytes → `tooLarge`.
    - Non-JSON, a `version` of `1.5`, or a missing `packs` → `unreadable`.
    - A server that stalls past the (injected, shortened) receive timeout → `unreachable`.
  - **Download.**
    - A `200` streams to the target file and returns `Downloaded(size, sha256)`, equal to the
      served bytes.
    - One byte over `entry.size` → `DownloadFailed(tooLarge)`.
    - `302` → `redirect`, and `404` → `status`.
    - A stall → `timeout`.
    - Cancelling mid-stream → `DownloadCancelled`.
    - **1 Mbit/s (SC-006).** The server sends `mvpSizePack()` from `test/helpers/synthetic_packs.dart`
      (T023) at 125,000 bytes/s. The download completes, and the download plus `decodePackFile`
      take less than 30 s.
  - **Flavor rule.** With the staging flavor, an `http://127.0.0.1` URL is refused before any
    connection: the server records no request.
- [x] T030 [P] [US2] Write `apps/mobile/test/core/content/pack_store_test.dart`, the basic
  operations, on a temp directory (contracts/loading.md "PackStore"):
  - **The `state.json` codec** round-trips every data-model field. The rules include "`format` int
    `1`", `stored` at most 2 ("at most one `active` and one `ready`"), and `last_check_at` UTC
    ISO-8601.
  - **`beginDownload` then `commitDownload`** leave `core-<v>.json.gz` and a `ready` entry, with no
    `tmp/` file left. A second `commitDownload` of a higher version deletes the older ready file.
  - **`activate(v)`** makes it `active` and deletes the old active file.
  - **`markChecked`** records the time. **`restoreChecked(previous)`** puts back the previous time,
    or removes it when `previous` is null. **`recordFailure`** appends an event `{at, reason,
    version?, detail?}`.
  - **No `state.json.tmp`** remains after any write.

  Add `expectStoreInvariants(dir, appVersion)` to `apps/mobile/test/helpers/content.dart`. It
  checks data-model.md invariants 1–4, and every test in this file ends by calling it.
- [x] T031 [P] [US2] Write `apps/mobile/test/core/content/content_controller_stored_test.dart`:
  - a stored `ready` v2 (from `samplePackVersion(2)`) above the bundled v1 → active v2 from stored,
    and `state.json` shows it `active`;
  - a stored `active` v2 stays active;
  - a stored entry whose `min_client_version` is above the app's `1.0.0+2` is skipped: the bundled
    pack wins and the stored entry is dropped;
  - `acceptReady(v3)`, then `switchIfReady()`, makes v3 active in one state change. A listener sees
    exactly one new `ActiveContent`;
  - `switchIfReady()` with no ready pack does nothing.
- [x] T032 [P] [US2] Write `apps/mobile/test/core/content/content_updater_test.dart` with a
  `FakeContentRemote`, a fake clock and a fake `ConnectivitySource`. Add the fakes to
  `test/helpers/content.dart`. Cover (contracts/updates.md):
  - **Triggers.** A check runs after `start()`, on `onResume()`, and when connectivity goes from
    offline to online. Online → online doesn't trigger one.
  - **Throttle.** 14 min 59 s after the last check → no request. 15 min → a request. A
    `last_check_at` in the future counts as elapsed. `check(force: true)` skips only the throttle.
  - **One at a time.** A trigger during a running check is a no-op.
  - **Entry rules**, one case each (data-model.md "Manifest entry"):
    - no `core` entry, a version not above the active or ready one, or `version: 0` → nothing,
      with no event;
    - `size` 16,777,217 → `tooLarge`;
    - `min_client_version` `9.0.0` → `entryIgnored/minClientVersion`;
    - a version listed in `unusable` (seeded in `state.json`) → `entryIgnored/unusable`;
    - an `http` URL with the staging flavor → `entryIgnored/insecureUrl`.
  - **`ManifestFailed(unreachable)`** → one `manifestFailed` event, and the active pack is
    unchanged.
  - **A good v2** → the store holds a `ready` v2, and the controller holds it in memory. A second
    check offering v2 again downloads nothing (US2-8).
- [x] T033 [P] [US2] Write `apps/mobile/test/core/content/home_arrival_test.dart`, widget tests
  with the real router from `lib/core/routing/router.dart` and a controller holding a ready v2:
  - from `/lines`, going to `/home` switches to v2;
  - these locations don't switch: `/home/pre-trip/line_hay.01`, `/trip/line_hay.01`,
    `/trip/line_hay.01/result` and `/shop/fuel`;
  - a pack that becomes ready while `/home` is showing doesn't switch until the next arrival;
  - the trip pause overlay, which has no path, never switches;
  - **the updater waits for startup:** when the whole app is pumped, `FakeContentRemote` records no
    request until the boot screen has handed over to `/home` (T041 starts the updater only after
    `appStartup`).
- [x] T034 [P] [US2] Write `apps/mobile/test/repo/cleartext_config_test.dart` (research R12):
  - under `android/app/src/*/res/xml/`, only `dev/res/xml/network_security_config.xml` exists;
  - it has exactly one `domain-config` with `cleartextTrafficPermitted="true"`, whose domains are
    `localhost`, `127.0.0.1` and `10.0.2.2`, and no `base-config` that permits cleartext;
  - `android/app/src/dev/AndroidManifest.xml` sets
    `android:networkSecurityConfig="@xml/network_security_config"`;
  - the `main`, `staging` and `prod` manifests have no `networkSecurityConfig` or
    `usesCleartextTraffic`;
  - `main/AndroidManifest.xml` declares `android.permission.INTERNET`.

### Implementation for User Story 2

- [x] T035 [P] [US2] Create `apps/mobile/lib/core/network/api_environment.dart` (research R11):
  - `String apiBaseUrl(Flavor flavor, {String devOverride = const
    String.fromEnvironment('WASSAL_DEV_API_BASE')})`;
  - `bool isAllowedUrl(Flavor flavor, Uri uri)`;
  - the hostnames as named constants, with a comment pointing to
    `docs/runbooks/provision-host.md` and the delivery plan's domain-switch item.

  T028 passes.
- [x] T036 [P] [US2] Create `apps/mobile/lib/core/platform/connectivity.dart`:
  - the `ConnectivitySource` interface {`Stream<bool> get online`, `Future<bool> isOnline()`};
  - `ConnectivityPlusSource`, which maps `List<ConnectivityResult>` to "any result other than
    `none`";
  - a keep-alive provider.
- [x] T037 [US2] Create `apps/mobile/lib/core/content/content_remote.dart` with the
  `ContentRemote` interface and the sealed `ManifestResult` and `DownloadResult` types.

  Create `apps/mobile/lib/core/network/http_client.dart`:
  - `Dio createHttpClient(Flavor flavor, AppInfo info)`, with `followRedirects: false`, a
    `validateStatus` that accepts every status (callers check for `200`), the 10 s connect timeout,
    and the `X-Client-Version` and `X-Platform` headers;
  - the caps and timeouts from contracts/updates.md as named constants: 65,536 bytes for the
    manifest, 16,777,216 for a download, a 10 s manifest receive timeout, 30 s between download
    chunks and 120 s per download.

  Create `apps/mobile/lib/core/network/dio_content_remote.dart` (`DioContentRemote`):
  - streamed bodies, byte counting and chunked SHA-256;
  - `isAllowedUrl` checked before every request;
  - a `CancelToken` on both calls;
  - the manifest decoded with `decodeContentJson` and `Manifest.fromJson`.

  T029 passes.
- [x] T038 [US2] Create `apps/mobile/lib/core/content/content_state.dart`: the `state.json` model
  and codec (data-model.md "Content state"), reading through `decodeContentJson`. An unknown
  `format`, or a file that doesn't parse, gives the empty state.

  Create `apps/mobile/lib/core/content/pack_store.dart`, with `PackStore(Directory dir)` and the
  operations `beginDownload`, `commitDownload`, `activate`, `dropStored`, `markChecked`,
  `restoreChecked` and `recordFailure` (event append only for now). Every `state.json` write goes to `state.json.tmp`
  with `flush: true`, then `rename`. Add a keep-alive `packStoreProvider` on
  `<getApplicationSupportDirectory()>/content/`. T030 passes.
- [x] T039 [US2] Extend `apps/mobile/lib/core/content/content_controller.dart`:
  - **`build()`** first awaits `appInfoProvider` and `packStoreProvider`. Its candidates are the
    stored entries whose `min_client_version` is at most the app version, plus the bundled pack,
    highest version first. The first that decodes wins. A stored `ready` winner is `activate`d, and
    a bundled winner calls `dropStored()` (contracts/loading.md "Launch", steps 2–5).
  - **`acceptReady(PackContentSource source)`** holds the ready pack in memory.
  - **`switchIfReady()`** sets the state synchronously, then awaits `store.activate`. A failure is
    recorded as `storageError`.

  T031 passes, and T020 still does.
- [x] T040 [US2] Create `apps/mobile/lib/core/content/content_updater.dart` (`ContentUpdater`)
  with `start()`, `onResume()`, `onConnectivity(bool online)` and `check({bool force = false})`:
  - the 15-minute throttle from `state.last_check_at` against an injected clock;
  - one check at a time;
  - the entry rules;
  - check steps 1–6 from contracts/updates.md "One check", with refusals recorded as events.

  Add `contentUpdaterProvider` to `content_providers.dart`. T032 passes.
- [x] T041 [US2] Create `apps/mobile/lib/core/content/home_arrival.dart` (`HomeArrival`), which
  listens to `GoRouter.routerDelegate`. When the current URI path changes from anything else to
  exactly the Home destination's path (read from `routes.dart`, not a literal), it calls
  `switchIfReady()`. Wire it in `apps/mobile/lib/bootstrap/app.dart`, once `appStartup` has
  completed:
  - attach `HomeArrival` to the router;
  - call `contentUpdater.start()`;
  - forward `AppLifecycleListener.onResume` to `onResume()`;
  - subscribe `ConnectivitySource.online` to `onConnectivity`;
  - dispose all of them with the app.

  T033 passes.
- [x] T042 [US2] Android network setup in `apps/mobile/android/app/src/` (research R12):
  - add `<uses-permission android:name="android.permission.INTERNET"/>` to
    `apps/mobile/android/app/src/main/AndroidManifest.xml`;
  - create `apps/mobile/android/app/src/dev/res/xml/network_security_config.xml`, with one
    `domain-config cleartextTrafficPermitted="true"` for `localhost`, `127.0.0.1` and `10.0.2.2`;
  - create `apps/mobile/android/app/src/dev/AndroidManifest.xml`, which merges
    `android:networkSecurityConfig="@xml/network_security_config"` into `<application>`.

  T034 passes, and `fvm flutter build apk --flavor dev --debug` builds.

**Checkpoint**: US2 is complete. A newer pack on the server reaches the device and becomes active
at launch or on arrival at Home.

---

## Phase 5: User Story 3 - A bad file or an interrupted update never breaks the game (Priority: P2)

**Goal**: Refusals, attempts, the unusable list, reconciling files at launch, every kill point,
app updates, storage errors and leaving the foreground all leave exactly one verified pack active
(FR-022, FR-023, FR-028 to FR-031, FR-038).

**Independent Test**: `fvm flutter test test/core/content test/core/network` (quickstart scenario
4): every refusal and every kill point ends with one verified active pack.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [x] T043 [P] [US3] Add to `apps/mobile/test/core/content/pack_store_test.dart` (research R14):
  - **`reconcile()`:**
    - removes `tmp/`;
    - deletes a `core-9.json.gz` that `state.json` doesn't list;
    - drops an entry whose file is missing;
    - a `state.json` with `format: 2`, or bytes that don't parse, counts as empty, and every stored
      file is deleted.
  - **`recordFailure`:**
    - the 1st and 2nd `sha256Mismatch` of v5 set `attempts` to 1 and 2;
    - the 3rd moves v5 to `unusable` with `checksumFailed` and removes its `attempts` entry;
    - `unreadable` puts a version in `unusable` at once.
  - **`setAppVersion`:** `1.0.0+3` after `1.0.0+2` clears `unusable` and `attempts`. The same value
    keeps them.
  - **Events:**
    - after 25 events, only the last 20 remain, oldest first;
    - an event's keys are only `at`, `reason`, `version` and `detail`.
- [x] T044 [P] [US3] Write `apps/mobile/test/core/content/kill_points_test.dart`. For each
  `KillPoint` (`partWritten`, `partFlushed`, `renamed`, `stateWritten`, `activateStateWritten`):
  1. start from bundled v1 plus a stored active v2;
  2. download v3, or activate a ready v3, with the hook throwing at that point;
  3. build a fresh `ContentController` on the same directory.

  Assert that exactly one pack is active (v2 or v3, never a partial file), that
  `expectStoreInvariants` passes, and that neither `tmp/` nor a stray `core-*.json.gz` remains
  (SC-005).
- [x] T045 [P] [US3] Write `apps/mobile/test/core/content/launch_selection_test.dart`, one test per
  row of data-model.md "Choosing the active pack at launch":
  - fresh install;
  - a stored ready pack that passes;
  - the top stored entry fails (one flipped byte): the next candidate wins, the entry and file are
    removed, a `storedCheckFailed` event is recorded, and the version is not in `unusable`;
  - an app update whose bundled pack (v4) is above the stored v3: bundled wins and every stored
    entry is deleted;
  - an app update whose bundled pack is lower: the stored entry stays;
  - nothing passes: `ContentUnavailable` and a `bundledCheckFailed` event;
  - on an app version change, `unusable` and `attempts` are cleared before candidates are chosen.
- [x] T046 [P] [US3] Write `apps/mobile/test/core/content/content_updater_refusals_test.dart`,
  with `FakeContentRemote` serving crafted bytes:
  - **Checksum failures.** A size or sha256 mismatch counts an attempt, and the version is
    downloaded at most 3 times across checks, then becomes `unusable` (SC-008).
  - **Content refusals.** `decompressTooLarge`, `unreadable`, `wrongIdentity` and
    `schemaUnsupported` each make the version `unusable` after one download. After
    `setAppVersion('1.0.0+3')` it is downloaded again.
  - **Download errors.** `tooLarge` and `downloadFailed` leave no part file and are retried at the
    next check.
  - **Storage errors.** A store hook throwing `FileSystemException` on rename gives a
    `storageError` event, leaves no part file and keeps the active pack.
  - **Leaving the foreground.** `onBackground()` during a download cancels it: no event, no part
    file, and the next check starts again.
  - **A cancel doesn't use up the 15 minutes (FR-015).** After the cancel, `last_check_at` is back to
    its value from before that check (absent, if there was none), so an `onResume()` right after
    makes a request and downloads again.
  - **No switch.** None of these changes the active pack (SC-004).

### Implementation for User Story 3

- [x] T047 [US3] Extend `apps/mobile/lib/core/content/pack_store.dart`:
  - `reconcile()`;
  - `recordFailure`, with attempts and the unusable list (3 attempts → `checksumFailed`; decoder
    refusals → unusable at once), and events capped at 20 as a named constant;
  - `setAppVersion`;
  - a `KillPoint` enum and an optional `void Function(KillPoint)? onKillPoint` hook, called at each
    point in contracts/loading.md "Kill points";
  - `FileSystemException` turned into `storageError`.

  T043 passes.
- [x] T048 [US3] Extend `ContentController.build()` in
  `apps/mobile/lib/core/content/content_controller.dart`:
  - first `reconcile()`, then `setAppVersion`;
  - a stored candidate that fails is removed with a `storedCheckFailed` event (no attempt, no
    unusable);
  - a refused bundled pack gives a `bundledCheckFailed` event before `ContentUnavailable`.

  T044 and T045 pass, and T031 still does.
- [x] T049 [US3] Extend `apps/mobile/lib/core/content/content_updater.dart`:
  - attempts and the unusable list through `recordFailure`;
  - part files deleted on every failure;
  - `storageError` handling;
  - `onBackground()` cancelling the running request's `CancelToken`, then calling
    `store.restoreChecked(previous)` with the `last_check_at` saved at step 1 of that check
    (contracts/updates.md "One check").

  In `apps/mobile/lib/bootstrap/app.dart`, forward `AppLifecycleListener` `onPause`, `onHide` and
  `onDetach` to `onBackground()`. T046 passes, and T032 still does.

**Checkpoint**: US3 is complete. No bad file, kill, update or full disk leaves the app without a
verified pack.

---

## Phase 6: User Story 4 - Every build ships a pack its server knows (Priority: P3)

**Goal**: Staging and prod bundle only the newest promoted pack from `content/source/`, checked
against production's release record, and a build without one is refused (FR-033, FR-034).

**Independent Test**: `test_bundle.py` and `bundled_pack_test.dart` accept a correct release
bundle and refuse each wrong case. Until the first promotion, `fvm flutter build apk --flavor
staging --debug` stops at `checkBundledPack` (quickstart scenario 5).

### Tests for User Story 4 ⚠️ (write first, must fail)

- [x] T050 [P] [US4] Add release-mode tests to `tools/content_kit/tests/test_bundle.py`. The
  fixture is a temp copy of the sample with `pack.json` at version 7, and an injected fetcher
  returning a canonical release record whose `sha256`, `size`, `pack_id` and `version` match the
  rebuilt file, with `min_client_version: "1.0.0"` and every stage `passed`:
  - **The written files.** It writes `core-7.json.gz`, the record copy `core-7.release.json`, and
    `bundled.json` with `source: "content_source"`, the record's `min_client_version`, and
    `release_record_sha256` equal to the sha256 of the record bytes. It removes `README.md` and
    any other `core-*`.
  - **Warnings are accepted.** A `size` or `solver` stage of `warning` passes.
  - **Failures**, each with exit code 1 and a message:
    - `pack.json` missing, or at version 0;
    - layout findings;
    - an `http://` packs URL;
    - the fetcher raising;
    - a record over 65,536 bytes;
    - a record with a float;
    - a mismatched `pack_id`, `version`, `sha256` or `size`;
    - a stage `failed`.
  - **`--check release`:**
    - passes on fresh output;
    - fails on one changed byte in the file, a changed `bundled.json`, a record copy whose
      `sha256` differs from the file, and a `release_record_sha256` that differs from the copy;
    - with no `content/source/pack.json`, passes only when the directory holds nothing but
      `README.md`.
- [x] T051 [P] [US4] Test the record fetcher in `tools/content_kit/tests/test_bundle.py`:
  - it refuses a non-`https` URL before any request;
  - it reads at most 65,536 bytes, with a 10 s timeout;
  - it refuses redirects. Test this with a `urllib` opener whose handler returns a `302`.
- [x] T052 [P] [US4] Add the release rules to `apps/mobile/test/repo/bundled_pack_test.dart`,
  at the place T022 marked:
  - **With `content/source/pack.json` present, at version `v` > 0:**
    - `assets/content/release/bundled.json` exists with version `v`;
    - its size and sha256 agree with `core-<v>.json.gz`;
    - the record copy's `sha256` and `size` fields equal `bundled.json`'s;
    - `release_record_sha256` equals the copy's sha256;
    - `min_client_version` is at most the pubspec version.
  - **Otherwise** the directory holds only `README.md`.

### Implementation for User Story 4

- [x] T053 [US4] In `tools/content_kit/src/wassal_content/bundle.py`, implement release mode and
  `--check release`, with the record fetcher over `urllib.request`
  (HTTPS only, no redirects, a 65,536-byte cap, a 10 s timeout). Parse the record with the
  content kit's strict loader. Remove the "not implemented" from the CLI. T050 and T051 pass, and
  ruff, mypy and the 80% gate stay green.
- [x] T054 [US4] In `apps/mobile/android/app/build.gradle.kts`, register `checkBundledPack`. It
  throws a `GradleException` with the message in contracts/bundling.md ("No promoted pack is
  bundled. Run wassal-content bundle release (docs/runbooks/content-publishing.md §3).") when
  `rootProject.file("../assets/content/release/bundled.json")` doesn't exist. Make every
  `pre(Staging|Prod)(Debug|Profile|Release)Build` task depend on it. Leave a comment linking
  contracts/bundling.md.
- [x] T055 [US4] In `.github/workflows/backend.yml`, extend the `Bundled packs match their
  sources` step (T008) with
  `uv run wassal-content bundle release --check --out ../../apps/mobile/assets/content/release`.
  T052 passes in the app job.
- [x] T056 [P] [US4] Add the bundling step to `docs/runbooks/content-publishing.md` §3 ("Bring the
  content back into the repository"). After unzipping the export into `content/source/`, run:

  ```text
  uv run wassal-content bundle release \
    --packs-url https://api.193-122-74-125.sslip.io/packs/ \
    --out ../../apps/mobile/assets/content/release
  ```

  Commit the export and the three asset files in the same pull request. Then explain what CI
  checks (contracts/bundling.md "The publisher's step").
- [x] T057 [US4] Run scenario 5 of `specs/006-m04-content-loader/quickstart.md`:
  - `fvm flutter build apk --flavor staging --debug` stops at `checkBundledPack` with the message;
  - `fvm flutter build apk --flavor dev --debug` still builds.

**Checkpoint**: Every story is complete. Each build can bundle only a pack its server serves byte
for byte.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documents, coverage, the full quickstart, review, and the owner's items.

- [x] T058 [P] Update `docs/architecture-mobile.md` (research R17):
  - **§14.1:**
    - until M06, the app checks the manifest itself at launch, on resume and when the connection
      returns, at most every 15 minutes;
    - dev bundles the sample, and staging and prod bundle the newest `content/source/` pack;
    - the switch happens only at launch or on arrival at Home;
    - the 64 KiB, 16 MiB and 32 MiB caps;
    - link to this feature's contracts.
  - **§11:** `content_cache` is `state.json` in `<app support>/content/` until M05.
  - **§5:** list `core/content/` (with `domain/`) and `core/network/`.
- [x] T059 [P] Update `CLAUDE.md`:
  - **"Project status":** the app now loads content packs (M04, `specs/006-m04-content-loader/`).
  - **"Mobile commands":**
    - build `packages/content_models` first after a fresh checkout;
    - for dev builds against the local stack, run `adb reverse tcp:8000 tcp:8000` and use
      `localhost:8000`;
    - `--dart-define=WASSAL_DEV_API_BASE` overrides the dev API address;
    - staging and prod builds need a bundled promoted pack.
  - **"Content commands":** the four `wassal-content bundle` commands.
- [x] T060 [P] Update `docs/delivery-plan.md`:
  - **Progress:**
    - `005-b05-solver-parity` merged in #6 on 2026-10-21; tick it, and tick step 3;
    - add M04's line: the app becomes 1.0.0; downloads are in M04; staging and prod bundle
      `content/source/`; constitution 1.2.0 (amended 2026-10-21) allows plain HTTP in dev builds
      only.
  - **Step 1's "Decided in B01" item:** the domain switch also edits
    `apps/mobile/lib/core/network/api_environment.dart`.
  - **Step 4:** hand-overs to M02, M05 and M06 from research.md "Handed to later features".
- [x] T061 [P] Add the M04 section to `docs/owner-actions.md`, and update "Open now": the B05 row
  says merged in #6, plus an M04 row.
  - **Before merge:** none.
  - **After merge:**
    - **T062:** the A06 timing (quickstart scenario 6) and the cold start;
    - **after production's first promotion:** run `bundle release` and commit it (runbook §3); make
      the first staging build; then, after the next staging publish, check that the staging app
      downloads and switches at Home (SC-006);
    - **with a real MVP pack:** the cold-start measurement again on a prod build.
- [ ] T062 **Owner** (after merge): run `apps/mobile/integration_test/content_load_perf_test.dart`
  on the Galaxy A06 (quickstart scenario 6). Record the two
  medians and the cold-start median in a follow-up issue, then tick the item in
  `docs/owner-actions.md`.
- [x] T063 Run the coverage gates in `apps/mobile`, `packages/content_models` and
  `tools/content_kit`:
  - `fvm dart run tool/check_coverage.dart --min 80` in `apps/mobile`;
  - the `content_models` gate;
  - `uv run pytest --cov --cov-fail-under=80` in `tools/content_kit`.

  Add tests for any uncovered branch until each passes. Don't exclude files.
- [ ] T064 Run every check in [quickstart.md](./quickstart.md), and all pass:
  - **scenario 1:**
    - `apps/mobile`: format, `flutter analyze --fatal-infos`, `flutter test`;
    - `packages/content_models` and `packages/trip_engine` tests;
    - `tools/content_kit`: ruff, mypy, pytest, `codegen --check`, `golden` and both
      `bundle --check`;
  - **scenarios 2–5**, on an emulator and the local stack.

  Status on 2026-10-21: scenario 1 (every automated check), 4 (the refusal and kill-point tests) and
  5 (staging stops at `checkBundledPack`, dev builds) pass. Scenarios 2 and 3 need a phone or an
  emulator, and none was attached: they are the owner's before-merge item in
  `docs/owner-actions.md`.
- [x] T065 Review the diff in `apps/mobile`, `packages/content_models` and `tools/content_kit`:
  - run the `code-reviewer` and `flutter-reviewer` agents on `apps/mobile` and
    `packages/content_models`, and the `python-reviewer` on `tools/content_kit`;
  - run the `security-reviewer` on `lib/core/network/`, `decode_pack_file.dart`, `pack_store.dart`,
    `bundle.py` and the Android network config (plan "Security & privacy");
  - check every changed file against constitution I, II, V, VII and XIII;
  - fix every CRITICAL and HIGH finding.
- [x] T066 **Owner:** approve the amendment of `.specify/memory/constitution.md` to 1.2.0 (plain
  HTTP in the dev flavor only, which replaces planning's Complexity Tracking exception). Done:
  approved on 2026-10-21. Remove the Sync Impact Report comment at the top of the constitution
  before it is committed.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies. T001 comes first, and T002 and T003 run in parallel with it.
- **Foundational (Phase 2)**: depends on Setup.
  - T004 → T005.
  - T006 → T007 → T008. T008 produces the dev bundle that T010, T011, T012 and T022 read.
  - T009, T013, T014 and T018 can start at once.
  - T015 needs T011 and T013. T016 needs T014. T017 needs T005, T009, T012 and T015.
- **US1 (Phase 3)**: depends on Foundational. Its tests T019–T023 are parallel, then T024 → T025 →
  T026. T027 needs T023 and T017.
- **US2 (Phase 4)**: depends on US1, because it extends `ContentController` and `startup.dart`.
  - Tests T028–T034 are parallel.
  - T035 and T036 are parallel.
  - Then T037 → T038 → T039 → T040 → T041. T042 can go at any point after T034.
- **US3 (Phase 5)**: depends on US2 (`pack_store.dart`, `content_updater.dart`). Tests T043–T046
  are parallel, then T047 → T048 → T049.
- **US4 (Phase 6)**: needs only Foundational (T007, T008) and US1's T022. It can run in parallel
  with US2 and US3 if staffed.
  - Tests T050–T052 are parallel.
  - Then T053 → T055. T054 and T056 are parallel with those. T057 comes last.
- **Polish (Phase 7)**: after every story. T058–T061 are parallel. T063 → T064 → T065.

### Within Each User Story

- Tests first, and they must fail.
- The shared files grow in order: US1 → US2 → US3 for `content_controller.dart`, and US2 → US3 for
  `pack_store.dart` and `content_updater.dart`.
- Run build_runner after every provider change.

### Parallel Opportunities

- **Foundational:** T004, T006, T009, T010, T011, T012, T013, T014 and T018 touch different files.
- **US1:** every test, T019–T023, and then T027.
- **US2:** every test, T028–T034, then T035, T036 and T042.
- **US3:** every test, T043–T046.
- **US4:** T050–T052, then T054 and T056. US4 as a whole can run in parallel with US2 and US3.
- **Polish:** T058–T061.

---

## Parallel Example: User Story 2

```text
# All US2 tests at once (different files):
T028 test/core/network/api_environment_test.dart
T029 test/core/network/dio_content_remote_test.dart
T030 test/core/content/pack_store_test.dart
T031 test/core/content/content_controller_stored_test.dart
T032 test/core/content/content_updater_test.dart
T033 test/core/content/home_arrival_test.dart
T034 test/repo/cleartext_config_test.dart

# Then the independent pieces:
T035 lib/core/network/api_environment.dart
T036 lib/core/platform/connectivity.dart
T042 android/app/src/{main,dev}/…
```

## Parallel Example: Foundational

```text
T004 packages/content_models/test/strict_json_test.dart
T006 tools/content_kit/tests/test_bundle.py (dev mode)
T009 lib/core/content/refusal_reason.dart
T013 test/repo/domain_imports_test.dart
T014 test/core/content/client_version_test.dart
T018 lib/core/platform/app_info.dart
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 and Phase 2.
2. Phase 3 (US1): the app loads, verifies and serves the bundled pack.
3. **Stop and validate**: quickstart scenario 2, and the delivery plan's "the app loads the
   bundled pack and verifies its sha256". M02 could start from here.

### Incremental Delivery

1. US1: content offline, the MVP.
2. US2: updates from the manifest, checked against the local stack (scenario 3).
3. US3: resilience. Ship US2 and US3 together: US2 without US3 is unsafe for players.
4. US4: the release bundle and build guards. It is needed before the first staging or prod build.
5. Polish, review, then merge as one PR.

### Notes

- **[P]** tasks are in different files with no dependencies on incomplete tasks.
- Never edit a generated file. The bundled assets come only from `wassal-content bundle`, and
  `codegen` owns `packages/content_models/lib/src/generated/`.
- Never stash, reset or discard to get past a failing hook. Ask the owner.
- Commit after each task or logical group, with Conventional Commits.
