# Implementation Plan: Content Pack Loader (M04)

**Branch**: `006-m04-content-loader` | **Date**: 2026-10-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/006-m04-content-loader/spec.md`

## Summary

M04 gives the app its content. It covers:

- **The bundled pack.** Every build carries one pack file and a record of its version, size and
  sha256. The app checks the bytes before it decompresses them, decodes off the UI isolate, refuses
  any non-integer number the generated models would otherwise truncate, and checks the pack's
  identity (research R3, R4, R6).
- **One content source.** A read-only `ContentSource` over the generated models serves every later
  feature. It lives behind a pure-Dart interface and switches as a whole (R8).
- **Updates without a release.** The app checks `GET /v1/content/manifest` at launch, on resume and
  when the connection returns, at most every 15 minutes. It downloads only from the manifest's URL,
  within production's own caps, and verifies before reading. It switches only at launch or on
  arrival at Home (R7, R9, R10).
- **Resilience.** Atomic files in the app's private directory, launch-time re-verification, and a
  fallback to the bundled pack. An unusable version is never downloaded again, until an app update.
  Every kill point is tested (R5, R14).
- **Builds that ship a pack their server knows.**
  - Dev bundles the sample as version 1.
  - Staging and prod bundle the newest `content/source/` pack, checked against production's release
    record.
  - A new `wassal-content bundle` command writes the files, and CI, a Gradle check and a guard test
    refuse a wrong one (R13).
- **The app becomes `1.0.0`**, so the manifest offers it packs (R2). Dev builds may use plain HTTP
  to the local stack, which constitution 1.2.0 allows for the dev flavor only (R12).

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**:

- Dart 3.13.5 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`).
- Python 3.13 (uv) for the `wassal-content bundle` command in `tools/content_kit`.

**Primary Dependencies**:

- **App.**
  - `content_models` (path), `dio ^5.11.1`, `crypto ^3.0.7`, `path_provider ^2.1.6`,
    `connectivity_plus ^7.3.2`, `package_info_plus ^10.2.2`, each plugin behind an app interface
    (R1).
  - Dev: `integration_test` (SDK).
  - Existing: Riverpod 3 with its generator, and go_router 18.
- **`content_models`.** No new dependency: `decodeContentJson` is hand-written over `dart:convert`.
- **`content_kit`.** No new dependency. The release record is fetched with `urllib` from the
  standard library.

**Storage**:

- On the device: `<app support>/content/` holds up to two `core-<v>.json.gz` files and
  `state.json`, written atomically (R5, data-model.md).
- In the repo: the bundled files under `apps/mobile/assets/content/{dev,release}/`.
- No database: M05 brings drift.

**Testing**:

- `flutter_test` unit and widget tests on real temp directories, with fake `ContentRemote`,
  `ConnectivitySource`, `AppInfo` and clock.
- `DioContentRemote` against a real local `HttpServer`.
- Kill-point tests, and repo guards for domain imports, cleartext config, the bundled pack and the
  app version.
- A CI perf budget, plus an on-device integration test for the A06.
- `package:test` for `decodeContentJson`, and pytest for `bundle`.
- Coverage ≥ 80% in the app, `content_models` and `content_kit` (R16, contracts/ci-checks.md).

**Target Platform**:

- Android, `minSdk 24` and `targetSdk 36`, for all three flavors.
- iOS is phase 3: nothing here is Android-only except the network security config.
- Linux for CI and `flutter test`.

**Project Type**: A mobile app feature in the `wassal` monorepo (`apps/mobile/lib/core/content/` and
`core/network/`), plus one helper in `packages/content_models` and one command in
`tools/content_kit`.

**Performance Goals**:

- An MVP-size pack is active in ≤ 500 ms on the Galaxy A06, and a 2 MiB-compressed pack in ≤ 1.5 s
  (SC-002, SC-003).
- Cold start to Home stays at a median ≤ 3 s.
- The CI runner's regression budgets are 300 ms and 1 s (R15).

**Constraints**:

- Offline-first: nothing blocks on the network (constitution V).
- Verify before reading (B04 hand-over).
- Caps: 64 KiB manifest, 16 MiB download, 32 MiB decompressed.
- No background work.
- HTTPS for staging and prod.
- No switch outside launch and arrival at Home.
- Integer-only content.

**Scale/Scope**:

- One pack (`core`). The MVP pack has about 50 trips, chapters 1 to 4 and about 25 speech pools.
  The pipeline warns above 2 MiB compressed.
- About 15 new `lib/` files, 1 helper in `content_models`, and 1 content-kit command.
- 3 Android files, CI steps, and 5 document updates.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How M04 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | Yes | No trip rule is read or written here. The engine still takes `TripDefinition` directly. `ContentSource` is a pure-Dart interface in `lib/core/content/domain/`, and a guard test forbids Flutter, plugin and `dart:io` imports there (R8). |
| II | Integer money | Yes | Catalog amounts are `int` in the generated models. `decodeContentJson` refuses every non-integer number before `fromJson` could truncate it (R3). The existing integer-money guard scans the new files. |
| III | Parity | No | No rule, scoring, parameter or PRNG change. The fixtures are untouched. |
| IV | Server authority | Partly | The loader handles no balances. Prices come only from the pack's catalog, and the active version is exposed so that ops can declare it and B03 can validate it (FR-010). |
| V | Offline-first | Yes | The bundled pack makes first launch work with no network. Manifest and download failures are silent and never block play. Updates have no screen to mark «محتاج نت» (spec Assumptions). |
| VI | Idempotency | No | Only `GET` requests. Re-downloading a version is harmless, and is bounded by attempts and the unusable list (R14). |
| VII | Content, not code | Yes | Content comes only from packs, read through the generated models. No app-side content type exists. URLs come only from the manifest. Prices come only from the catalog. No player-visible text is added. |
| VIII | Tunable numbers | No | No balancing number is added. The 15-minute interval, the 3-attempt limit and the caps are protocol limits, mirroring production's promotion caps (spec Assumptions). |
| IX | No ads in a trip | No | No ads. A download never interrupts a trip, and a switch can't happen during one. |
| X | RTL and Arabic first | No | No new screen. The boot screen and its goldens are M03's and unchanged (FR-040). |
| XI | Accessible minimums | No | No UI. |
| XII | No runtime LLM | No | — |
| XIII | Small, testable features | Yes | One spec folder. Tests cover every refusal, switch point, kill point, app-update case and build check, with real files and a real HTTP server. Coverage ≥ 80% in the app, `content_models` and `content_kit` (R16). |

**Locked stack.** Followed: Riverpod with its generator, go_router and dio. The new plugins
(`path_provider`, `connectivity_plus`, `package_info_plus`) are first-party or Flutter Community
packages, each behind an app interface (Architecture boundaries). No drift yet: that is M05's (R5).

**Security & privacy.**

- **HTTPS.** Staging and prod reach the manifest and packs only over HTTPS, enforced in the app and
  by Android's default config. Redirects are refused (R10).
- **Plain HTTP in dev.** Dev builds may use plain HTTP to `localhost`, `127.0.0.1` and `10.0.2.2`
  only. Constitution 1.2.0 (Security & privacy, amended 2026-10-21) allows exactly this, and
  requires the refusal in staging and prod plus the test that keeps it (R12, T034).
- **Untrusted bytes.** Nothing is decompressed before its size and sha256 match. Decompression is
  capped, decoding is strict, and the pack's identity is checked (R4).
- **No secrets, tokens or personal data.** Requests carry only the app version and platform.
- **Private storage.** Files live in the app's private directory, and records never hold URLs or
  content (R14).
- **Review.** The constitution's security-review list (auth, purchases, ledger, sync, webhooks,
  personal data) isn't touched. The PR still gets a security review, because it adds the app's
  first network client and its untrusted-input handling.

**CI gates (constitution).**

- Mobile: analyze, then unit, widget and golden tests. The app jobs now build `content_models`
  first.
- Content: schema validation, `codegen --check`, the golden, and the new `bundle --check`.
- Parity and the OpenAPI diff: unchanged. The manifest is consumed through the generated model,
  which B04 tests against the OpenAPI serializer.

**Gate result (pre-research): PASS.** No exceptions.

- **History.** Plain HTTP in dev builds was first recorded here as an exception the owner approved.
  `/speckit-analyze` (finding C1) noted that the exception had no time limit and no removal task,
  which Governance "Exceptions" requires.
- **Now.** The need is permanent, so the constitution was amended to 1.2.0 on 2026-10-21 to make it
  a rule for the dev flavor only.

**Gate result (post-design): PASS.** The re-check after Phase 1 found no new issue:

- the content source's interface imports only the generated models;
- every number on the content path is an integer, checked before construction;
- staging and prod accept only `https`;
- no screen, string or tunable is added;
- every bundled byte is pinned by sha256 to a file the content kit built, and for release to
  production's record.

## Project Structure

### Documentation (this feature)

```text
specs/006-m04-content-loader/
├── plan.md                    # This file
├── research.md                # Phase 0: decisions R1–R17, hand-overs
├── data-model.md              # Phase 1: bundled record, state.json, entry rules, lifecycle, launch choice
├── quickstart.md              # Phase 1: setup, scenarios 1–6, done when
├── contracts/
│   ├── content-source.md      # ContentSource interface, providers, rules for readers
│   ├── loading.md             # decodePackFile, decodeContentJson, PackStore, kill points, launch, reasons
│   ├── updates.md             # ContentRemote, requests, triggers, one check, the switch at Home
│   ├── bundling.md            # per-flavor assets, `wassal-content bundle`, refusals, publisher step
│   └── ci-checks.md           # mobile.yml and backend.yml changes, test inventory
├── checklists/requirements.md
└── tasks.md                   # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
apps/mobile/
├── pubspec.yaml                              # version 1.0.0+2; new deps; content asset dirs per flavor
├── assets/content/
│   ├── dev/                                  # NEW: core-1.json.gz, bundled.json (sample, v1)
│   └── release/README.md                     # NEW: replaced by the promoted pack's files (bundling.md)
├── lib/
│   ├── bootstrap/startup.dart                # waits for activeContentProvider; retry invalidates it
│   ├── bootstrap/app.dart                    # starts HomeArrival and the updater after startup
│   └── core/
│       ├── content/                          # NEW
│       │   ├── domain/content_source.dart    # the pure-Dart interface (content-source.md)
│       │   ├── pack_content_source.dart      # PackContentSource: indexes built once
│       │   ├── decode_pack_file.dart         # decodePackFile, ExpectedPack, PackDecodeResult
│       │   ├── refusal_reason.dart           # reason and detail codes (loading.md)
│       │   ├── bundled_pack.dart             # bundled.json + file from the asset bundle
│       │   ├── content_state.dart            # state.json model and codec (data-model.md)
│       │   ├── pack_store.dart               # files, atomic writes, reconcile, KillPoint hook
│       │   ├── content_controller.dart       # ActiveContent, launch choice, switchIfReady
│       │   ├── content_updater.dart          # triggers, throttle, one check
│       │   ├── content_remote.dart           # ContentRemote interface, results
│       │   ├── home_arrival.dart             # router listener → switchIfReady
│       │   └── content_providers.dart        # providers (content-source.md)
│       ├── network/                          # NEW
│       │   ├── api_environment.dart          # base URL per flavor, dev override, URL rules
│       │   ├── http_client.dart              # dio factory: headers, timeouts, no redirects
│       │   └── dio_content_remote.dart       # ContentRemote over dio, streaming caps
│       └── platform/
│           ├── app_info.dart                 # NEW: AppInfo over package_info_plus
│           └── connectivity.dart             # NEW: ConnectivitySource over connectivity_plus
├── android/app/
│   ├── build.gradle.kts                      # checkBundledPack before staging/prod preBuild
│   └── src/
│       ├── main/AndroidManifest.xml          # INTERNET permission
│       └── dev/                              # NEW: AndroidManifest.xml + res/xml/network_security_config.xml
├── test/
│   ├── core/content/                         # decoder, source, store, launch, kill points, updater,
│   │                                         #   home arrival, startup, perf budget
│   ├── core/network/                         # dio remote against a local HttpServer, environments
│   ├── repo/                                 # bundled_pack, domain_imports, cleartext_config guards
│   └── helpers/content.dart                  # sample ActiveContent, fakes, synthetic packs
├── integration_test/content_load_perf_test.dart   # NEW: A06 timing (owner)
└── test_driver/integration_test.dart              # NEW
packages/content_models/
├── lib/src/strict_json.dart                  # NEW: decodeContentJson, ContentJsonError
├── lib/content_models.dart                   # exports it
└── test/strict_json_test.dart                # NEW
tools/content_kit/
├── src/wassal_content/bundle.py              # NEW: dev, release, --check
├── src/wassal_content/cli.py                 # the bundle subcommand
└── tests/test_bundle.py                      # NEW
.github/workflows/mobile.yml                  # content_models build before the app's jobs
.github/workflows/backend.yml                 # bundle --check; apps/mobile/assets/content/ in the filter
docs/architecture-mobile.md                   # §5, §11, §14.1
docs/runbooks/content-publishing.md           # §3: the bundling step
docs/delivery-plan.md                         # B05 merged in #6; M04 progress; domain-switch line
docs/owner-actions.md                         # M04 section (at /speckit-implement)
CLAUDE.md                                     # bundle commands, content_models before the app, adb reverse
```

**Structure decision.**

- **Where the code goes.** `core/content/` and `core/network/` are the folders mobile §5 already
  names for "pack loader, manifest, cache" and "dio client". Only the reader-facing interface sits
  in `domain/`, so the purity guard has one small directory to watch.
- **Shared pieces.** The strict decoder goes in `content_models`, because what counts as valid
  content belongs with the models. The bundler goes in `content_kit`, because that is the only
  canonical pack builder.
- **No new package.** The loader is app infrastructure. Nothing outside the app needs it.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified

None. The one deviation found during planning, plain HTTP in dev builds, is now allowed by
constitution 1.2.0 (see "Gate result (pre-research)" above, and research R12).
