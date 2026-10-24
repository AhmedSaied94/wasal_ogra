# Research: App Shell (M03)

Phase 0 output. Researched 2026-10-18 against pub.dev, GitHub releases, official Android and Flutter
docs, and the Flutter 3.47.7 source. Items marked **[tested]** were confirmed with throwaway projects on
the local Flutter 3.47.7. Every Technical Context unknown is resolved below. The open questions this
feature owns, mobile §24.1 and §24.2, are closed in R1 and R14.

## R1 Minimum platform versions (resolves mobile §24.1)

- **Decision:**
  - Android: `minSdk 24` (Android 7.0), with `targetSdk 36` and `compileSdk 36`.
  - iOS: deployment target 15.0, set in every build configuration of the Xcode project. It is declared
    now, but iOS builds wait for phase 3.
  - *Since 2026-10-24 (PR #14):* there is no Podfile. Every iOS plugin is a Swift Package, so Flutter
    builds iOS without CocoaPods. iOS builds run on Codemagic (`codemagic.yaml`). Until phase 3 the
    only build is the unsigned dev IPA ([runbook](../../docs/runbooks/ios-test-build.md)).
- **Rationale:** the floor comes from the toolchain and the MVP dependencies, not from a product choice.
  Nothing allows lower, and nothing requires higher.

  | Sets the floor | Android | iOS |
  | --- | --- | --- |
  | Flutter 3.47.7 itself | 24 (API 21–23 dropped in 3.35) | 15.0 (raised in 3.47 for Xcode 27) |
  | FlutterFire (Android BoM 35.0.0, iOS SDK 12.19) | 24 | 15.0 |
  | google_mobile_ads 9.1.0 (Ads SDK 25.4) | 24 | 13.0 |
  | google_sign_in_android, flutter_secure_storage 11.2, flutter_local_notifications 22.3, shared_preferences 2.5.6, sign_in_with_apple 8.2, sqlite3 3.7 (drift) | 24 | ≤ 13.0 |
  | in_app_purchase_android 0.5.4 (Play Billing 8.0), rive 0.14 / rive_native, share_plus, flame, audioplayers | ≤ 24 | ≤ 13.0 |

  Google Play has required `targetSdk 36` for new apps and updates since 2026-08-31. Flutter 3.47
  already defaults to 36.
- **Consequence:** apps targeting 36 get predictive back on Android 16+: `onBackPressed` is no longer
  called. All back handling goes through `PopScope` and go_router (R7).
- **Alternatives rejected:** API 21/23 (Flutter itself no longer supports them); API 26+ (needlessly cuts
  older Egyptian devices).
- **Docs to update in this PR:** mobile §2 (Target platform row) and §24.1 (FR-038).
- **Follow-up for later features:** drop `sqlite3_flutter_libs`, which is end-of-life. drift's sqlite3
  3.x uses native-assets hooks (affects M05).

## R2 Dependencies and versions (M03 only)

| Package | Version | Role |
| --- | --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5 | Pinned in `.fvmrc` |
| `material_ui` | ^1.7.0 | Material widgets (R3) |
| `flutter_riverpod` | ^3.4.3 | State and dependency injection |
| `riverpod_annotation` | ^4.0.7 | `@riverpod` |
| `riverpod_generator` (dev) | ^4.0.9 | Codegen through `build_runner` |
| `riverpod_lint` (analyzer plugin) | ^3.1.9 | `plugins:` in `analysis_options.yaml`; no `custom_lint` |
| `go_router` | ^18.1.0 | Routing (needs Flutter ≥ 3.44) |
| `flutter_localizations` (sdk) + `intl` | sdk + ^0.20.3 | gen-l10n only. Number display does **not** use `intl` (R9). |
| `shared_preferences` | ^2.5.6 | `SharedPreferencesWithCache` (R11) |
| `flutter_native_splash` (dev) | ^2.4.8 | Generates the launch screens (R13) |
| `build_runner`, `flutter_lints` (dev) | current major at implementation | Codegen and the lint baseline |

**Not adopted:**

- `alchemist`: its CI goldens draw text as blocks, which defeats the point of Arabic glyph goldens.
- `golden_toolkit`: discontinued.
- `very_good_coverage`: archived.
- `freezed`, `dio`, `drift`: nothing in M03 needs them.

**Riverpod 3 notes that shape the code:**

- `@riverpod` providers are auto-dispose by default. App-lifetime state (digit style, config, settings
  store) uses `@Riverpod(keepAlive: true)`.
- Failed providers retry automatically. The app root sets `ProviderScope(retry: (_, __) => null)`, so a
  startup failure surfaces instead of looping.
- Listeners under `TickerMode(enabled: false)` pause, and that includes hidden tabs in an
  `indexedStack`. The bottom bar, which watches the «new» dot, is always visible, so this is safe.
- Tests use `ProviderContainer.test(overrides:)` and `ProviderScope(overrides:)`.

## R3 The Material split (`material_ui`)

- **Decision:** depend on `material_ui` 1.7.0 and import it everywhere instead of
  `package:flutter/material.dart`. Run `dart fix --apply --code=migrate_design_widgets` if anything
  slips through.
- **Rationale:**
  - Flutter 3.47 publishes Material as the separate `material_ui` package; the in-SDK copy is frozen
    and due for deprecation.
  - go_router 18 already depends on `material_ui`. Mixing the two Material libraries would put two
    separate `Theme` and `Page` type hierarchies in one app.
- **Risk:**
  - The combination of gen-l10n delegates and `material_ui` is untested. The generated code references
    the in-SDK `flutter_localizations`. Plan: pass
    `[AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates]` taken from `material_ui`.
  - The first implementation task is a short spike to confirm this builds and renders RTL. If it
    doesn't, record the workaround here before continuing.
- **Spike outcome (T009, 2026-10-18):** it works with no workaround.
  - `material_ui` 1.7.0, go_router 18.1.0 and gen-l10n analyze clean with the delegates above.
  - The app renders Arabic RTL on an en_US test locale. The spike's throwaway test became the permanent
    `test/bootstrap/app_test.dart` (T012), so there was nothing to delete.
  - `fvm flutter build apk --flavor dev --debug` succeeds. It needed one Gradle fix, unrelated to
    Material (see R15).
- **Alternative rejected:** the frozen in-SDK Material. It conflicts with go_router 18 and needs a
  migration later.

## R4 Routing design

- **Decision:** go_router 18 with a `rootNavigatorKey`, plus the following.
  - **Tabs:** `StatefulShellRoute.indexedStack` with four branches (home, lines, apartment, shop).
    Switching uses `navigationShell.goBranch(i, initialLocation: i == currentIndex)`, so tapping the
    selected tab returns that branch to its root.
  - **Pages and sheets:** every `page` and `sheet` destination sets
    `parentNavigatorKey: rootNavigatorKey`, which hides the bar (FR-015).
  - **Sheets:** a custom `SheetPage<T>` whose `createRoute` returns
    `ModalBottomSheetRoute(settings: this, isScrollControlled: true, isDismissible: true, enableDrag: true, …)`.
    go_router has no built-in sheet page.
  - **Other pages:** `StickerPage` (a `CustomTransitionPage`): a fade-through of `motion.screen`, which
    is a plain `fast` fade when `MediaQuery.disableAnimationsOf` is true (FR-023).
  - **Unknown routes:** `onException: (_, __, router) => router.go('/home')`. It is the only error hook
    set; go_router asserts if more than one is set. Invalid parameters are rejected by per-route
    `redirect`s built from the validators in contracts/routes.md (FR-022).
  - **Duplicate pushes (FR-024):** go_router's `push` always adds an entry, which we confirmed in its
    source. A `NavGuard` helper drops a request when the target equals the current location, or while a
    push Future is still pending.
- **Alternatives rejected:**
  - `ShellRoute`, because it doesn't keep per-tab state.
  - Imperative `showModalBottomSheet`, because sheets would have no URL or name, and later features and
    tests couldn't link to them.
  - Auto_route, which isn't in the locked stack.

## R5 CI pipeline

- **Decision:** one workflow, `.github/workflows/mobile.yml`, as specified in contracts/ci-checks.md,
  with:
  - `actions/checkout@v7`
  - `subosito/flutter-action@v2` (≥ 2.23, `flutter-version-file: .fvmrc`, `cache: true`,
    `pub-cache: true`)
  - `actions/setup-java@v6` (Temurin 17; AGP 9.1.0 and Gradle 9.3.1 need Java ≥ 17)
  - `actions/upload-artifact@v7`
- **Paths:**
  - A `changes` job decides with `git diff`, so required checks never hang as "pending" on PRs that
    don't touch mobile code.
  - FVM 4.3.2 finds the root `.fvmrc` from `apps/mobile` because it searches parent directories, so the
    whole monorepo shares one pin.
- **Coverage gate:** `tool/check_coverage.dart`, a small, tested Dart script with no dependencies.
  - It parses `lcov.info`, drops excluded globs, adds every unreported `lib/` file at 0%, and fails
    below 80%.
  - `very_good_coverage` is archived (last release 2024), and its successor, `very_good_workflows`, is
    a full reusable job that takes away control over the steps.
- **Alternatives rejected:**
  - `kuhnroyal/flutter-fvm-config-action`: no longer needed.
  - A pinned Flutter container: the cirruslabs images stopped at 3.44.0 on 2026-05-01.

## R6 Golden tests and fonts

- **Decision:** plain `matchesGoldenFile`, set up in `test/flutter_test_config.dart`:
  - load every font in `FontManifest.json` through `FontLoader` (Lalezar, Baloo Bhaijaan 2 and Material
    Icons), so goldens show real Arabic glyphs instead of Ahem boxes;
  - install a tolerant `LocalFileComparator` subclass that accepts ≤ 0.1% differing pixels.
- **Surfaces:**
  - Frames are set with `tester.view.physicalSize` and `devicePixelRatio`, then reset in `addTearDown`.
  - The text scale is set as the device setting (`tester.platformDispatcher.textScaleFactorTestValue`),
    so it passes through the production clamp in `MaterialApp.builder`.
  - **Deviation from T017 (2026-10-18):** goldens render at device pixel ratio 1, not 3. Layout depends
    only on logical size, and dpr 1 keeps each PNG around 15 KB instead of about 9× that, across a
    matrix of more than 100 images. Glyph shaping and RTL order are still visible at this size.
- **Matrix:** 390×844 and 360×640, Arabic-Indic and Western digits, text scale 1.0 and 1.3. Every shell
  screen is covered, plus each tab with the «new» dot on and off.
- **Platform drift:**
  - The test runner uses only fonts in Flutter's own cache, never system fonts.
  - Remaining risk is sub-pixel differences between machines, which the threshold absorbs.
  - If the first CI run still disagrees, regenerate with the `update-goldens` dispatch job; CI becomes
    the reference.
- **Variable font:** since Flutter 3.41, `FontWeight` drives the `wght` axis of Baloo Bhaijaan 2
  automatically. `TypeTokens` also sets `FontVariation('wght', …)` explicitly, so the weight holds on
  every renderer.

## R7 Back handling under predictive back

- **Decision:**
  - **Shell:** one `PopScope(canPop: false, onPopInvokedWithResult: …)` around the shell scaffold.
    go_router's `popRoute` tries the active branch navigator first and then the root, so this callback
    sees back only when the current branch is at its root.
    - On a non-home tab → `goBranch(0)`.
    - On home, first press → show the snackbar (ARB `pressBackAgainToExit`) and remember the time.
    - On home, a second press within 2 s → `SystemNavigator.pop()`.
    - Every callback starts with `if (didPop) return;`.
  - **Trip route:** `PopScope(canPop: false)`. The callback pushes the `tripPause` overlay; back on the
    overlay pops it.
  - **Sheets and other pages:** the default pop, plus a top-right back control that calls `context.pop()`.
- **Consequence (accepted by the owner):** with `canPop: false`, Android doesn't play the predictive
  "back to home" animation on الموقف.
- **Known caveat:** Flutter refreshes its "framework handles back" flag only when history changes. After
  a tab switch, a stale flag could make back exit without the animation. A widget test covers our side.
  The device check is quickstart scenario 6.
- **Alternative rejected:** letting `canPop` go true for the 2 s window so Android handles the second
  press. It is nicer visually, but it depends on that flag being fresh, which is less deterministic.

## R8 Localization and RTL

- **Decision:**
  - Use gen-l10n with `l10n.yaml`: `arb-dir: lib/l10n`, `template-arb-file: app_ar.arb`,
    `output-dir: lib/l10n/generated`, `nullable-getter: false`, and `generate: true` in the pubspec.
    The synthetic `flutter_gen` package was removed in 3.32.
  - Force `locale: Locale('ar')` with `supportedLocales: [Locale('ar')]`. **[tested]** This gives Arabic
    and RTL on an en_US device.
  - The ARB file is `app_ar.arb`, written in Egyptian Arabic. An `app_ar_EG.arb` can't exist without an
    `app_ar.arb` fallback anyway.
- **Generated code:** neither committed nor formatted by hand. It is regenerated by `flutter pub get`,
  gitignored, and excluded from coverage and from the Arabic-literal check.
- **Directional icons:** come from `Icons.arrow_back` and similar icons, which mirror under RTL. Nothing
  is hard-coded left or right.

## R9 Number formatting and bidi

- **Decision:** a custom pure-Dart `NumberFormatter` (contracts/number-format.md), not `intl`.
- **Why not `intl`** **[tested]**:
  - `ar_EG` emits Arabic-Indic digits and ٫/٬, but its minus is ALM + hyphen, not U+2212.
  - Plain `ar` emits Western digits with an LRM hyphen.
  - `ar_SA` and `ar_AE` fall back to `ar` (Western digits), which matters for the Gulf launch.
  - The digit style is a player setting that has to work the same in every region, so it can't depend
    on locale data.
- **Bidi** **[tested]**:
  - Without marks, "−1" inside Arabic renders as "1−".
  - An LRM fixes a lone number but breaks "−1 / 5".
  - Wrapping each formatted value in LRI…PDI (`Unicode.LRI` / `Unicode.PDI` from
    `package:flutter/foundation.dart`) renders correctly in SkParagraph. The marks take zero width.
  - Impeller doesn't change layout.

## R10 Text scaling

- **Decision:** `MaterialApp.router(builder: (c, child) => MediaQuery.withClampedTextScaling(minScaleFactor: 1.0, maxScaleFactor: 1.3, child: child!))`.
- **Rationale:** `TextScaler.clamp` keeps Android 14+ nonlinear scaling inside the range, and the 12 pt
  minimum holds because the lower bound is 1.0.

## R11 Device preference storage (owner decision 2026-10-18)

- **Decision:** a `SettingsStore` interface with a `SharedPreferencesWithCache` implementation.
  - `allowList: {'pref.digit_style'}`.
  - It is created during startup, so reads are synchronous after boot.
  - On Android, `shared_preferences` 2.5.6 stores data in DataStore.
- **Tests:** `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(...)`
  from `shared_preferences_platform_interface`, or a fake `SettingsStore`.
- **Scope rule:** device UI preferences only (digit style now; sound and haptics toggles in M14). Never
  tokens (`flutter_secure_storage`) and never game state (drift, M05).
- **Alternative rejected:** drift now (owner chose against it); the legacy `SharedPreferences` API,
  which is being deprecated.

## R12 Tunables loading

- **Decision:** `assets/config/tunables.json` holds every default.
  - It is loaded once by a keep-alive startup provider before `/boot` hands over to `/home`.
  - `assets/config/tunables.dev.json` is a flavor-conditional asset (`flavors: [dev]`, supported since
    Flutter 3.19, still in 3.47.7).
  - The loader treats a missing dev asset as `{}`. Flavored assets are omitted when no `--flavor` is
    given, which includes plain `flutter test`, so tests don't need `--flavor`.
  - Typed parsing uses `Tunable<T>.parse(Object?)`, which returns null when the type is wrong, so the
    next source wins.
- **Rationale:** values live in data, not code (constitution VIII). The flat JSON is the shape that
  Remote Config `setDefaults` takes in M15, and that B10 can seed `LiveSetting` from.
- **Alternatives rejected:**
  - Dart const maps: these are magic constants in code.
  - `--dart-define` overrides: they aren't visible in the bundle, and are easy to leave on by accident.

## R13 Launch without a white frame, and the fully-drawn report

- **Decision:**
  - `flutter_native_splash` 2.4.8, configured as `color: "#FFD23F"` and
    `android_12: { color: "#FFD23F", icon_background_color: "#FFD23F", image: <placeholder icon> }`,
    plus the same config per flavor.
  - **White-frame fix:** the package edits only `LaunchTheme`, and Flutter's template `NormalTheme`
    keeps a white `windowBackground` until the first frame. The fix is to set `NormalTheme`'s
    `windowBackground` to `@color/shams` in `values`, `values-night`, `values-v31` and
    `values-night-v31`.
  - The boot screen paints شمس from its first frame.
  - **Fully drawn:** `MainActivity` (a `FlutterActivity`, which extends `android.app.Activity`)
    registers a `MethodChannel('wassal/launch')` in `configureFlutterEngine`. The channel calls
    `reportFullyDrawn()`. On the Dart side, `LaunchMetrics.reportFullyDrawnOnce()` runs from الموقف's
    first post-frame callback, once per process.
- **Placeholder icon:** a plain شمس-and-ink placeholder launcher icon. The real art isn't part of M03.

## R14 Reference device and cold-start method (resolves mobile §24.2; owner decision 2026-10-18)

- **Decision:** Samsung Galaxy A06 (4 GB RAM, Helio G85).
  - Measure the `prod` variant in release mode with `adb shell am start -S -W`, 10 runs, timed to the
    "Fully drawn" logcat line. Pass is a median ≤ 3.0 s.
  - No white frame: a launch screen recording, checked frame by frame with ffmpeg (luma ≥ 245 on more
    than 50% of a frame fails).
  - An optional 3 GB Unisoc phone is checked once per release, as information only, not a gate.
  - The scripts live in `apps/mobile/tool/perf/`.
- **Docs to update in this PR:**
  - mobile §2: "2–3 GB RAM class" becomes the named device;
  - mobile §19 and §24.2;
  - `docs/delivery-plan.md`: move §24.2 from step 5 to step 1 (FR-044).
- **Note for M02:** the 45 fps budget is now measured on the same A06.

## R15 Build variants

- **Decision:** Android `productFlavors` with dimension `env`, and namespace `com.wassalogra.app`.

  | Variant | Application ID | App name |
  | --- | --- | --- |
  | `dev` | `com.wassalogra.app.dev` | «وصّل dev» |
  | `staging` | `com.wassalogra.app.staging` | «وصّل staging» |
  | `prod` | `com.wassalogra.app` | «وصّل الأجرة» |

  - App names are Android string resources, not Dart.
  - One `main.dart` reads `appFlavor`. A missing or unknown flavor fails a startup assertion and a test.
  - iOS: the Xcode schemes `dev`, `staging` and `prod`, each with `Debug-`, `Release-` and
    `Profile-<flavor>` configurations, use the same bundle IDs and app names (`APP_DISPLAY_NAME`).
    They were added on 2026-10-24 (PR #14).
- **Application ID:** chosen by the owner on 2026-10-18. It is permanent once uploaded to Play.
- **AGP 9:** `resValue` is off by default, so `build.gradle.kts` sets `buildFeatures { resValues = true }`.
  Without it, Gradle fails with "Product Flavor dev contains custom resource values, but the feature is
  disabled" (found during the T009 spike).

## R16 Decisions on low-impact spec gaps

- **Sheets:** they also close on a tap outside (`isDismissible: true`), in addition to a swipe or the
  close button. This is standard platform behavior; the spec's list was not exclusive.
- **Daily screens:** shown as full-screen pages for now. M13 may change how they are presented, but not
  their names or paths.
- **Bottom-bar icons:** Material Symbols placeholders until the art set exists. Icon choice is cosmetic
  and doesn't affect tests beyond the goldens.

## R17 Implementation notes (`/speckit-implement`, 2026-10-18)

Choices made while building, where the code differs from a task's wording or settles a detail the
plan left open.

- **Locations:** go_router's `currentConfiguration.uri` leaves out `push`ed routes, so `NavGuard` and
  the tests read the top route's location from `GoRouter.state.uri`.
- **Duplicate-navigation guard (FR-024):** `push` returns a Future that completes when the pushed
  route is popped, so "while a push is pending" can't mean that Future. `NavGuard` drops a request
  when the target is the current location, when another request hasn't been drawn yet (cleared after
  the next frame), or when the caller's page is no longer on top in every enclosing navigator. The
  last rule covers taps on a page that is leaving or covered.
- **Link actions:** a link to a tab, or from a root page to a tab's sheet (result → pre-trip), uses
  `go`, so the tab shows beneath. Hand-offs that back shouldn't return to use `pushReplacement`: the
  pre-trip sheet → trip, and trip → result. Every other link uses `push`.
- **Route nesting:** a tab's sheets, plus `/apartment/chapters`, nest under the tab's route with
  `parentNavigatorKey: root`, so the tab shows beneath them and back returns to it. `/trip/:tripId`
  and `/trip/:tripId/result` are separate top-level routes, so the result never stacks on the trip.
- **«New» dot clearing (FR-016a):** the shell is sometimes rebuilt from scratch on a branch change,
  so clearing on an index change was unreliable. Instead, the open tab never keeps its dot: whenever
  the shell builds with a dot on the current tab, it clears it after the frame. A dot set on الموقف
  at launch therefore clears at once. That's intended, since the player is already there.
- **The dot's screen-reader label** joins its tab cell's label («جديد» plus the tab name) instead
  of being a separate node, so the tab is announced as new.
- **Arabic-literal guard (FR-042):** the scan skips comments, using a small Dart lexer in
  `test/helpers/dart_source.dart`. FR-042 is about player-visible text, and comments use domain terms
  such as الموقف. Strings, including raw and triple-quoted ones, are still scanned. The integer-money
  scan uses the same lexer.
- **Coverage gate:** the Dart VM leaves files with no code to run (constants, abstract interfaces)
  out of `lcov.info`. The gate counts a missing file as untested only if it has a function body.
  Otherwise `typography.dart` and the interfaces would wrongly read 0%.
- **Sample numbers:** the placeholders' sample row is a single ARB message, `sampleNumbers`, with
  `String` placeholders filled by `NumberFormatter`.
- **Startup:** `appStartupProvider` opens the `SettingsStore` and loads the tunable layers in
  parallel. A failure shows the boot screen's retry. Retry (`retryAppStartup`) resets both steps as
  well as `appStartup`, because each keep-alive step caches its own error. Until startup completes,
  a router redirect sends every location except `/boot` to `/boot`, because screens read those
  providers synchronously.
- **Saving the digit style:** if the write fails, the choice still applies until the app restarts,
  and the failure goes to `FlutterError.reportError` instead of being dropped.
- **Page transitions:** they use `animation.drive(...)`, which registers no listeners of its own,
  and read the reduce-motion setting on every build.
- **Dev tunables:** a dev-only asset is not in the bundle under `flutter test` (no flavor). Startup
  checks the asset manifest instead of catching a load error, and the test reads the file from disk.

## Handed to later features (not blocking M03)

- **`trip_hints_enabled_line_gamaa` (M01/M02):** the ux-spec's "first time per passenger type" mode
  needs an enum, not a boolean (contracts/tunables.md). If the key changes, update mobile §14.3 and the
  backend in the same change.
- **drift (M05):** use the native-assets `sqlite3` 3.x, not the end-of-life `sqlite3_flutter_libs`.
