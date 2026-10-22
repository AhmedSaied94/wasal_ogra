# Quickstart: Trip Screen (M02)

How to run M02 and check that it works. Contracts: [trip-controller.md](./contracts/trip-controller.md),
[trip-view.md](./contracts/trip-view.md), [scene-layout.md](./contracts/scene-layout.md),
[rive-character.md](./contracts/rive-character.md), [trip-records.md](./contracts/trip-records.md),
[ci-checks.md](./contracts/ci-checks.md).

## Prerequisites

- The repo's usual mobile setup (`CLAUDE.md`, "Mobile commands"), with `packages/content_models` built.
- Network once, for `rive_native`'s libraries (Android and Linux).
- For the device checks: a phone or emulator with `adb`, and for the performance check a Galaxy A06.
- The owner's character file at `apps/mobile/assets/rive/passenger.riv`
  ([rive-character.md](./contracts/rive-character.md)). Without it, passengers use the stand-in and the
  contract test fails.

## Setup (in `apps/mobile`)

```bash
fvm flutter pub get
fvm dart run build_runner build -d
fvm dart run rive_native:setup --verbose --clean --platform linux     # for flutter test
fvm dart run rive_native:setup --platform android                     # before the first Android build
python3 tool/sfx/generate.py                                          # rewrites assets/audio/sfx/*.wav
```

`generate.py` is deterministic: rerunning it changes no file, and CI checks that.

## Checks

```bash
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm flutter analyze --fatal-infos
fvm flutter test --coverage
fvm dart run tool/check_coverage.dart --min 80
fvm flutter test test/drift                       # the v1 → v2 schema tests
fvm flutter test test/features/trip/scripted_player_test.dart   # the 58 fixtures through the controls
```

## Scenarios

Run on a dev build (`fvm flutter run --flavor dev`) unless a scenario says otherwise.

1. **A trip, offline (US1, SC-001).** Turn on airplane mode. On Home's placeholder, open `line_hay.01`
   from the playtest list. Play it to the end. The tank goes down by one liter when the trip opens, the
   money moves seat by seat, the result route shows the stars, the conditions and the pay, and the pay
   is in the balance.
2. **Interruptions (US2, SC-006).** In `line_gamaa.02`, switch to another app and back: the pause card
   shows. Press the phone's back button: the pause card shows. With money in transit, press Home,
   then kill the app (`adb shell am force-stop com.wassalogra.app.dev`) and launch it: the trip opens
   paused at the moment it left the screen, with the same money in the same hands, and the tank
   didn't change. Then force-stop it while it runs in the foreground (a crash): it opens paused at its
   last accepted command, again with no liter spent.
3. **Leaving and restarting (US2).** From the pause card, «عيد المشوار» costs one liter and starts the
   trip again; «ارجع الموقف» lands on Home and pays nothing. With an empty tank, «عيد المشوار» says the
   tank is empty and does nothing.
4. **Passengers and choices (US3).** In `line_gamaa.01` and `line_gamaa.02`: wake the sleeper, see the
   blocked token turn orange with «؟», answer «أنا دافع!» both ways in test trips, pay the group payer's
   change and see it go to the payer.
5. **Events (US4).** `line_gamaa.01` (bump: collect a note within 3 s, lose another), `line_hay.02`
   (traffic and a payment dispute: the trip pauses until you choose). The other events play in the
   event test trips of `test/features/trip/`.
6. **Help (US5).** In a dev build with BONAT set for testing: use each booster, run out of one and buy
   it from the card, request breaks up to the limit, undo a send within a second. On `line_hay`, بلية
   points at the owed passenger as their stop nears; on `line_gamaa`, he explains each new type once.
7. **Failing (US6).** Fail a trip by sending wrong change: the failure card names the causes. Revive with
   BONAT, fail again: no second revive. Fail the story trip `line_hay.03` with a fight: no revive.
8. **Playtest tools (US7).** On dev and staging: the trip list on Home's placeholder, the debug panel,
   the copied replay record. On a prod build: neither exists.
9. **Accessibility.** Turn on «إزالة الرسوم المتحركة»: no shake, no bubble pop. Turn sound and vibration
   off on the pause card: every key event still shows and says what happened. Set the font size to the
   largest: the dashboard still fits.

## Owner checks on the Galaxy A06

1. **Frame rate and memory (SC-003, SC-004).** Build the prod-like profile run with the real character:

   ```bash
   tool/perf/trip_fps.sh com.wassalogra.app.dev line_gamaa.02
   ```

   It runs `integration_test/trip_perf_test.dart` under `flutter drive --profile` and prints the frame
   summary. Pass: average ≥ 55 fps, no one-second window below 45 fps, memory under 300 MB.
2. **Response (SC-005).** In the same run's output: a drawer tap reaches the hand within 100 ms, and the
   trip's first frame shows within 1 s of opening it.
3. **Download size.** Build the release app bundle and check the arm64 download with `bundletool`
   (`get-size total`). It must stay under 80 MB with `rive_native` (research R2).
4. **Rive license.** Confirm the plan that exported `passenger.riv` (Cadet or above) and record it in
   the PR.
5. **Playtest (SC-009).** Five testers from outside the team play `line_hay.01` on a staging build
   without instructions. Record who finishes and who replays by choice.

## Done when

- Every scenario above passes on a dev build.
- `flutter test` passes with the character file committed, including the 58 scripted fixtures, the
  kill-and-rebuild test, the trip goldens on the three surfaces, and the guards.
- The A06 checks pass and their output is in the PR.
