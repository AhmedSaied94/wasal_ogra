# Quickstart: App Shell (M03)

How to set up, run and validate M03 end to end. Commands run from `apps/mobile` unless noted. The full
command list is in [contracts/ci-checks.md](./contracts/ci-checks.md).

## Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| FVM | 4.3.x | `dart pub global activate fvm`, then `fvm install` at the repo root (reads `.fvmrc` → Flutter 3.47.7) |
| Java | 17 (Temurin) | Needed by AGP 9.1 |
| Android SDK | platform 36, build-tools, NDK 28.2 | `fvm flutter doctor` must be green for Android |
| adb | platform-tools | Only for on-device checks and the cold-start measurement |
| ffmpeg | any recent | Only for the white-frame check |

## Setup

```bash
fvm install                                  # repo root
cd apps/mobile
fvm flutter pub get                          # also generates lib/l10n/generated/
fvm dart run build_runner build -d           # Riverpod code generation
```

## Automated validation (the same as CI)

```bash
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm flutter analyze --fatal-infos
fvm flutter test --coverage
fvm dart run tool/check_coverage.dart --min 80
fvm flutter build apk --flavor dev --debug
```

Expected: every step exits 0. `flutter test` includes the goldens, the palette check, the Arabic-literal
check, the ARB placeholder check, the tunables check and the minimum-size checks.

**Measured 2026-10-18 (T085)** on the Linux dev machine with warm pub and Gradle caches: the full list
(pub get, build_runner, format, analyze, 555 tests, coverage gate, dev APK) took **71 s**. Line coverage
was 90.1%. The gates fail when they should:

- `ColorTokens.primary` set back to `#1F5FA8` → `palette_test` fails (ΔL\* 17.4 against danger).
- A string containing «ا» in `lib/main.dart` → `no_arabic_literals_test` fails at `lib/main.dart:6`.
- A `double amountPiasters` parameter → `integer_money_test` fails at `lib/main.dart:6`.

## Manual scenarios (on a phone or emulator, `fvm flutter run --flavor dev`)

| # | Scenario | Expected | Covers |
| --- | --- | --- | --- |
| 1 | Set the phone language to English, then cold-start the app | شمس yellow from the first frame, then الموقف in Arabic RTL with the bar الموقف، الخطوط، الشقة، المحل from right to left | US1, SC-002 |
| 2 | Turn on system dark mode and restart | Looks identical | FR-009 |
| 3 | From الموقف, follow every placeholder link (routes.md table); open and close each sheet by swiping, with the close button, and by tapping outside | Every MVP destination is reachable; the bar shows only on the four tabs | US2, SC-006 |
| 4 | Scroll inside الخطوط, switch to المحل, switch back | الخطوط is unchanged | FR-016 |
| 5 | Open the trip placeholder and press back, then back again | Pause opens, then closes; the trip stays. The trip shows no top-right control, and everything tappable is in the bottom third | FR-019, FR-020 |
| 6 | On المحل press back; on الموقف press back once, wait 3 s, press once more, then press twice quickly | المحل → الموقف; the message shows twice, and the app only leaves on the quick double press | FR-021 |
| 7 | Settings → Western digits, then look at the placeholder sample numbers; kill the app, turn on airplane mode, reopen | Every number switches at once; the choice is still Western after the restart | US3, SC-003 |
| 8 | System font size to the largest | Text grows to 1.3× and stops; nothing overflows | FR-030 |
| 9 | Turn on reduce motion / remove animations | Screen changes fade, no slide | FR-023 |
| 10 | Install the `dev`, `staging` and `prod` builds side by side | Three icons with distinct names | FR-037 |

**Emulator run, 2026-10-18 (partial T091; Pixel 6 AVD, API 36, English locale, debug builds):**

- Scenario 1: the `dev` cold start shows شمس from the first frame, and `check_white_frames.sh` finds 0
  mostly-white frames out of 20. Android logs `Fully drawn com.wassalogra.app.dev/…MainActivity`, so
  the `wassal/launch` channel works on a real runtime. The debug-build time on the emulator (12.4 s)
  is not a measurement; the release measurement is on the A06.
- Scenario 10: `dev`, `staging` and `prod` install side by side as `com.wassalogra.app.dev` «وصّل dev»,
  `com.wassalogra.app.staging` «وصّل staging» and `com.wassalogra.app` «وصّل الأجرة».
- Scenarios 2–9 still need a hands-on pass on a device. Widget tests already cover each of them:
  dark mode, the links and sheets, tab state, the trip pause, back to exit, digits, the text clamp and
  reduce motion.

## Cold-start measurement (reference device, SC-001)

Device: Samsung Galaxy A06 (4 GB, Helio G85), USB debugging on, screen awake, no other apps open.

```bash
fvm flutter build apk --flavor prod --release   # debug keystore is fine for measurement
adb install -r build/app/outputs/flutter-apk/app-prod-release.apk
tool/perf/cold_start.sh com.wassalogra.app 10
```

- **What the script does:** it runs `adb shell am start -S -W -n <package>/com.wassalogra.app.MainActivity` ten
  times. `-S` force-stops the app first. After each run it reads the `Fully drawn com.wassalogra.app:
  +…ms` line from `adb logcat -d`, then prints each run and the median.
- **Pass:** median ≤ 3000 ms.
- **Recording the result:** paste the output into the PR description.
- **Optional:** repeat on the 3 GB Unisoc phone, once per release, for information only.

## White-frame check (SC-001a)

```bash
adb shell screenrecord --bit-rate 8000000 --time-limit 6 /sdcard/launch.mp4 &
sleep 1; adb shell am start -S -n com.wassalogra.app/com.wassalogra.app.MainActivity; wait
adb pull /sdcard/launch.mp4
tool/perf/check_white_frames.sh launch.mp4
```

- **What the script does:** it uses ffmpeg to extract every frame and fails if any frame has more than
  50% of its pixels at luma ≥ 245 (mostly pure white).
- **Pass:** the script exits 0. Also scrub the video by eye once and attach it to the PR.

## Done-when checklist (from the delivery plan)

- [ ] The app launches in RTL with the theme tokens and both digit settings.
- [ ] Goldens run in CI, and CI is green on the PR.
- [ ] `CLAUDE.md` lists the real build, lint and test commands (FR-043).
- [ ] The docs are updated in the same PR:
  - ux-spec «الألوان» (FR-013);
  - mobile §2 and §24.1 (FR-038);
  - mobile §2, §19 and §24.2, plus the delivery plan's step 1 and step 5 (FR-044).
- [ ] The owner has made `check` and `build-android` required checks on `master`.
