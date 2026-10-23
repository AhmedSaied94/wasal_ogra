# Quickstart: Design Refresh (M21)

How to run M21 and check that it works. Contracts: [design-tokens.md](./contracts/design-tokens.md),
[components.md](./contracts/components.md), [trip-layout.md](./contracts/trip-layout.md),
[rive-characters.md](./contracts/rive-characters.md), [design-checks.md](./contracts/design-checks.md).

## Prerequisites

- The repo's usual mobile setup (`CLAUDE.md`, "Mobile commands"), with `packages/content_models`
  built.
- Network once, for `rive_native`'s libraries and the two font files.
- **The owner's Rive file**, `apps/mobile/assets/rive/wassal.riv`
  ([rive-characters.md](./contracts/rive-characters.md)). The feature can be built and tested on the
  static art without them, but it doesn't merge without them: the tests tagged `rive` fail until
  they're in.
- For the device checks: a phone or emulator with `adb`, and a Galaxy A06 for the performance check.

## Setup (in `apps/mobile`)

```bash
fvm flutter pub get
fvm dart run build_runner build -d
fvm dart run rive_native:setup --verbose --clean --platform linux     # for flutter test
fvm dart run tool/design/gen_tokens.dart                               # rewrites lib/core/theme/tokens/design_tokens.dart
fvm dart run tool/design/sync_assets.dart                              # copies icons and illustrations from docs/design
```

Both tools are deterministic: rerunning them on an unchanged `docs/design/` changes no file, and the
repo tests check that.

## Checks

```bash
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm flutter analyze --fatal-infos
fvm flutter test --coverage
fvm dart run tool/check_coverage.dart --min 80
fvm flutter test test/design                                      # artboard layout tests
fvm flutter test test/features/trip/scripted_player_test.dart     # M02's 58 fixtures, unchanged (SC-003)
fvm flutter test --tags rive                                      # the owner's files against the contract
```

To see each golden beside its design PNG for the PR:

```bash
fvm flutter test test/design --dart-define=DESIGN_COMPARE=true    # writes build/design_compare/*.png
```

## Scenarios

Run on a dev build (`fvm flutter run --flavor dev`) unless a scenario says otherwise.

1. **Tokens (US1, US7).**
   - Change one colour in a scratch copy of `docs/design/tokens.json`, run `gen_tokens.dart`, and run
     `flutter test test/repo/design_tokens_test.dart test/goldens`. The token test passes, and the
     goldens that use the colour fail and show where.
   - Restore the file: the generator puts everything back.
   - Edit `design_tokens.dart` by hand: the token test fails and names the command to run.
2. **The gallery (US1).** On Home's placeholder, open the gallery from the playtest section.
   - Every component shows in every state.
   - Pressing a button pushes it down by its lip and back.
   - The digit switch changes every number.
   - The reduced-motion switch stops the pops and pulses.
   - On a prod build there is no way in.
3. **The frame (US2).**
   - **Cold start.** The native splash and `Loading` share the `sun` ground with no white frame. The
     road bar fills as the boot steps finish, with the marker moving right to left.
   - **Navigation.** The four tabs show the new `BottomNav`, with its dots. A later feature's route
     shows its `ScreenHeader` and empty state. A sheet drags down to close, and back twice on Home
     leaves through the new toast.
   - **Settings.** The digit choice is a `Segmented` control.
4. **A trip (US3).** Open `line_gamaa.02` from the playtest list.
   - **The screen.** The HUD, the strip and the dashboard match `C-Trip`. Faces sit at the design's
     seats, notes hop along the columns, and the next stop's ring and countdown pulse under 8 s.
   - **The hand.** Play to the end. Undo a send with the «رجّع» pill in the hand.
5. **Events and choices (US4).**
   - **`line_gamaa.01`.** After the bump, a fallen note shows its sun ring; tap it within 3 s. Use the
     ledger booster: the tags turn into «دافع» / «لسه» / «على صاحبه» for 10 s, with its countdown.
   - **`line_hay.02`.** Traffic shows its banner; the dispute pauses the trip on its two faces.
   - **`line_hay.03`, the story trip.** The «مشوار قصة» chip and the condition strip show.
   - **Hints.** On `line_hay`, بلية's head, bubble and hand show without dimming anything.
   - **The rest.** The fare increase (banner, struck-through price) and «أنا دافع!» («ماشي» / «لأ، ما
     دفعتش!» next to the passenger, with the trip still running) aren't in the sample pack. They play
     in M02's event test trips, and their goldens are `TripEvents`'.
6. **Pause and failure (US5).**
   - **Pause.** The `Pause` card has the fuel chip on «عيد المشوار» and working switches.
   - **Failure.** Fail a trip by short change. The `Fail` card shows angry faces from the trip, the
     reason chip and the BONAT revive. Back and taps outside do nothing. Revive, fail again: no revive.
   - **Story failure.** Fail `line_hay.03` with a fight: the story reason, and no revive.
   - **An empty booster.** Run out of a booster and tap it: the trip pauses on the spend confirmation;
     buying uses it and resumes.
7. **The art (US6).**
   - **With the files.** Every passenger is drawn in its look and moves through the states as the trip
     plays: sleep and wake, headphones and the two calls, impatience, change due, a fight, a claim,
     boarding and getting off.
   - **Without it.** Rename `wassal.riv`: passengers fall back to the static art with a gentle
     bob, the trip plays the same, and the debug panel lists the problem.
   - **Tiers.** Switch `ArtTier` in the debug panel: the back rows go static.
8. **Accessibility.**
   - **Reduced motion.** Turn on «إزالة الرسوم المتحركة»: no shake, pop, pulse or entrance; the art's
     effects hold still.
   - **Text size.** Set the largest font size: the trip's HUD and dashboard stop growing at 1.15×,
     cards grow to 1.3×, nothing clips.
   - **TalkBack.** Each control reads its label. A passenger reads their look and stop, and «ليه باقي»
     only while their tag is hot.
9. **Narrow and short phones.** On a 360×800 emulator (or the A06): faces, tags, notes and targets are
   full size, with the cabin's top cropped. On a 360×640 emulator, the scene shrinks as before (the
   exception), and the HUD and dashboard keep their sizes.

## Owner checks

1. **Side by side (SC-010).** Open the compare images in the PR (`build/design_compare/`), one per
   artboard in scope. Accept each, or list what to change. design-checks.md lists the expected
   differences.
2. **Frame rate and memory on the Galaxy A06 (SC-005).**

   ```bash
   tool/perf/trip_fps.sh com.wassalogra.app.dev line_gamaa.02
   ```

   Pass:
   - an average of at least 55 fps;
   - no one-second window under 45 fps;
   - memory under 300 MB.

   Record the p90 frame time. If it misses on the `rive` tier, run it again on `near_rive`, and record
   both in research.md R18.
3. **Cold start on the A06 (SC-006).** `tool/perf/cold_start.sh com.wassalogra.app.dev 10`: no white
   frame, and Home within 3 s.
4. **Download size (SC-009).** The release app bundle's arm64 download (`bundletool get-size total`)
   stays under 80 MB.
5. **The Rive file.** Export `wassal.riv` again as the contract's "Open" asks, and commit it. Record in
   the PR the plan it was exported from and its size (budget about 3 MB).

## Done when

- Every scenario above passes on a dev build.
- `flutter test` passes with the Rive file committed, including:
  - the artboard goldens and layout tests;
  - M02's and M03's behaviour tests, unchanged;
  - the scripted fixtures;
  - the repo guards.
- The owner has accepted the side-by-side review, and the A06 checks are in the PR.
