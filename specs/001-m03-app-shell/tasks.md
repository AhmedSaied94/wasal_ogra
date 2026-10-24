---

description: "Task list for M03 App Shell"
---

# Tasks: App Shell (M03)

**Input**: Design documents from `specs/001-m03-app-shell/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:
- Tests are **mandatory** (constitution XIII). Every story writes its tests first; they must fail
  before the implementation tasks start.
- Required coverage: ≥ 80% lines for the app.

**Organization**: Tasks are grouped by user story. Paths are from the repository root. The app lives
in `apps/mobile/`. Run every Flutter and Dart command through FVM (`fvm flutter …`, `fvm dart …`) from
`apps/mobile/` unless a task says otherwise.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US5 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Pin the toolchain, scaffold the Flutter app, set platform levels and dependencies, and
de-risk the `material_ui` combination.

- [X] T001 Create `.fvmrc` at the repository root containing exactly `{"flutter": "3.47.7"}` (a plain version, no `@stable`; CI parses it with `jq -r '.flutter'`), run `fvm install` at the root, and confirm `fvm flutter --version` prints 3.47.7 (FR-036)
- [X] T002 Scaffold the app from the repo root with `fvm flutter create --empty --org com.wassalogra --project-name wassal --platforms android,ios apps/mobile`, then:
  - in `apps/mobile/android/app/build.gradle.kts`, set `namespace = "com.wassalogra.app"` and `applicationId = "com.wassalogra.app"`;
  - move `MainActivity.kt` to `apps/mobile/android/app/src/main/kotlin/com/wassalogra/app/MainActivity.kt` with `package com.wassalogra.app`;
  - delete any generated sample test.
- [X] T003 Set the platform levels from research.md R1 in `apps/mobile/android/` and `apps/mobile/ios/`:
  - Android: `minSdk = 24`, `targetSdk = 36`, `compileSdk = 36` in `apps/mobile/android/app/build.gradle.kts`.
  - iOS: `IPHONEOS_DEPLOYMENT_TARGET = 15.0` for every build configuration in `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`, and `platform :ios, '15.0'` in `apps/mobile/ios/Podfile`. (PR #14 removed the Podfile on 2026-10-24: every iOS plugin is a Swift Package.)
  - Portrait only: `android:screenOrientation="portrait"` on the activity in `apps/mobile/android/app/src/main/AndroidManifest.xml`, and `UISupportedInterfaceOrientations` with portrait only in `apps/mobile/ios/Runner/Info.plist` (FR-004, FR-038).
- [X] T004 Configure `apps/mobile/pubspec.yaml`, then run `fvm flutter pub get`:
  - `environment: sdk: ^3.13.0, flutter: ">=3.47.7"`;
  - dependencies: `material_ui: ^1.7.0`, `flutter_riverpod: ^3.4.3`, `riverpod_annotation: ^4.0.7`, `go_router: ^18.1.0`, `flutter_localizations: {sdk: flutter}`, `intl: ^0.20.3`, `shared_preferences: ^2.5.6`;
  - dev_dependencies: `flutter_test: {sdk: flutter}`, `build_runner`, `riverpod_generator: ^4.0.9`, `flutter_lints`, `flutter_native_splash: ^2.4.8`, `shared_preferences_platform_interface: ^2.4.2`;
  - `flutter: generate: true, uses-material-design: true`;
  - a `fonts:` section with family `Lalezar` (`assets/fonts/Lalezar-Regular.ttf`) and family `BalooBhaijaan2` (`assets/fonts/BalooBhaijaan2-VariableFont_wght.ttf`).
- [X] T005 [P] Create `apps/mobile/analysis_options.yaml`:
  - `include: package:flutter_lints/flutter.yaml`;
  - `analyzer: language: {strict-casts: true, strict-inference: true, strict-raw-types: true}`, and exclude `lib/l10n/generated/**` and `**/*.g.dart`;
  - `plugins: riverpod_lint: ^3.1.9` (the analyzer-plugin form, not custom_lint; research R2).
- [X] T006 [P] Download the font files from the google/fonts GitHub repository into `apps/mobile/assets/fonts/`:
  - `ofl/lalezar/Lalezar-Regular.ttf` and its `OFL.txt` (saved as `OFL-Lalezar.txt`);
  - `ofl/baloobhaijaan2/BalooBhaijaan2[wght].ttf` (saved as `BalooBhaijaan2-VariableFont_wght.ttf`) and its `OFL.txt` (saved as `OFL-BalooBhaijaan2.txt`);
  - check that both fonts contain the Arabic-Indic digits U+0660–U+0669.
- [X] T007 [P] Append to the root `.gitignore` under the Dart/Flutter section: `apps/mobile/lib/l10n/generated/` and `**/*.g.dart` (generated code is not committed; plan.md)
- [X] T008 [P] Create `apps/mobile/l10n.yaml`, then create `apps/mobile/lib/l10n/app_ar.arb` containing only `"@@locale": "ar"` and `"appName": "وصّل الأجرة"`. The `l10n.yaml` keys:
  - `arb-dir: lib/l10n`
  - `template-arb-file: app_ar.arb`
  - `output-dir: lib/l10n/generated`
  - `output-localization-file: app_localizations.dart`
  - `nullable-getter: false`
- [X] T009 Spike (research R3) in `apps/mobile/lib/main.dart`:
  - Build a throwaway `MaterialApp.router` that imports only `material_ui`, uses a one-route go_router 18 config, and sets `locale: Locale('ar')` with delegates `[AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates]` taken from `material_ui`.
  - Prove it with `fvm flutter analyze` and `fvm flutter build apk --debug`, plus a temporary widget test asserting `Directionality.of(context) == TextDirection.rtl` on an en_US test locale.
  - Record the outcome, and any workaround, under R3 in `specs/001-m03-app-shell/research.md`.
  - Then delete the temporary test.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The app entry, flavors, forced Arabic RTL, the text-scale clamp, the startup provider, the
router skeleton, glossary ids and the test harness. Every story depends on these.

**⚠️ CRITICAL**: No user-story work begins until this phase is complete.

### Tests first

- [X] T010 [P] Write `apps/mobile/test/core/glossary/ids_test.dart` (glossary §3.6):
  - every enum value's `wireName` matches the glossary exactly: `LineId` = `line_hay, line_gamaa, line_souq, line_masyaf, line_safar`; `VehicleId` = `tuktuk, micro_old, micro_new, micro_safar`; `ChapterId` = `ch1_first_job, ch2_her_father, ch3_shabka, ch4_salon, ch5_kitchen, ch6_bedroom, ch7_wedding`; `RoomId` = `salon, kitchen, bedroom`;
  - `fromWire` returns null for unknown strings.
- [X] T011 [P] Write `apps/mobile/test/bootstrap/flavor_test.dart`: `Flavor.fromName` maps `dev`, `staging` and `prod`, and throws or asserts for a missing or unknown flavor (data-model BuildVariant).
- [X] T012 [P] Write `apps/mobile/test/bootstrap/app_test.dart`. Pump `WassalApp` and assert:
  - with the test platform locale set to `en_US`, `Localizations.localeOf` is `ar` and `Directionality.of` is `TextDirection.rtl` (FR-001);
  - with `platformBrightness` set to dark, the theme brightness stays light (FR-009);
  - with a device text scale of 2.0, the effective `MediaQuery.textScalerOf(context).scale(10)` is 13 (clamped to 1.3); with 0.8 it is 10 (clamped to 1.0) (FR-030);
  - an unknown path such as `/nope` lands on `/home` (FR-022).

### Implementation

- [X] T013 [P] Implement `apps/mobile/lib/core/glossary/ids.dart` with the enums `LineId`, `VehicleId`, `ChapterId` and `RoomId`. Each value has a `wireName` and a static `fromWire(String) → T?`. Add a header comment: replaced by B04-generated content models. Make T010 pass.
- [X] T014 [P] Implement `apps/mobile/lib/bootstrap/flavor.dart` (`enum Flavor {dev, staging, prod}`, with `Flavor.current` read from `appFlavor` in `package:flutter/services.dart`), then configure the Android flavors (FR-037, research R15):
  - In `apps/mobile/android/app/build.gradle.kts`, add `flavorDimensions += "env"` and three `productFlavors`:
    - `dev`: `applicationIdSuffix = ".dev"`, `resValue("string", "app_name", "وصّل dev")`;
    - `staging`: `applicationIdSuffix = ".staging"`, `resValue("string", "app_name", "وصّل staging")`;
    - `prod`: `resValue("string", "app_name", "وصّل الأجرة")`.
  - Set `android:label="@string/app_name"` in `apps/mobile/android/app/src/main/AndroidManifest.xml`.
  - Make T011 pass.
- [X] T015 Implement the entry point in `apps/mobile/lib/bootstrap/startup.dart`, `apps/mobile/lib/bootstrap/bootstrap.dart` and `apps/mobile/lib/main.dart`:
  - `apps/mobile/lib/bootstrap/startup.dart`: an `@Riverpod(keepAlive: true) Future<void> appStartup(Ref ref)` that is empty for now; US3 and US4 add their loading here.
  - `apps/mobile/lib/bootstrap/bootstrap.dart`: `WidgetsFlutterBinding.ensureInitialized()`, `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])`, then `runApp(ProviderScope(retry: (_, __) => null, child: const WassalApp()))`.
  - `apps/mobile/lib/main.dart`: replace the spike with a call to `bootstrap()`.
- [X] T016 Implement `apps/mobile/lib/bootstrap/app.dart` (`WassalApp`) and a minimal `apps/mobile/lib/core/routing/router.dart`, then make T012 pass:
  - `WassalApp` uses `MaterialApp.router` with `locale: Locale('ar')`, `supportedLocales: [Locale('ar')]`, the delegates confirmed in T009, `themeMode: ThemeMode.light` with no `darkTheme`, and `builder: (c, child) => MediaQuery.withClampedTextScaling(minScaleFactor: 1.0, maxScaleFactor: 1.3, child: child!)`.
  - The router is a `@Riverpod(keepAlive: true)` provider with a top-level `rootNavigatorKey`, `initialLocation: '/boot'`, `onException: (_, __, router) => router.go('/home')` as the only error hook, and stub routes `/boot` and `/home`.
  - Run `fvm dart run build_runner build -d`.
- [X] T017 Create the test harness in `apps/mobile/test/flutter_test_config.dart` and `apps/mobile/test/helpers/`:
  - `apps/mobile/test/flutter_test_config.dart`:
    - load every family in `FontManifest.json` with `FontLoader` (Lalezar, BalooBhaijaan2 and MaterialIcons);
    - install a `LocalFileComparator` subclass that passes when ≤ 0.1% of pixels differ (research R6).
  - `apps/mobile/test/helpers/surfaces.dart`:
    - `Surface.reference` (390×844 logical) and `Surface.small` (360×640), at dpr 1 (research R6 deviation);
    - `applySurface(tester, surface)`, which resets in `addTearDown`.
  - `apps/mobile/test/helpers/pump_app.dart`:
    - `pumpWassalApp(tester, {List overrides, String? initialLocation, double textScale = 1.0})`, which wraps `ProviderScope(overrides:)` and sets the device text scale through `tester.platformDispatcher.textScaleFactorTestValue`.

**Checkpoint**: `fvm flutter test` passes T010–T012. The app starts in Arabic RTL on `/boot` with any
device locale.

---

## Phase 3: User Story 1 - First open looks and reads like the game (Priority: P1) 🎯 MVP

**Goal**:
- Launch on شمس with no white frame, reaching الموقف inside the four-tab bottom bar.
- The «ستيكر الميكروباص» tokens and shared components, with automated palette and size checks.
- A fully-drawn report, plus the cold-start scripts.

**Independent Test**:
- Install a fresh `dev` build on a phone set to English. No white frame appears, الموقف shows in
  Arabic RTL with the bar الموقف، الخطوط، الشقة، المحل from right to left, and the colors, fonts,
  borders and shadows match contracts/design-tokens.md.
- Automated: T018–T025 pass.

### Tests for User Story 1 (write first, must fail)

- [X] T018 [P] [US1] Write `apps/mobile/test/core/theme/palette_test.dart`. It implements WCAG 2.1 relative luminance and CIE L\* (D65) inside the test file, and asserts every table in contracts/design-tokens.md (FR-010, FR-011):
  - `ColorTokens` hex values are exactly: shams #FFD23F, hibr #1D1A2B, waraq #FFFFFF, tablouh #2A2633, primary #1A4B8C, danger #F2542D, gold #F5B301, station1 #3B2A6B, station2 #0F766E, station3 #5FAE4E, station4 #A9DDF3, and `badgeNew == danger`;
  - ΔL\* ≥ 18 for every station pair and for primary–danger;
  - every listed text-on-fill pair reaches ≥ 4.5:1;
  - the «new» dot reaches ≥ 3:1 on tablouh, shams and waraq through its fill or its hibr outline;
  - every station hue is ≥ 30° from the danger hue;
  - station letters: waraq on station1 and station2, hibr on station3 and station4.
- [X] T019 [P] [US1] Write `apps/mobile/test/core/theme/tokens_test.dart`, asserting (FR-006, FR-007):
  - type scale: display 32, headline 24 and button 20 use family `Lalezar`; title 18/w700, body 15/w500, label 13/w600 and caption 12/w500 use `BalooBhaijaan2`; no style is below 12;
  - shape: borderCard 2.5, radiusCard 18, radiusControl 14, shadowCard 4, shadowPrimary 5, badgeSize 12, badgeOutline 2, minTouch 44;
  - motion: fast 150 ms, screen 250 ms, sheet 250 ms, every one < 333 ms;
  - space: 4, 8, 12, 16, 24, 32;
  - `Theme.of(context).extension<WassalTokens>()` is non-null.
- [X] T020 [P] [US1] Write `apps/mobile/test/core/theme/components_test.dart`:
  - `PrimaryButton`: primary fill, waraq text, hibr 2.5 border, radius 14, a hard shadow offset of 5 that falls bottom-left under RTL, min height 52, and the shadow drops to 0 when pressed;
  - `SecondaryButton`: waraq fill, hibr text;
  - `StickerCard`: waraq fill, 2.5 border, radius 18, shadow 4;
  - `WassalBottomBar`: tablouh fill; four cells in RTL order الموقف، الخطوط، الشقة، المحل (the first is rightmost); each cell ≥ 44×44; selected icon and label shams, unselected waraq; sits inside `SafeArea` bottom (FR-008, FR-014).
- [X] T021 [P] [US1] Write `apps/mobile/test/features/boot/boot_screen_test.dart` (FR-012, FR-012a):
  - the boot screen's first pumped frame has a shams background and shows `appName`;
  - after `appStartupProvider` completes, the location is `/home`;
  - with a mock handler on `MethodChannel('wassal/launch')`, `reportFullyDrawn` is invoked exactly once, after الموقف's first frame, even after switching tabs and back.
- [X] T022 [P] [US1] Write `apps/mobile/test/core/routing/shell_test.dart`:
  - a cold start lands on `/home` inside the shell, with the bottom bar visible and الموقف selected;
  - each of `/lines`, `/apartment` and `/shop` shows its placeholder title from ARB inside the shell (FR-013, FR-014).
- [X] T023 [P] [US1] Write `apps/mobile/test/a11y/minimum_sizes_test.dart`. For boot, `/home`, `/lines`, `/apartment` and `/shop`, at `Surface.reference` and `Surface.small`, and text scale 1.0 and 1.3, assert (FR-041, SC-004, constitution XI):
  - `meetsGuideline(iOSTapTargetGuideline)` (44×44);
  - `meetsGuideline(textContrastGuideline)`;
  - every `RenderParagraph`'s effective font size (style size × text scaler) is ≥ 12;
  - no overflow error is reported.
- [X] T024 [P] [US1] Write `apps/mobile/test/goldens/shell_goldens_test.dart`: `matchesGoldenFile` for boot, `/home`, `/lines`, `/apartment` and `/shop`, at both surfaces × text scale {1.0, 1.3}. Name each golden `goldens/<screen>_<surface>_<scale>.png` (FR-040).
- [X] T025 [P] [US1] Write `apps/mobile/test/repo/no_raw_style_values_test.dart`. It scans `apps/mobile/lib/**/*.dart`, excluding `lib/core/theme/tokens/` and `lib/l10n/generated/`, and fails on `Color(0x`, `Colors.` or `BorderRadius.circular(` followed by a numeric literal (FR-005, FR-006: no screen uses a non-token color or radius).

### Implementation for User Story 1

- [X] T026 [P] [US1] Implement `apps/mobile/lib/core/theme/tokens/colors.dart`:
  - `ColorTokens` with the exact hex values from T018, and `badgeNew` as an alias of `danger`;
  - `StationColor {fill, letter}` with `station1`/`station2` → letter `waraq` and `station3`/`station4` → letter `hibr`;
  - doc comment: station colors are assigned by stop order within a trip, max 4 drop-off stations.
- [X] T027 [P] [US1] Implement `apps/mobile/lib/core/theme/tokens/typography.dart` (`TypeTokens`) with the exact scale from T019. Families are `Lalezar` and `BalooBhaijaan2`; `FontWeight` drives the `wght` axis (research R6).
- [X] T028 [P] [US1] Implement `apps/mobile/lib/core/theme/tokens/shape.dart`, `apps/mobile/lib/core/theme/tokens/motion.dart` and `apps/mobile/lib/core/theme/tokens/space.dart` with the exact values from T019, plus a helper `hardShadowOffset(double n, TextDirection d)` that returns `Offset(d == rtl ? -n : n, n)`.
- [X] T029 [US1] Implement `apps/mobile/lib/core/theme/app_theme.dart`:
  - `WassalTokens extends ThemeExtension` holding all token groups;
  - `buildAppTheme()`, which returns a light `ThemeData` from `material_ui` with `scaffoldBackgroundColor: shams`, a color scheme mapped from the tokens, `fontFamily: 'BalooBhaijaan2'` and a text theme from `TypeTokens`;
  - use it in `apps/mobile/lib/bootstrap/app.dart`;
  - make T019 pass.
- [X] T030 [P] [US1] Implement `apps/mobile/lib/core/theme/components/primary_button.dart` and `apps/mobile/lib/core/theme/components/secondary_button.dart` per contracts/design-tokens.md «Shared components». When pressed, the shadow drops to 0 and the button shifts by the shadow offset.
- [X] T031 [P] [US1] Implement `apps/mobile/lib/core/theme/components/sticker_card.dart`: waraq fill, hibr `borderCard` border, `radiusCard`, `shadowCard` hard shadow with no blur.
- [X] T032 [US1] Add the US1 strings to `apps/mobile/lib/l10n/app_ar.arb`: `tabHome` «الموقف», `tabLines` «الخطوط», `tabApartment` «الشقة», `tabShop` «المحل», and the placeholder title keys `destHome`, `destLines`, `destApartment`, `destShop` (each with an `@` description). Run `fvm flutter pub get` to regenerate.
- [X] T033 [US1] Implement `apps/mobile/lib/core/theme/components/wassal_bottom_bar.dart`:
  - a tablouh bar with four equal cells; each whole cell is the tap target, ≥ 44×44;
  - each cell has a Material Symbols placeholder icon and a `label`-style text from ARB;
  - selected is shams, unselected is waraq;
  - wrapped in `SafeArea(top: false)`;
  - exposes `currentIndex` and `onTap`;
  - make T020 pass.
- [X] T034 [US1] Implement `apps/mobile/lib/core/routing/placeholder_screen.dart`: a `PlaceholderScreen` taking a destination title ARB key and a param map, and rendering a `StickerCard` with the title (in `headline` style) and the params. It uses only tokens and components.
- [X] T035 [US1] Implement `apps/mobile/lib/core/routing/shell_scaffold.dart` (a scaffold with `navigationShell` + `WassalBottomBar`, calling `goBranch`) and replace the `/home` stub in `apps/mobile/lib/core/routing/router.dart` with a `StatefulShellRoute.indexedStack`. It has four branches, `/home`, `/lines`, `/apartment` and `/shop`, each building a `PlaceholderScreen`. Make T022 pass.
- [X] T036 [US1] Implement `apps/mobile/lib/features/boot/boot_screen.dart`: a shams background from the first frame, `appName` in `display` style, a `ref.listen` on `appStartupProvider` that calls `context.go('/home')` on data, and an error state with a retry button. Wire it to `/boot` in `apps/mobile/lib/core/routing/router.dart`.
- [X] T037 [US1] Implement the fully-drawn report in `apps/mobile/lib/core/platform/launch_metrics.dart` and `MainActivity.kt` (FR-012a, research R13), then make T021 pass:
  - `apps/mobile/lib/core/platform/launch_metrics.dart`: `LaunchMetrics.reportFullyDrawnOnce()`, which uses `MethodChannel('wassal/launch')`, calls `reportFullyDrawn` once per process (static guard), and swallows `MissingPluginException`.
  - Call it from the الموقف placeholder's first `addPostFrameCallback`.
  - In `apps/mobile/android/app/src/main/kotlin/com/wassalogra/app/MainActivity.kt`, override `configureFlutterEngine` to register the channel; on `reportFullyDrawn` it calls `reportFullyDrawn()`.
- [X] T038 [US1] Create the placeholder launch art in `apps/mobile/assets/branding/` and the native splash in `apps/mobile/flutter_native_splash.yaml` (FR-012):
  - placeholder art: `apps/mobile/assets/branding/splash_icon.png` (288×288, an ink #1D1A2B rounded square on transparent) and `apps/mobile/assets/branding/app_icon.png` (1024×1024, ink square on #FFD23F);
  - `apps/mobile/flutter_native_splash.yaml`: `color: "#FFD23F"`, `image: assets/branding/splash_icon.png`, `android_12: {color: "#FFD23F", icon_background_color: "#FFD23F", image: assets/branding/splash_icon.png}`;
  - generate with `fvm dart run flutter_native_splash:create`.
- [X] T039 [US1] Fix the white frame between the splash and the first Flutter frame in `apps/mobile/android/app/src/main/res/` (research R13):
  - add `<color name="shams">#FFD23F</color>` in `apps/mobile/android/app/src/main/res/values/colors.xml`;
  - set `NormalTheme`'s `android:windowBackground` to `@color/shams` in `apps/mobile/android/app/src/main/res/values/styles.xml`, `values-night/styles.xml`, `values-v31/styles.xml` and `values-night-v31/styles.xml`, creating any missing files from the generated `LaunchTheme`.
- [X] T040 [P] [US1] Create the cold-start scripts in `apps/mobile/tool/perf/` per quickstart.md (SC-001, SC-001a):
  - `apps/mobile/tool/perf/cold_start.sh <package> <runs>`:
    - runs `adb shell am start -S -W -n <package>/com.wassalogra.app.MainActivity` `<runs>` times;
    - after each run, parses `Fully drawn <package>: +…ms` from `adb logcat -d`, clearing logcat before each run;
    - prints each run and the median;
    - exits 1 if the median is > 3000 ms.
  - `apps/mobile/tool/perf/check_white_frames.sh <video>`: uses ffmpeg to extract every frame, and exits 1 if any frame has > 50% of its pixels at luma ≥ 245.
  - Mark both scripts executable.
- [X] T041 [US1] Generate the US1 goldens in `apps/mobile/test/goldens/` on Linux with `fvm flutter test --update-goldens test/goldens`, inspect every PNG for correct Arabic glyphs and RTL order, then run `fvm flutter test` until T018–T025 all pass.

**Checkpoint**: US1 is complete. The app launches on شمس into الموقف with the bottom bar, every token
and palette check is green, and the goldens are committed.

---

## Phase 4: User Story 2 - Moving around the game (Priority: P2)

**Goal**:
- Every MVP destination from mobile §9 is reachable through placeholder links.
- Sheets, pages and the trip pause overlay.
- The back rules: top-right back, press twice on الموقف, trip back → pause.
- Parameter validation, the duplicate-navigation guard and the «new» dot.

**Independent Test**: starting from الموقف and tapping only placeholder links, reach every
destination in contracts/routes.md (except onboarding). The bar shows only on the four tabs, every
sheet closes in all three ways, and back returns to الموقف from everywhere. Automated: T042–T048 pass.

### Tests for User Story 2 (write first, must fail)

- [X] T042 [P] [US2] Write `apps/mobile/test/core/routing/param_validators_test.dart`, covering valid and invalid samples for each rule (contracts/routes.md):
  - `tripId` must match `^(line_[a-z]+)\.(\d{2})$`, with group 1 a known `LineId` (`line_hay.01` ok; `line_xyz.01`, `line_hay.1` and `hay.01` rejected);
  - `lineId` and `vehicleId` must be glossary values;
  - `itemId` must match `^(salon|kitchen|bedroom)\.[a-z0-9_]+$`;
  - `chapterId` must be a `ChapterId` wire name.
- [X] T043 [P] [US2] Write `apps/mobile/test/core/routing/route_table_test.dart` (FR-017):
  - the destination table contains exactly the names, paths, types (`tab`/`page`/`sheet`/`overlay`), sections and links listed in contracts/routes.md;
  - the four `tab`s are in the order home, lines, apartment, shop;
  - no path contains `garage`, `leagues`, `events` or `referral`.
- [X] T044 [P] [US2] Write `apps/mobile/test/core/routing/navigation_test.dart`:
  - **Links:** walking every link from `/home` per FR-017a reaches each destination (SC-006). The onboarding routes are opened directly.
  - **Bar:** visible only on the 4 tab roots; hidden on every page and sheet (FR-015).
  - **Sheets:** each closes by a drag down, by its close button and by a tap on the barrier (FR-018).
  - **Tab state:** scroll the الخطوط placeholder, switch to المحل and back, and the scroll offset is kept (FR-016). Tapping the selected tab returns its branch to the root.
  - **Bad routes:** `/trip/line_xyz.01`, `/lines/bad` and `/nope` land on `/home` (FR-022).
  - **Reduce motion:** with `MediaQuery.disableAnimations` true, page transitions use no slide transition (FR-023).
- [X] T045 [P] [US2] Write `apps/mobile/test/core/routing/back_behavior_test.dart`, simulating back with `tester.binding.handlePopRoute()` (FR-019 – FR-021):
  - a page pops;
  - with a sheet open, only the sheet closes;
  - on `/trip/line_hay.01`, the first back shows `tripPause` and the trip stays; a second back closes the pause; the pause's home action goes to `/home`;
  - the trip placeholder shows no top-right back control, and at both surfaces every tappable element on `/trip/line_hay.01` has its top edge at or below ⅔ of the screen height (constitution XI);
  - on `/shop`, back → `/home`;
  - on `/home`:
    - the first back shows the `pressBackAgainToExit` snackbar and does not exit;
    - a second back within 2 s calls `SystemNavigator.pop` (spy on `SystemChannels.platform`);
    - a press after 3 s counts as a first press again.
- [X] T046 [P] [US2] Write `apps/mobile/test/core/routing/nav_guard_test.dart` (FR-024):
  - two rapid taps on a link push exactly one route;
  - navigating to the current location is ignored;
  - a second request while a push is pending is ignored.
- [X] T047 [P] [US2] Write `apps/mobile/test/core/routing/new_dot_test.dart` (FR-016a):
  - every section's dot provider defaults to off;
  - an override to on shows `NewDot` (12 pt including a 2 pt hibr outline, badgeNew fill) at the tab icon's top-left under RTL, with the semantics label `newBadgeLabel` «جديد»;
  - a dot set to on (through `show()` or `overrideWithBuild`) disappears after the player opens that tab, and stays off after switching away and back.
- [X] T048 [P] [US2] Write `apps/mobile/test/goldens/navigation_goldens_test.dart`: goldens for a page placeholder (`/story/ch1_first_job`), a sheet placeholder (`/home/pre-trip/line_hay.01`), the `tripPause` overlay, and each of the 4 tabs with the «new» dot on and off. Use both surfaces × text scale {1.0, 1.3}.

### Implementation for User Story 2

- [X] T049 [P] [US2] Implement `apps/mobile/lib/core/routing/param_validators.dart` with the exact rules from T042, built on `apps/mobile/lib/core/glossary/ids.dart`. Make T042 pass.
- [X] T050 [P] [US2] Implement `apps/mobile/lib/core/routing/nav_guard.dart`. It drops a request when the target equals `GoRouter.of(context).state` location, or while an earlier `push` Future is pending. Make T046 pass.
- [X] T051 [P] [US2] Implement the two page types in `apps/mobile/lib/core/routing/sticker_page.dart` and `apps/mobile/lib/core/routing/sheet_page.dart`:
  - `apps/mobile/lib/core/routing/sticker_page.dart`: a `CustomTransitionPage` with a fade-through of `motion.screen`; when `MediaQuery.disableAnimationsOf` is true, it uses a plain fade of `motion.fast`.
  - `apps/mobile/lib/core/routing/sheet_page.dart`: a `SheetPage<T> extends Page<T>` whose `createRoute` returns `ModalBottomSheetRoute(settings: this, isScrollControlled: true, isDismissible: true, enableDrag: true, …)`, with top corners `radiusCard` and a hibr `borderCard` top border.
- [X] T052 [P] [US2] Implement the «new» dot in `apps/mobile/lib/core/theme/components/new_dot.dart` and `apps/mobile/lib/core/routing/new_dot_providers.dart`:
  - `apps/mobile/lib/core/theme/components/new_dot.dart`: `NewDot` — badgeNew fill, a 2 pt hibr outline, 12 pt total, and `Semantics(label: newBadgeLabel)`.
  - `apps/mobile/lib/core/routing/new_dot_providers.dart`: a keep-alive `Notifier<bool>` provider family keyed by section, defaulting to `false`, with `show()` (for owning features) and `clear()`.
- [X] T053 [US2] Implement `apps/mobile/lib/core/routing/routes.dart`, the full `Destination` table from data-model.md and contracts/routes.md. Each entry has `name`, `path`, `presentation`, `section`, param validators, `links` and `titleKey`, plus the sample params `tripId=line_hay.01`, `lineId=line_hay`, `vehicleId=micro_old`, `itemId=salon.nish` and `chapterId=ch1_first_job`. Make T043 pass.
- [X] T054 [US2] Register every destination in `apps/mobile/lib/core/routing/router.dart`:
  - tabs stay in the shell;
  - every `page` and `sheet` uses `parentNavigatorKey: rootNavigatorKey` with `StickerPage` or `SheetPage`;
  - per-route `redirect`s use the validators and send invalid params to `/home`;
  - `lineDetail` (`/lines/:lineId`) and `vehiclePurchase` (`/lines/vehicle/:vehicleId`) are declared with `vehicle/:vehicleId` before `:lineId`.
- [X] T055 [US2] Extend `apps/mobile/lib/core/routing/placeholder_screen.dart`:
  - onward links render as `SecondaryButton`s that navigate through `NavGuard` (FR-017a);
  - non-tab pages get a header with an auto-mirrored back control at the top right that calls `context.pop()` (FR-019), **except the trip**, which has no top-right control (constitution XI);
  - sheets get a close button.
- [X] T056 [US2] Implement `apps/mobile/lib/core/routing/trip_pause_overlay.dart`, a dialog-style route on the root navigator with a resume action (pop) and a home action (`go('/home')`). Wrap the trip placeholder in `PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { if (didPop) return; /* push pause */ })` in `apps/mobile/lib/core/routing/router.dart` (FR-020). The trip placeholder lays out its title and its onward link to `result` in the bottom third of the screen (constitution XI).
- [X] T057 [US2] Implement `apps/mobile/lib/core/routing/back_to_exit.dart` and wrap the shell in `apps/mobile/lib/core/routing/shell_scaffold.dart` with `PopScope(canPop: false)` (FR-021, research R7):
  - on a non-home branch root → `goBranch(0)`;
  - on الموقف:
    - the first press shows a `SnackBar` with `pressBackAgainToExit` and stores the time;
    - a second press within `Duration(seconds: 2)` calls `SystemNavigator.pop()`;
    - otherwise it counts as a new first press.
  - Make T045 pass.
- [X] T058 [US2] Integrate `NewDot` into `apps/mobile/lib/core/theme/components/wassal_bottom_bar.dart`. Place it at the icon's top-end (top-left in RTL), watching `newDotProvider(section)`, and call `clear()` for that section when the player opens the tab. Make T047 pass.
- [X] T059 [US2] Add the US2 strings to `apps/mobile/lib/l10n/app_ar.arb`:
  - a `dest*` title for every destination in contracts/routes.md;
  - link labels;
  - `backLabel`, `closeLabel`, `pressBackAgainToExit`, `pauseTitle`, `pauseResume`, `pauseHome`;
  - `newBadgeLabel` «جديد».
  - Make T044 pass.
- [X] T060 [US2] Extend `apps/mobile/test/a11y/minimum_sizes_test.dart` with every US2 page, sheet and the pause overlay. Generate the US2 goldens with `fvm flutter test --update-goldens test/goldens`, inspect them, and run `fvm flutter test` until T042–T048 pass.

**Checkpoint**: US1 and US2 both work. Every MVP destination is linked and every back rule passes.

---

## Phase 5: User Story 3 - Choosing how numbers look (Priority: P3)

**Goal**: one shared number formatter, the Arabic-Indic default and the Western option in settings,
applied instantly and persisted on the device.

**Independent Test**:
- Open settings and switch to Western. Every sample number on every shell screen changes at once.
- Restart offline, and the choice is kept.
- Automated: T061–T064 pass.

### Tests for User Story 3 (write first, must fail)

- [X] T061 [P] [US3] Write `apps/mobile/test/core/l10n/number_formatter_test.dart` (FR-027 – FR-029):
  - every golden example in contracts/number-format.md for both styles, after stripping U+2066/U+2069 (for example `piasters(850)` → `٨٫٥` / `8.5`, `integer(1250)` → `١٬٢٥٠` / `1,250`, `integer(-1)` → `−١` / `−1` using U+2212, `countdown(750 s)` → `١٢:٣٠` / `12:30`, `countdown(3725 s)` → `١:٠٢:٠٥`, `countdown(-5 s)` → `٠:٠٠`);
  - every raw output starts with U+2066 and ends with U+2069;
  - `piasters(825)` asserts in debug.
  - Build the expected Arabic-Indic strings in the test from code points or literals; literals are allowed in `test/`.
- [X] T062 [P] [US3] Write `apps/mobile/test/core/l10n/digit_style_test.dart`, using `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()` (FR-025 – FR-027):
  - default `arabicIndic`;
  - `set(western)` persists `pref.digit_style` = `"western"`;
  - a stored `"arabic_indic"` reads back as `arabicIndic`;
  - a stored `"garbage"` or a non-string value reads back as `arabicIndic`;
  - a new `ProviderContainer` over the same store reads the persisted value (restart).
- [X] T063 [P] [US3] Write `apps/mobile/test/core/l10n/arb_placeholders_test.dart`. It parses `apps/mobile/lib/l10n/app_ar.arb` and fails if any placeholder whose `type` is `int`, `num` or `double` is printed in message text outside a `plural` or `select` selector (contracts/number-format.md).
- [X] T064 [P] [US3] Write `apps/mobile/test/features/settings/settings_screen_test.dart` (US3 acceptance 1–3):
  - `/settings` shows the digit-style control with two options, Arabic-Indic selected by default;
  - choosing Western changes the sample numbers on the settings screen and on a pushed placeholder without a restart;
  - each option is ≥ 44×44.

### Implementation for User Story 3

- [X] T065 [P] [US3] Implement `apps/mobile/lib/core/l10n/digit_style.dart`: `enum DigitStyle {arabicIndic, western}` with wire values `"arabic_indic"` and `"western"`, and `fromWire(Object?) → DigitStyle`, which returns `arabicIndic` for anything unknown.
- [X] T066 [P] [US3] Implement `apps/mobile/lib/core/l10n/number_formatter.dart` per contracts/number-format.md, then make T061 pass:
  - pure Dart, with no Flutter imports;
  - digits from code points `0x0660 + d`; separators U+066B and U+066C (Arabic-Indic) or `.` and `,` (Western); minus U+2212; thousands grouping from 1,000;
  - every result wrapped in U+2066…U+2069;
  - no Arabic literals in the file (FR-042).
- [X] T067 [P] [US3] Implement `apps/mobile/lib/core/preferences/settings_store.dart` (an interface with `String? readString(String key)` and `Future<void> writeString(String key, String value)`) and `apps/mobile/lib/core/preferences/shared_prefs_settings_store.dart`. The latter uses `SharedPreferencesWithCache.create(cacheOptions: SharedPreferencesWithCacheOptions(allowList: {'pref.digit_style'}))` (research R11). The comment states the scope rule: device UI preferences only, never tokens or game state.
- [X] T068 [US3] Implement `apps/mobile/lib/core/l10n/digit_style_provider.dart` and wire the store, then make T062 pass:
  - `digitStyleProvider` is an `@Riverpod(keepAlive: true)` `Notifier<DigitStyle>` that reads `pref.digit_style` from `settingsStoreProvider`, and whose `set(DigitStyle)` updates state and then persists;
  - `numberFormatterProvider` derives a `NumberFormatter` from it;
  - create the `SettingsStore` in `apps/mobile/lib/bootstrap/startup.dart` and expose it as a keep-alive `settingsStoreProvider`.
- [X] T069 [US3] Implement `apps/mobile/lib/features/settings/settings_screen.dart`, the settings placeholder header plus the real digit-style control. It has two token-styled toggle options, each ≥ 44×44, and a row of sample numbers. Swap the `/settings` builder in `apps/mobile/lib/core/routing/router.dart` to it (FR-025). Make T064 pass.
- [X] T070 [US3] Extend `apps/mobile/lib/core/routing/placeholder_screen.dart` with a sample-numbers row: `integer(1250)`, `piasters(850)`, `ratio(4, 5)` and `countdown(750 s)`, all through `numberFormatterProvider`. This makes every placeholder show the digit setting.
- [X] T071 [US3] Add the US3 strings to `apps/mobile/lib/l10n/app_ar.arb`: `settingsDigitStyle`, `digitStyleArabic` «عربية ١٢٣», `digitStyleWestern` «غربية 123», and sample-row labels whose number placeholders are typed `String`. Make T063 pass.
- [X] T072 [US3] Add the digit-style dimension to the test matrix in `apps/mobile/test/helpers/pump_app.dart`, `apps/mobile/test/goldens/` and `apps/mobile/test/a11y/minimum_sizes_test.dart`:
  - add `DigitStyle` as a parameter in `apps/mobile/test/helpers/pump_app.dart` (overriding `digitStyleProvider`);
  - extend the golden matrices in `apps/mobile/test/goldens/shell_goldens_test.dart` and `apps/mobile/test/goldens/navigation_goldens_test.dart` to {Arabic-Indic, Western};
  - add settings-screen goldens;
  - extend `apps/mobile/test/a11y/minimum_sizes_test.dart` to both digit styles;
  - regenerate the goldens on Linux and inspect them; then `fvm flutter test` must pass.
- [X] T073 [US3] Write `apps/mobile/test/goldens/all_destinations_goldens_test.dart` (constitution X, FR-040). It iterates the `Destination` table in `apps/mobile/lib/core/routing/routes.dart` with its sample params and goldens every destination, the 22 routes plus the `tripPause` overlay, at `Surface.reference` and text scale 1.0, in both digit styles: 46 images named `goldens/all/<name>_<digits>.png`. Boot is captured with `appStartupProvider` overridden to a never-completing future. Generate on Linux, inspect every image, and make `fvm flutter test` pass.

**Checkpoint**: US1–US3 work. Digits switch everywhere and persist offline.

---

## Phase 6: User Story 4 - Balancing numbers work offline from day one (Priority: P4)

**Goal**: every mobile §14.3 key has a typed registry entry and a bundled default, read through one
`ConfigSource`, with overrides for tests and dev.

**Independent Test**:
- On a device that has never been online, every key returns its documented default.
- An override changes only its key, and a wrong-typed override falls back to the default.
- Automated: T074–T075 pass.
- **Dependencies:** Foundational only. Can run in parallel with US2 and US3.

### Tests for User Story 4 (write first, must fail)

- [X] T074 [P] [US4] Write `apps/mobile/test/core/config/tunables_defaults_test.dart` (FR-031 – FR-033, SC-007):
  - load `assets/config/tunables.json` through `rootBundle`;
  - assert it has exactly the 30 keys of contracts/tunables.md, with the right JSON types and values;
  - assert per-line keys exist for every `LineId`, hop 1300/1100/900/900/900 and bubble 4500/4000/3500/3500/3500, with hints `true` only for `line_hay`;
  - assert `pre_trip_card_mode` is `"always"` and one of `always`/`new_only`;
  - assert every `Tunable` in the registry has a default that parses to its declared type, and every JSON key is in the registry.
- [X] T075 [P] [US4] Write `apps/mobile/test/core/config/config_source_test.dart` (FR-034, FR-035):
  - bundled read returns defaults;
  - an override of `fuel_max` = 9 changes only `fuel_max`;
  - an override of `fuel_max` = `"nine"` or `true` falls back to 5;
  - a missing `assets/config/tunables.dev.json` asset is treated as `{}`;
  - after `appStartupProvider` completes, `ref.read(configSourceProvider).read(Tunable.fuelMax)` is synchronous.

### Implementation for User Story 4

- [X] T076 [P] [US4] Create `apps/mobile/assets/config/tunables.json` with exactly the 30 keys and defaults in contracts/tunables.md, and `apps/mobile/assets/config/tunables.dev.json` containing `{}`. Register both in `apps/mobile/pubspec.yaml`: `- assets/config/tunables.json`, and `- path: assets/config/tunables.dev.json` with `flavors: [dev]` (research R12).
- [X] T077 [P] [US4] Implement `apps/mobile/lib/core/config/tunable.dart`:
  - `Tunable<T extends Object>` with `key` and `T? parse(Object? raw)`, which returns null on a wrong type;
  - named constants for every non-per-line key, plus factories `tripHopMs(LineId)`, `tripBubbleMinMs(LineId)` and `tripHintsEnabled(LineId)` that build `<prefix>_<line_id>`;
  - `PreTripCardMode {always, newOnly}`, parsed from `"always"` and `"new_only"`;
  - a static `all` list;
  - **no default values in code** (constitution VIII).
- [X] T078 [US4] Implement the config sources in `apps/mobile/lib/core/config/`, then make T075 pass:
  - `apps/mobile/lib/core/config/config_source.dart`: `abstract interface class ConfigSource { T read<T extends Object>(Tunable<T> key); }`
  - `apps/mobile/lib/core/config/bundled_config_source.dart`: from a decoded JSON map; a missing key is a `StateError`, which the defaults test prevents;
  - `apps/mobile/lib/core/config/override_config_source.dart`: a layered source; valid override → fallback; invalid or missing → fallback.
- [X] T079 [US4] Implement `apps/mobile/lib/core/config/config_providers.dart` and wire it into startup:
  - `configSourceProvider` is keep-alive and built from the bundled map, plus the dev overrides when `Flavor.current == Flavor.dev`; a missing dev asset is `{}`;
  - load both JSON assets in `apps/mobile/lib/bootstrap/startup.dart` before startup completes;
  - add a header comment: only the Application layer reads it, and the engine gets tunables as explicit `params`.
  - Make T074 pass.

**Checkpoint**: tunables work offline. M15 can add a remote layer without touching readers.

---

## Phase 7: User Story 5 - Every change is checked automatically (Priority: P5)

**Goal**:
- A GitHub Actions pipeline with the pinned toolchain: format, analyze, all tests and goldens, the
  coverage gate and a `dev` APK, within 15 minutes.
- The Arabic-literal guard.
- The real commands in `CLAUDE.md`.

**Independent Test**:
- A PR that changes a token color fails (golden or palette).
- A PR that adds Arabic text in `lib/` fails.
- A clean PR passes.
- Automated: T080–T082 pass locally.

### Tests for User Story 5 (write first, must fail)

- [X] T080 [P] [US5] Write `apps/mobile/test/repo/no_arabic_literals_test.dart` (FR-042). It scans `apps/mobile/lib/**/*.dart`, excluding `lib/l10n/generated/`, and fails with file:line on any character in U+0600–U+06FF, U+0750–U+077F, U+08A0–U+08FF, U+FB50–U+FDFF or U+FE70–U+FEFF. A self-check proves that a temp string containing «ا» is detected.
- [X] T081 [P] [US5] Write `apps/mobile/test/repo/integer_money_test.dart` (constitution II; plan Constitution Check). It scans `apps/mobile/lib/**/*.dart`, excluding `lib/l10n/generated/`, and fails with file:line when a parameter, field, variable or return type declared `double` or `num` has a name matching `(?i)(piaster|amount|price|fare|cash|money|jenehat|bonat)`, or when `NumberFormatter.piasters` takes anything but `int`. A self-check proves that a temp snippet `double amountPiasters` is detected.
- [X] T082 [P] [US5] Write `apps/mobile/test/tool/check_coverage_test.dart` against fixture lcov files in `apps/mobile/test/tool/fixtures/`. It asserts that:
  - `**/*.g.dart`, `lib/l10n/generated/**` and `lib/main.dart` are excluded;
  - a `lib/` file absent from lcov counts as 0% covered;
  - the overall percentage is lines hit / lines found;
  - the exit code is 1 below `--min` and 0 at or above it.

### Implementation for User Story 5

- [X] T083 [US5] Implement `apps/mobile/tool/check_coverage.dart`, a dependency-free CLI: `--min <percent>`, `--lcov coverage/lcov.info` and `--lib lib`. It prints per-file misses and the total. Make T082 pass.
- [X] T084 [US5] Create `.github/workflows/mobile.yml` exactly per contracts/ci-checks.md:
  - triggers: `pull_request`, `push` to `master`, and `workflow_dispatch` with input `update_goldens`; `concurrency: mobile-${{ github.ref }}` with cancel-in-progress;
  - a `changes` job using `actions/checkout@v7` (`fetch-depth: 0`) and `git diff --name-only` against the merge base, outputting `mobile` for `apps/mobile/**`, `packages/**`, `.fvmrc` or `.github/workflows/mobile.yml`;
  - a `check` job using `subosito/flutter-action@v2` (`flutter-version-file: .fvmrc`, `cache: true`, `pub-cache: true`). It runs `pub get`, `build_runner build -d`, the format check over `git ls-files '*.dart'`, `flutter analyze --fatal-infos`, `flutter test --coverage` and `dart run tool/check_coverage.dart --min 80`, and uploads `test/**/failures/` with `actions/upload-artifact@v7` on failure;
  - a `build-android` job using `actions/setup-java@v6` (temurin 17), running `flutter build apk --flavor dev --debug` and uploading the APK with 7-day retention;
  - an `update-goldens` job (dispatch only) running `flutter test --update-goldens test/goldens` and uploading the PNGs;
  - `timeout-minutes: 15` on `check` and `build-android`, and `defaults.run.working-directory: apps/mobile`.
- [X] T085 [US5] Run the whole CI command list from contracts/ci-checks.md locally in `apps/mobile/`, in order: pub get, build_runner, format check, analyze, test with coverage, coverage gate, `build apk --flavor dev --debug`. Fix every finding until all of them exit 0, and record the total wall time in `specs/001-m03-app-shell/quickstart.md` under «Automated validation». Then prove the gates fail when they should, reverting each change afterwards:
  - set `ColorTokens.primary` back to the old `#1F5FA8` (ΔL\* 17.4 to danger) and confirm `palette_test` fails;
  - add a string containing «ا» to `apps/mobile/lib/main.dart` and confirm T080 fails;
  - add a `double amountPiasters` parameter and confirm T081 fails.

  Record the three failures in the PR description (US5 Independent Test, SC-008).
- [X] T086 [US5] Update `CLAUDE.md` (FR-043):
  - replace "No build, lint or test commands exist yet…" with a «Mobile commands» section listing the commands table from contracts/ci-checks.md (all through `fvm`, run in `apps/mobile/`);
  - note that goldens are generated on Linux, and that the `update-goldens` workflow dispatch regenerates them on CI.

**Checkpoint**: all five stories are complete, and the full local CI run is green.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: the doc updates owed by this PR, the coverage gate, and on-device validation.

- [X] T087 [P] Update the «الألوان» table in `docs/ux-spec.md` to the palette in contracts/design-tokens.md (FR-013), keeping the doc's Egyptian Arabic voice:
  - أزرق → #1A4B8C;
  - برتقالي → #F2542D;
  - replace the per-station row with the four-step ladder (محطة ١–٤: #3B2A6B, #0F766E, #5FAE4E, #A9DDF3; white letter on ١–٢, ink on ٣–٤; assigned by stop order; max 4 drop-off stations per trip);
  - add the «new» dot (danger fill, 2-pt ink outline);
  - add a sentence that text on the danger color is ink.
- [X] T088 [P] Update `docs/architecture-mobile.md` (FR-038, FR-044):
  - §2: the Target platform row becomes "minSdk 24, targetSdk 36; iOS 15.0", and the Performance goals row names the Samsung Galaxy A06 (4 GB, Helio G85);
  - §19: the Trip scene row names the device instead of NEEDS CLARIFICATION;
  - §24: mark items 1 and 2 as resolved, with links to `specs/001-m03-app-shell/research.md` R1 and R14.
- [X] T089 [P] Update `docs/delivery-plan.md` (FR-044):
  - add "mobile §24.2 (reference device: Galaxy A06)" to step 1's «Resolve» list for M03;
  - remove it from step 5's list, keeping a note that M02 measures fps on that device.
- [X] T090 Run `fvm flutter test --coverage && fvm dart run tool/check_coverage.dart --min 80` in `apps/mobile/`. Add tests until line coverage is ≥ 80% (SC-010). Don't exclude files to get there.
- [ ] T091 Walk manual scenarios 1–10 in `specs/001-m03-app-shell/quickstart.md` on an emulator or phone with `fvm flutter run --flavor dev`, and fix any failure.
- [ ] T092 On the reference Galaxy A06, using `apps/mobile/tool/perf/`:
  - build the `prod` release APK and run `apps/mobile/tool/perf/cold_start.sh com.wassalogra.app 10`; the median must be ≤ 3000 ms;
  - run the white-frame recording check per quickstart.md;
  - keep both outputs for the PR description (SC-001, SC-001a).

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T009)**: no dependencies. T009 (the spike) depends on T002–T008 and gates everything
  after it.
- **Foundational (T010–T017)**: depends on Setup and blocks every story.
- **US1 (T018–T041)**: depends on Foundational.
- **US2 (T042–T060)**: depends on US1 (shell, `PlaceholderScreen`, components, bottom bar).
- **US3 (T061–T073)**: depends on US1 (placeholders, components) and on US2's `/settings` route
  (T054).
- **US4 (T074–T079)**: depends on Foundational only. It can run in parallel with US1–US3; it touches
  `startup.dart` and `pubspec.yaml`, so coordinate those edits.
- **US5 (T080–T086)**: T080–T084 depend only on Foundational and can run in parallel with any story.
  T085 and T086 run after every story is merged into the branch.
- **Polish (T087–T092)**: T087–T089 can run any time. T090–T092 run last.

### Within each story

- Tests first; they must fail before implementation.
- Tokens → theme → components → screens → routes.
- Regenerate goldens only after the story's implementation is done, and inspect every PNG.

### Shared files (never edit in parallel)

`apps/mobile/pubspec.yaml`, `apps/mobile/lib/l10n/app_ar.arb`, `apps/mobile/lib/core/routing/router.dart`,
`apps/mobile/lib/core/routing/placeholder_screen.dart`, `apps/mobile/lib/bootstrap/startup.dart`,
`apps/mobile/lib/core/theme/components/wassal_bottom_bar.dart`, `apps/mobile/test/a11y/minimum_sizes_test.dart`.

---

## Parallel Examples

```text
# Setup, after T004:
T005 analysis_options.yaml · T006 fonts · T007 .gitignore · T008 l10n.yaml + ARB skeleton

# US1, all tests together:
T018 palette · T019 tokens · T020 components · T021 boot · T022 shell · T023 a11y · T024 goldens · T025 raw-values scan

# US1, token files together:
T026 colors · T027 typography · T028 shape/motion/space   (then T029 theme)

# US2, all tests, then the independent building blocks:
T042–T048 together; then T049 validators · T050 nav guard · T051 page types · T052 new dot

# Across stories, once Foundational is done:
US4 (T074–T079) and US5 (T080–T084) alongside US1 → US2 → US3
```

---

## Implementation Strategy

### MVP first (US1)

1. Setup (including the T009 spike), then Foundational.
2. US1: the app launches on شمس into الموقف with tokens and the bottom bar; palette, size and golden
   checks are green.
3. **Stop and validate:** quickstart scenarios 1 and 2, and a first cold-start reading.

### Incremental delivery

US1 → US2 (navigation) → US3 (digits). US4 (tunables) and US5 (CI) are slotted in parallel. Then
Polish. Each story is independently testable at its checkpoint, and the PR merges only when every
phase is complete and CI is green (delivery-plan step 1 «Done when»).

---

## Notes

- **Generated code** (`lib/l10n/generated/`, `*.g.dart`) is never committed. Run `fvm flutter pub get`
  and `fvm dart run build_runner build -d` after changing the ARB file or providers.
- **No Arabic literals in `lib/`** (T080). The Arabic-Indic digits are built from code points.
  Player text goes in `app_ar.arb`.
- **No raw colors, radii, borders, shadows or durations in widgets.** Use tokens (T025).
- **Integer money only:** `NumberFormatter.piasters(int)`. Never `double`.
- **Owner action after the first CI run:** make `check` and `build-android` required checks on
  `master` (contracts/ci-checks.md).
