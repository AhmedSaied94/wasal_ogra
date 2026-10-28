# Quickstart: Validating M08 (Home, Pre-trip Card, Result)

How to prove the feature works, from CI checks to a device. The contracts hold the details:
[home.md](./contracts/home.md), [pre-trip-card.md](./contracts/pre-trip-card.md),
[result.md](./contracts/result.md), [seams.md](./contracts/seams.md),
[progress-rules.md](./contracts/progress-rules.md).

## Prerequisites

From a fresh checkout of `013-m08-home-result`:

```sh
# content models first (CLAUDE.md "Content commands")
cd packages/content_models && fvm dart pub get && fvm dart run build_runner build -d
cd ../../apps/mobile
fvm flutter pub get
fvm dart run build_runner build -d
fvm dart run rive_native:setup --verbose --clean --platform linux   # Rive goldens and tests
```

No database migration and no backend change.

## 1. The CI suite

```sh
cd apps/mobile
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm flutter analyze --fatal-infos
fvm flutter test --coverage --exclude-tags backend
fvm dart run tool/check_coverage.dart --min 80
```

**Expected:** all green. The repo guards include the new domain folders in
`domain_imports_test.dart`, with no Arabic in `lib/`, no raw style values and integer money.

## 2. The rules on the phone agree with the server

```sh
fvm flutter test test/core/progress
```

**Expected:** every ported case of `backend/apps/progress/tests/test_unlocks.py` passes, and so does
the sample sweep. To check the port still matches, compare the list of test names:

```sh
grep -o "def test_[a-z_]*" ../../backend/apps/progress/tests/test_unlocks.py | sed 's/def //' | sort > /tmp/py
grep -o "'test_[a-z_]*'" test/core/progress/unlocks_test.dart | tr -d "'" | sort > /tmp/dart
diff /tmp/py /tmp/dart   # no output
```

## 3. The result's figures equal the engine's (SC-004)

```sh
fvm flutter test test/features/result/result_screen_test.dart test/features/result/domain
```

**Expected:** for every finished parity fixture, each figure on the screen equals
`expected_result`, and the quote's replay ends on the same result.

## 4. The design checks (SC-005)

```sh
fvm flutter test test/design test/goldens/design --dart-define=DESIGN_COMPARE=true
```

**Expected:**

- the layout tests pass for `C-Home`, `HomeStates`, `PreTrip`, `Result` and `ShareCard`;
- `build/design_compare/<artboard>_<digits>.png` exists for each, in both digit styles.

Review them beside `docs/design/png/`. The differences allowed are those in research R20, and they
go in the PR description. Goldens are regenerated on Linux, or by CI's `update_goldens` run, which
is the reference.

## 5. Minimum sizes (SC-006)

```sh
fvm flutter test test/a11y
```

**Expected:** Home, the card and the result keep 44×44 targets and 12 pt text at 360×640, 360×800
and 390×844, at text scale 1.0 and 1.3, with nothing cut off or overlapping. At 360×640, Home
scrolls above the bar when the offline banner shows.

## 6. The loop, offline (SC-001, SC-007)

Headless, like M07's first-session test (there is no Linux runner):

```sh
fvm flutter test integration_test/home_loop_test.dart -d flutter-tester
fvm flutter test integration_test/first_session_test.dart -d flutter-tester
```

**Expected,** with the network off:

1. `home_loop_test`, for a player whose tutorial is done:
   1. Home shows the next trip;
   2. «يلا نطلع!» → the card → «اطلع» → the trip, which the scripted player finishes;
   3. the result matches it;
   4. «مشوار تاني» → the next trip's card → close → Home, whose line card has moved.
2. `first_session_test` (M07's, extended):
   1. from the opening through the five tutorial trips, each result shows «كمّل»;
   2. no tutorial trip opens a card;
   3. after trip 5, Home shows the next trip of FR-010, and «يلا نطلع!» opens its card.

Only the «محتاج نت» items are unavailable.

## 7. By hand, on the owner's phone (dev build)

```sh
fvm flutter run --flavor dev
```

Over wireless adb, with `adb reverse tcp:8000 tcp:8000` after each reconnect. Use 3-button
navigation for the checks, and restore gestures after.

| Check | How | Expected |
| --- | --- | --- |
| Home figures | open Home after a few trips | balances, fuel and countdown, line card, savings target match the debug sheet's sync card and the economy |
| Countdown vs clock (SC-003) | spend fuel; change the device time ±1 h | the countdown doesn't jump; a liter arrives on time and the button returns by itself |
| Offline | airplane mode on Home | the banner, the scene shrinks, the shop tab and BONAT pill read «محتاج نت»; a trip still starts |
| Card setting | Settings → «في الجديد بس»; replay a finished regular trip | the trip opens directly; a story trip or one with a new type still shows the card |
| Booster buy | a card with a booster at ×٠, offline | the confirmation, the count rises, BONAT drops; a double tap buys once |
| Result | finish a trip with a mistake | the stars pop in from `wassal.riv`'s `Stars`, with their labels; the quote, the breakdown, the mistakes line with the passenger's face, the bar moving from old to new |
| Arrival (FR-022a) | a fresh install: play to trip 3's result, kill the app there so the سلمى scene is due, relaunch | Home's arrival plays the scene (and the notification ask's place after it), then Home; nothing else opens on that arrival. A scene and the name sheet due together are covered by `arrival_items_test` |
| Share (SC-010) | tap share | the share sheet within 1 s, with a 1080×1080 picture in your digit style; works offline |
| Internal tools | the debug button on Home | the trip list, the sync card, the gallery |
| Prod | `fvm flutter build apk --flavor prod --debug` (with a promoted pack) | no debug button |

Timing on the reference Galaxy A06 (SC-002, SC-010) is measured when one is available. Until then,
use the owner's Redmi Note 7 and note it in the PR.

## 8. iOS (owner)

Run Codemagic's `ios-dev-unsigned`. **Expected:** it builds with no Podfile (`share_plus` as a
Swift Package), and the share sheet opens on a sideloaded device.
