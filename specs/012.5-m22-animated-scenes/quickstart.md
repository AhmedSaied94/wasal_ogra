# Quickstart: Animated Scenes (M22)

How to check that the feature works: Part A runs on the dev machine and in CI, and Part B is the
owner's, on the phones. The tests behind each step are in
[contracts/ci-checks.md](./contracts/ci-checks.md).

## Prerequisites

- A checkout of `012.5-m22-animated-scenes`, set up as `CLAUDE.md` "Mobile commands" says
  (`packages/content_models` built, `fvm flutter pub get`, `build_runner`).
- Rive's Linux library: `fvm dart run rive_native:setup --verbose --clean --platform linux` (in
  `apps/mobile`).
- Both art files in `apps/mobile/assets/rive/`: `wassal.riv` (the owner's updated export) and
  `wassal_scenes.riv`.

## Part A: automated

Run in `apps/mobile`.

1. **The pure parts, first:**

   ```sh
   fvm flutter test test/features/onboarding/domain/panel_turns_test.dart \
     test/core/art/panel_talkers_test.dart test/core/art/rive_contract_test.dart
   ```

   Expected: every turn's order, length, pause and bounds, and the four Booleans, as data-model.md
   "Turns" says.

2. **The delivered file** (tag `rive`):

   ```sh
   fvm flutter test --tags rive test/core/art test/features/onboarding \
     test/features/trip/rive_art_contract_test.dart
   ```

   Expected:
   - the contract passes with no problem;
   - every spoken line's speaker changes the panel, and a character who isn't drawn changes nothing;
   - the first-frame sheets match their goldens.

3. **Turns, fallbacks and M07 unchanged:**

   ```sh
   fvm flutter test test/features/onboarding test/core test/goldens/design/intro_goldens_test.dart
   ```

   Expected:
   - turns, «يلا», «تخطّى», back and reduced motion behave as contracts/scene-turns.md says;
   - M07's scene tests and the `Intro` goldens pass without an update.

4. **The usta's look:** after rebuilding `docs/design/` and running `tool/design/sync_assets.dart`
   (contracts/usta-look.md):

   ```sh
   fvm flutter test --update-goldens test/goldens \
     test/features/trip/rive_art_goldens_test.dart test/core/theme
   git status --short -- '*.png'
   ```

   Expected: only the goldens contracts/usta-look.md lists have changed, each by the usta alone.

5. **Everything, as CI does:** the format check, `flutter analyze --fatal-infos`,
   `flutter test --coverage --exclude-tags backend` and the coverage gate (≥ 80%), then the first
   session end to end:

   ```sh
   fvm flutter test integration_test/first_session_test.dart -d flutter-tester
   ```

## Part B: on the phones (owner)

The dev flavor, with Rive's Android library (`fvm dart run rive_native:setup --platform android`),
`adb reverse tcp:8000 tcp:8000`, and reduced motion off.

1. **Every panel, both phones (SC-001).** On the Redmi Note 7 and the Galaxy A06, open the playtest
   «Onboarding» card and play the opening, then the سلمى scene.
   - Each panel moves by itself, and no «RIVE» splash shows.
   - Lines come one at a time, and the character who talks is the one whose bubble just appeared.
   - In `opening_go`, المعلم and بلية talk; the usta at the wheel doesn't.
   - «يلا» before the last line shows the rest at once, and the next «يلا» moves on.
   - With reduced motion on (Settings → Accessibility → Remove animations), every panel is its still
     drawing with every bubble, as before.
2. **Frame rate (SC-002), on the Galaxy A06:**

   ```sh
   tool/perf/scene_fps.sh com.wassalogra.app.dev
   ```

   Pass: an average of at least 55 fps, no one-second window under 45 fps, and memory under 300 MB.
   Paste the output in the PR.
3. **Cold start and the first trip (SC-003), on the Galaxy A06:**
   - `tool/perf/cold_start.sh com.wassalogra.app.dev 10`: Home within 3 s, with no white frame.
   - On a fresh install, open the app, tap «يلا» as soon as it shows, accept the suggested name, and
     time it: the first trip starts within 20 s of opening the app (M07 SC-001). Do it once on the
     Redmi Note 7 too, before merge.
4. **The Rive source:** in the Rive editor, rename «Untitled» to `wassal_scenes`, and move it beside
   `wassal.riv` if they should sit together. The app's copy doesn't change.

## Done when

- Part A passes in CI, with the new and changed goldens reviewed in the PR.
- Part B's first three checks pass on both phones (the frame rate and the cold start on the A06), and
  their results are in the PR or `docs/owner-actions.md`.
- The delivery plan's "done when" for 012.5:
  - the opening and the سلمى scene animate on the Redmi Note 7 and the Galaxy A06, and the character
    who talks is the one whose bubble shows;
  - without the file, with a broken artboard, or under reduced motion, every panel shows its drawing,
    and M07's scene goldens are unchanged.
