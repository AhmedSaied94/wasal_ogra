# Implementation Plan: App Shell (M03)

**Branch**: `001-m03-app-shell` | **Date**: 2026-10-18 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-m03-app-shell/spec.md`

## Summary

M03 creates the Flutter app in `apps/mobile` that every later mobile feature builds on. It ships no
real screen content, only:

- **Shell:** an Arabic RTL app shell with a four-tab bottom bar (state kept per tab), every MVP
  destination from mobile §9 as a linked placeholder, and the navigation and back rules from
  ux-spec «قواعد التنقل».
- **Visual system:** «ستيكر الميكروباص» theme tokens, using the owner's revised palette with automated
  lightness and contrast checks.
- **Digits:** one number formatter with an Arabic-Indic / Western digit setting, persisted on the
  device.
- **Tunables:** a typed `ConfigSource` with bundled defaults for every key in mobile §14.3.
- **Build:** three build variants, Flutter pinned with FVM, and a GitHub Actions pipeline (analyze,
  format, unit/widget/golden tests, palette check, Arabic-literal check, 80% coverage, `dev` APK).
- **Launch:** a no-white-frame launch on شمس, a fully-drawn report, and a cold-start measurement
  script for the reference device (Galaxy A06).

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**: Dart 3.13.5 (bundled with Flutter 3.47.7 stable, released 2026-10-08), pinned with
FVM in `.fvmrc` at the repository root

**Primary Dependencies**:

- `material_ui` ^1.7.0: Flutter 3.47's separated Material library, which go_router 18 requires (R3).
- `flutter_riverpod` ^3.4.3, `riverpod_annotation` ^4.0.7, and `riverpod_generator` ^4.0.9.
- `go_router` ^18.1.0.
- `flutter_localizations` + `intl` ^0.20.3, used for gen-l10n only.
- `shared_preferences` ^2.5.6.
- Dev: `build_runner`, `flutter_native_splash` ^2.4.8, `flutter_lints`, and the `riverpod_lint` ^3.1.9
  analyzer plugin.

Details are in research.md R2. No drift, dio, Firebase, ads, IAP, Flame or Rive in this feature.

**Storage**: `shared_preferences`, only for device UI preferences (`pref.digit_style`), behind a
`SettingsStore` interface. Bundled JSON assets for tunables. No database (drift arrives with M05).

**Testing**: `flutter_test` for unit, widget and golden tests. Goldens use plain `matchesGoldenFile`
with the bundled fonts loaded through `FontLoader` and a 0.1% tolerant comparator (R6), at 390×844 and
360×640 × {Arabic-Indic, Western} × text scale {1.0, 1.3}. Accessibility
matchers (`iOSTapTargetGuideline` for 44×44, `textContrastGuideline`) plus a custom 12 pt text-size
check. Coverage comes from `flutter test --coverage` (lcov), gated at ≥ 80%. Cold-start timing on the
device is measured manually with a script and is not in CI.

**Target Platform**: Android, minSdk 24 (Android 7.0), targetSdk and compileSdk 36. The iOS deployment
target is declared as 15.0, but iOS builds and CI are deferred to phase 3. Portrait only. (Since
2026-10-24, PR #14, Codemagic builds an unsigned iOS dev IPA from `codemagic.yaml`. There is no
Podfile: the iOS plugins are Swift Packages.)

**Project Type**: mobile app (`apps/mobile`) inside the `wassal` monorepo

**Performance Goals**: median cold start ≤ 3.0 s to الموقف on a Samsung Galaxy A06 (prod variant,
release mode, 10 runs, fully-drawn report); no frame mostly pure white during launch

**Constraints**:

- RTL Arabic regardless of the device locale; Arabic-Indic digits by default.
- Fully offline: no network calls in M03.
- Minimum sizes: 44×44 pt touch targets, 12 pt text.
- Text scale clamped to 1.0–1.3.
- Light theme only (same look in dark mode).
- No Arabic literals in `lib/`.
- CI result within 15 minutes.

**Scale/Scope**:

- 22 routed destinations plus 1 overlay, and 4 tabs.
- 12 color tokens, 7 type styles.
- 30 tunables.
- 3 build variants.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How M03 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | Partly | No engine code. `ConfigSource` is read only by the Application layer. Tunables reach the engine later as explicit `params`. No domain code imports Flutter: `NumberFormatter` and the tunable registry are pure Dart under `core/`. |
| II | Integer money | Yes | `NumberFormatter.piasters(int)` takes integer piasters only. Display formatting happens at the presentation edge. `integer_money_test.dart` fails on `double` or `num` in money code. |
| III | Parity | No | No engine rules or fixtures. |
| IV | Server authority | No | No currencies or purchases. |
| V | Offline-first | Yes | No network calls. Fonts, tunables, strings and the digit preference are all local, and first launch needs nothing. |
| VI | Idempotency | No | No state-changing requests. |
| VII | Content, not code | Yes | All player-visible text, including placeholder labels and the app's error and toast strings, lives in ARB files, and a test fails on Arabic literals in `lib/`. Default values live in `assets/config/tunables.json`, not in code. The glossary identifier enums (`LineId`, `VehicleId`, …) are identifiers, not content models, and B04's generated models replace them. |
| VIII | Tunable numbers | Yes | Every §14.3 key has a typed registry entry and a bundled default, with a test against the documented table. No new tunables. The 2 s back-to-exit window and the motion durations are UX constants in the spec and tokens, not balancing numbers. |
| IX | No ads in a trip | No | No ads. |
| X | RTL and Arabic first | Yes | The locale is forced to `ar_EG`, so direction is RTL. Goldens cover every destination in RTL × both digit styles, plus the full size and scale matrix for the representative screens. Directional icons mirror automatically. |
| XI | Accessible minimums | Yes | The trip placeholder has no top-right control, and every tappable element sits in the bottom third (tested). Automated 44×44 and 12 pt checks, a WCAG contrast test on token pairs, ΔL\* ≥ 18 for colors that must differ, station color + letter, and fade-only transitions with reduce-motion. |
| XII | No runtime LLM | No | None. |
| XIII | Small, testable features | Yes | Test-first for the formatter, palette, tunables registry and route validators. Widget tests cover navigation and back rules, plus goldens. App coverage ≥ 80% is gated in CI. |

**Locked stack.** M03 follows it: Flutter is pinned with FVM, Riverpod uses `riverpod_generator`, routing
uses `go_router`, and the flavors are `dev`, `staging` and `prod`. It adds `shared_preferences` for
device UI preferences only. The locked stack doesn't list it, and the decision log rejected it for the
ledger and sync, not for preferences. The owner approved this use on 2026-10-18. It never stores tokens
(those go to `flutter_secure_storage`) or game state (that goes to drift in M05).

**Security.**

- No secrets: the debug keystore is used for local release-mode measurement, and signing keys stay out
  of git (`.gitignore` already covers them).
- No network calls.
- No personal data.

**CI gates (constitution).**

- Mobile: `dart analyze` plus unit, widget and golden tests, run on every pull request that touches the
  mobile app.
- The automated checks for "no Arabic literals" and "integer-only money" are added now that code
  exists.

**Gate result (pre-research): PASS.** No violations, so Complexity Tracking stays empty.

**Gate result (post-design): PASS.** The re-check after Phase 1 found no change:

- the contracts keep player text in ARB, money as `int`, and tunables as data;
- every route lives on the shell or root navigator without trip logic;
- the design introduces no domain code that imports Flutter.

## Project Structure

### Documentation (this feature)

```text
specs/001-m03-app-shell/
├── plan.md              # This file
├── research.md          # Phase 0: decisions, versions, resolved open questions
├── data-model.md        # Phase 1: tokens, destinations, preference, tunables, variants, «new» dot
├── quickstart.md        # Phase 1: how to run, test, measure and verify
├── contracts/
│   ├── design-tokens.md # palette, checks, type, shape, motion, components
│   ├── routes.md        # route table, presentation, validators, back rules
│   ├── number-format.md # formatter API and golden examples
│   ├── tunables.md      # keys, types, defaults, read interface
│   └── ci-checks.md     # CI jobs, commands, pass criteria
├── checklists/requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
.fvmrc                                   # Flutter 3.47.7 pin (repo root, one pin for the monorepo)
.github/workflows/mobile.yml             # analyze · format · test+goldens · coverage · dev APK
apps/mobile/
├── pubspec.yaml                         # deps, fonts, assets (flavor-conditional dev overrides)
├── analysis_options.yaml                # flutter_lints + strict-casts/inference/raw-types
├── l10n.yaml                            # gen-l10n: app_ar.arb → lib/l10n/generated/
├── flutter_native_splash.yaml           # شمس background (pre-12 and Android 12+)
├── assets/
│   ├── config/tunables.json             # bundled defaults (30 keys)
│   ├── config/tunables.dev.json         # dev-only overrides ({}), flavors: [dev]
│   └── fonts/                           # Lalezar-Regular.ttf, BalooBhaijaan2[wght].ttf, OFL.txt ×2
├── lib/
│   ├── main.dart                        # single entry; flavor from appFlavor
│   ├── bootstrap/                       # bootstrap.dart (orientation, runApp), app.dart (MaterialApp.router), flavor.dart
│   ├── l10n/app_ar.arb                  # every player-visible string (+ generated/ output)
│   ├── core/
│   │   ├── theme/                       # tokens/{colors,typography,shape,motion,space}.dart, app_theme.dart,
│   │   │                                #   components/{primary_button,secondary_button,sticker_card,
│   │   │                                #   wassal_bottom_bar,new_dot}.dart
│   │   ├── routing/                     # routes.dart (table), router.dart, param_validators.dart,
│   │   │                                #   sticker_page.dart, sheet_page.dart, shell_scaffold.dart,
│   │   │                                #   back_to_exit.dart, nav_guard.dart, placeholder_screen.dart,
│   │   │                                #   trip_pause_overlay.dart, new_dot_providers.dart
│   │   ├── l10n/                        # digit_style.dart, number_formatter.dart, digit_style_provider.dart
│   │   ├── config/                      # config_source.dart, tunable.dart, bundled_config_source.dart,
│   │   │                                #   override_config_source.dart, config_providers.dart
│   │   ├── preferences/                 # settings_store.dart, shared_prefs_settings_store.dart
│   │   ├── glossary/ids.dart            # LineId, VehicleId, ChapterId, RoomId (until B04 codegen)
│   │   └── platform/launch_metrics.dart # reportFullyDrawn via MethodChannel
│   └── features/
│       ├── boot/boot_screen.dart        # name on شمس → /home when startup completes
│       └── settings/settings_screen.dart# placeholder + the real digit-style control
├── android/                             # namespace com.wassalogra.app; flavors dev/staging/prod;
│   └── app/src/main/kotlin/…/MainActivity.kt   # launch-metrics channel → reportFullyDrawn()
├── ios/                                 # IPHONEOS_DEPLOYMENT_TARGET 15.0; Swift Packages, no Podfile; built on Codemagic (PR #14)
├── test/
│   ├── core/theme/{palette_test,tokens_test,components_test}.dart
│   ├── core/l10n/{number_formatter_test,digit_style_test,arb_placeholders_test}.dart
│   ├── core/config/{tunables_defaults_test,config_source_test}.dart
│   ├── core/routing/{route_table_test,param_validators_test,navigation_test,back_behavior_test,nav_guard_test}.dart
│   ├── features/settings/settings_screen_test.dart
│   ├── a11y/minimum_sizes_test.dart
│   ├── repo/no_arabic_literals_test.dart
│   ├── tool/check_coverage_test.dart
│   ├── goldens/shell_goldens_test.dart  # + goldens/*.png (Linux-generated)
│   ├── flutter_test_config.dart         # FontLoader for FontManifest + 0.1% tolerant comparator
│   └── helpers/{pump_app.dart,surfaces.dart}
└── tool/
    ├── check_coverage.dart              # lcov gate: excludes, unreported files at 0%, --min 80
    └── perf/{cold_start.sh,check_white_frames.sh}   # SC-001 / SC-001a on the Galaxy A06
```

**Generated code** is not committed: `lib/l10n/generated/` (gen-l10n) and `**/*.g.dart` (Riverpod).
Both are added to `.gitignore` and regenerated by `flutter pub get` and `build_runner`, locally and in
CI.

**First task is a spike** (R3): confirm that `material_ui`, go_router 18 and the gen-l10n delegates
build together and render RTL. If they don't, record the workaround in research.md before continuing.

**Structure decision.** This is the `apps/mobile` layout from mobile §5. M03 creates only the `core/`
folders it needs, plus `features/boot` and `features/settings`. Placeholders are one generic
`PlaceholderScreen` driven by the route table, so each later feature replaces a builder rather than
deleting files. `packages/` is not created yet (M01 creates `trip_engine`, B04 creates
`content_models`).

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified

No violations. Two items are recorded for visibility, but neither is a constitution violation:

| Item | Why | Simpler alternative rejected because |
| --- | --- | --- |
| `shared_preferences` for device UI preferences (owner-approved 2026-10-18) | Digit style must persist before M05 brings drift | Setting up drift now would pull M05's database design, codegen and migrations into M03 |
| Hand-written glossary identifier enums in `core/glossary/ids.dart` | Route validators and per-line tunables need `LineId` and others before B04 generates models | Waiting for B04 would block M03, the first feature. B04's generated code replaces these enums. |
