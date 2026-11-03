# Quickstart: Checking M11

## Prerequisites

- `apps/mobile` set up as in its `CLAUDE.md` (pub get, build_runner, `rive_native:setup`).
- Flutter tests run on the VPS: `RTEST_HOST=flutter-tests rtest …` from `apps/mobile`, never on the
  laptop.
- The dev stack up (`backend/`, Docker Compose) for §4, and `adb reverse tcp:8000 tcp:8000` on the
  owner's phone.
- Sample prices for the BONAT alternatives (revive 20, «زحمة» 8, refill 30) come from the release
  draft pack, as every sample does.

## 1. The suites

```bash
cd apps/mobile
RTEST_HOST=flutter-tests rtest --exclude-tags backend
RTEST_HOST=flutter-tests rtest test/core/ads test/core/economy/game_day_test.dart
RTEST_HOST=flutter-tests rtest test/drift            # schema 5 → 6
RTEST_HOST=flutter-tests rtest integration_test/fuel_ad_test.dart -d flutter-tester
cd ../../backend && uv run pytest apps/economy/tests/test_game_day_fixture.py
```

Expected:

- everything green, coverage ≥ 80%;
- the spy-gateway tests show no ad call while a trip runs (SC-001);
- `game_day.json` agrees in Dart and pytest.

## 2. The rules, scripted (SC-002, SC-003, SC-005, SC-008)

`test/core/ads/interstitial_due_test.dart` and `ad_offer_test.dart` cover every row of data-model.md's
rules. Check by hand that their tables include:

- trips 9 → no interstitial; trip 10 with 3 since the last → one;
- a ×2 on the last result → none at the next checkpoint;
- `remove_ads` → never;
- tutorial trips 1–2 → no ×2; trip 3 → ×2;
- a fourth refill ad on one Cairo day → `LimitReached`, and the next day → `Offered`.

## 3. On the phone with test ads (dev build)

```bash
cd apps/mobile && fvm flutter run --flavor dev
```

1. Fresh install: play the opening and tutorial trips 1–2. No ad and no consent form.
2. Before trip 3, the debug panel's «Ads» card shows consent `notRequired` (Egypt) and the
   `result_double` unit `ready`.
3. Trip 3's result: «اقبض ×٢» with «+{2×pay} بدل {pay}». Watch the test ad to the end: the pay
   doubles once, and the offer goes.
4. After the tutorial, fail a trip: «صالح الركاب» (ad) above the BONAT revive. Watch: the trip
   comes back paused at 40%.
5. In a trip with no «زحمة»: the ad badge shows. Tap it: the trip pauses before the ad, and after
   the reward the next station has +10 s. The trip waits for resume.
6. Empty the tank (debug panel): the out-of-fuel card shows the refill ad «باقيلك ٣ النهارده».
   Three refills; the fourth is «خلصت النهارده», with the BONAT refill beside it.
7. Play to trip 13 from Home: an interstitial shows before the card, not after «اطلع».
8. Debug panel → consent test geography EEA, clear the consent, relaunch, reach trip 3: the form
   shows before any ad request (SC-006).

## 4. The piggy against the dev stack (dev build)

1. Home shows «حصّالة الصبح». Tap it and watch the test ad. The debug panel shows the reference.
2. `uv run manage.py ads_dev_callback --user <player_id> --nonce <reference>` (in `backend`) within
   7 s. The reward card shows 30 ج and 2 بون, and the pills move when the sync pass ends.
3. Again, without the callback: after 7 s «المكافأة في الطريق، هتلاقيها أول ما توصل». Then run the callback,
   kill the app and open it again: on arrival at Home, the reward-arrived card shows once. Open it
   again: no card.
4. `uv run manage.py economy_check` → no mismatch.
5. `WASSAL_E2E_API=http://localhost:8000 fvm flutter test --tags backend test/backend/piggy_test.dart`
   runs steps 1–3 headless.

## 5. Staging with real units (owner)

The owner registers the test phone as a test device in the AdMob console first.

1. Install the staging build and run §3's steps 3–7 with real units serving test ads.
2. Tap the piggy 10 times over 10 days, or reset the cap on staging: 9 in 10 rewards appear within
   7 s (SC-004), and the admin shows each `granted` row.
3. Check that no live ad shows on the test phone. A live ad means the device isn't registered.

## 6. Design checks

```bash
RTEST_HOST=flutter-tests rtest test/design/fail_layout_test.dart test/design/trip_events_layout_test.dart \
  test/design/result_layout_test.dart test/design/c_home_layout_test.dart test/design/home_states_layout_test.dart \
  test/design/states_layout_test.dart
```

`fail_layout_test.dart` no longer skips box 12. The six new boards' tests run once their boards
are in `docs/design/` (contracts/design-briefs.md).
