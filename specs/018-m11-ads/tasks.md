---

description: "Task list for M11 Ads Integration: rewarded, interstitial, consent"
---

# Tasks: Ads Integration — Rewarded, Interstitial, Consent (M11)

**Input**: Design documents from `specs/018-m11-ads/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first** (constitution XIII). Write these tests first:
  - the pure rules (`gameDayOf`, `adOffer`, `interstitialDue`, the piggy's plan);
  - `ad_reward_seen`'s validator and fold;
  - the v6 migration;
  - the bootstrap `ads` block's parsing;
  - `AdsService.watch`'s outcome table.

  Every phase writes its tests first, and they must fail before its implementation starts.
- **No ad call while a trip runs.** Every trip test with ads uses `FakeAdsGateway` with a
  `TripRunningProbe` (contracts/ads-gateway.md), so any SDK call while the engine runs fails the test
  (spec FR-009, SC-001).
- **Real economy.** Economy-backed tests use the real `EconomyService` over in-memory drift
  (`apps/mobile/test/helpers/economy.dart`).
- **Prices** for the BONAT alternatives (revive 20, «زحمة» 8, refill 30) and the samples' values come
  from the release draft pack, through `releaseDraftPack()` (`test/helpers/synthetic_packs.dart`).
- **Where tests run.** Flutter tests run on the VPS: `RTEST_HOST=flutter-tests rtest …` from
  `apps/mobile`, never on the laptop.
- **Coverage.** At least 80% of lines in `apps/mobile`.
- **One PR.** Its description lists:
  - the B07 hand-over done differently (the wallet through the sync pass, research R12);
  - the trip-controller contract change (research R7);
  - schema 6;
  - the expected golden differences (Fail, Result, Home, `TripEvents`, the booster card);
  - the owner's open items.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US6 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the SDK and adapters, the ad ids, the platform configuration and the guards.

- [X] T001 Add to `apps/mobile/pubspec.yaml`, each with a comment naming research R1 or R2:
  `google_mobile_ads: ^9.2.0`, `gma_mediation_applovin: ^2.6.4` and `gma_mediation_unity: ^1.11.0`.
  - Run `fvm flutter pub get`.
  - Confirm `apps/mobile/ios/` still has no `Podfile` after `fvm flutter build ios --no-codesign
    --flavor dev --config-only`, or record that the build can't run on Linux and leave the check to
    Codemagic (T080).
- [X] T002 [P] Write `apps/mobile/test/core/ads/ad_ids_test.dart` first (contracts/platform-config.md
  "Ad ids"):
  - every `Flavor` maps every `AdUnit` on both platforms;
  - dev's app ids and units all hold Google's sample publisher `3940256099942544`;
  - staging's and prod's hold none of it;
  - no two placements share a unit within a flavor, except where the owner's ids say so.
- [X] T003 [P] Create `apps/mobile/lib/core/ads/ad_ids.dart` (research R4):
  - `enum AdUnit { resultDouble, fuelRefill, tripRevive, trafficJam, morningPiggy, interstitial }`;
  - `AdIds` (`androidAppId`, `androidUnits`, `iosAppId`, `iosUnits`) and `const adIds` by `Flavor`;
  - dev: `ca-app-pub-3940256099942544~3347511713` / `~1458002511`, rewarded `/5224354917` /
    `/1712485313`, interstitial `/1033173712` / `/4411468910`;
  - staging and prod: the owner's ids from T065. Until then they are placeholders that fail T002's
    "no sample publisher" check, so the PR can't merge without them.
- [X] T004 [P] Android (contracts/platform-config.md "Android"):
  - In `apps/mobile/android/app/build.gradle.kts`, each product flavor sets
    `manifestPlaceholders["admobAppId"]` to its app id.
  - Add `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="${admobAppId}"/>` inside `<application>` of
    `apps/mobile/android/app/src/main/AndroidManifest.xml`.
  - Extend `apps/mobile/test/repo/` with `admob_app_id_test.dart`: each flavor's placeholder in the
    Gradle file equals `adIds[flavor].androidAppId`.
- [ ] T005 [P] iOS (contracts/platform-config.md "iOS"): Waits for the iOS release (owner's decision, 2026-11-04).
  - `apps/mobile/ios/Runner/Info.plist` gains `GADApplicationIdentifier = $(ADMOB_APP_ID)`,
    `NSUserTrackingUsageDescription` (the owner's Arabic text from T067, an English fallback in
    `InfoPlist.strings`) and the `SKAdNetworkItems` list from Google's, AppLovin's and Unity's
    current docs.
  - Each scheme's `Debug-`, `Release-` and `Profile-<flavor>` configuration in
    `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` sets `ADMOB_APP_ID` to that flavor's iOS app
    id.
  - `admob_app_id_test.dart` checks these too.
- [X] T006 [P] Widen the ad SDK guard in `apps/mobile/test/repo/` (the test that today bans an ad SDK
  under `lib/features/trip/`). `google_mobile_ads` and `gma_mediation_` imports may appear only in
  `lib/core/ads/gma_ads_gateway.dart` and `lib/bootstrap/` (adapter registration, if needed). Add
  `lib/core/ads/domain/` to the domain-import guard with what it may import: the economy domain's
  `op.dart` and `economy_refusal.dart`, and itself.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: game days, schema 6, the new operation, the bootstrap's `ads` block, the gateway, the
rules, `AdsService` and the checkpoint's consent and preload. Every story needs them.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Game days (research R9): tests first

- [X] T007 [P] Write `backend/apps/economy/tests/test_game_day_fixture.py`, a generator and its check:
  - `fixtures/economy/game_day.json` is a list of `{"ms": <int>, "date": "YYYY-MM-DD"}`;
  - it covers, for every year 2026–2035: one second either side of Cairo's midnight on the day
    before and after each DST switch; each switch instant; and 12:00 on the 15th of every month;
  - the test asserts every entry equals `apps.economy` `game_date(from_ms(ms)).isoformat()`;
  - `--regenerate` (an env flag `WASSAL_REGEN_GAME_DAY=1`) rewrites the file.

  Generate the file once and commit it. Run
  `uv run pytest apps/economy/tests/test_game_day_fixture.py` in `backend`.
- [X] T008 [P] Write `apps/mobile/test/core/economy/game_day_test.dart`: every entry of
  `fixtures/economy/game_day.json` (read the way `fuel.json`'s test reads it) gives
  `gameDayOf(ms) == date`. Add cases from before 2023 that document the rule's range, as skipped
  tests that say why.

### Game days: implementation

- [X] T009 Create `apps/mobile/lib/core/economy/domain/game_day.dart`:
  `String gameDayOf(int trustedMs)`, Cairo's date under Egypt's rule since 2023 (UTC+2; UTC+3 from
  the last Friday of April 00:00 local to the last Thursday of October 24:00 local). The header
  comment names research R9 and the fixture. T008 passes.

### Schema 6 and `ad_reward_seen` (data-model.md, contracts/economy-ops.md): tests first

- [X] T010 [P] Write `apps/mobile/test/core/economy/ad_reward_seen_test.dart` against the real
  economy:
  - `markAdRewardSeen` stores one `ad_reward_seen` row, payload `{"nonce": "<uuid>"}`, with no deltas
    and `reason`/`ref` null;
  - the projection is unchanged;
  - a second call with a new request id and the same nonce is `OpRefused(alreadyRecorded)` and stores
    nothing;
  - the same request id again is `OpApplied(repeated: true)`;
  - `adRewardSeen(nonce)` is true after, whatever the row's `sync_status`;
  - the fold after a rebuild skips it.
- [X] T011 [P] Write `apps/mobile/test/core/economy/ad_counts_test.dart`:
  - `adRewardsOn(fuelRefill, day)` counts only non-rejected `ad_reward` rows of that placement whose
    trusted `occurred_at_ms` has `gameDayOf == day` (rows at 23:59:59 and 00:00:00 Cairo fall on
    their own days, other placements don't count, a `rejected` row doesn't count);
  - `tripStarts()` counts every `trip_start` row.
- [X] T012 [P] Extend `apps/mobile/test/core/sync/` tests for `op_wire`: `ad_reward_seen` goes out as
  `{"op_type":"ad_reward_seen","payload":{"nonce":…}}`; an accepted answer changes nothing; the
  rollback toast never counts it (M06 `sync_engine.dart` line ~686's rule).
- [X] T013 Run `fvm dart run drift_dev make-migrations` after T014's table edits, and write
  `apps/mobile/test/drift/app/` cases for v5 → v6:
  - existing `ledger_ops` and `trip_intent` rows survive;
  - an `ad_reward_seen` row and a `trip_intent` row with `kind = 'ad_reward'` insert after the step
    and fail before it;
  - `server_info.ads` is null after the step.

### Schema 6 and `ad_reward_seen`: implementation

- [X] T014 In `apps/mobile/lib/core/storage/tables.dart`:
  - `ledger_ops.op_type`'s check gains `ad_reward_seen`;
  - `trip_intent.kind`'s check gains `ad_reward`;
  - `server_info` gains `TextColumn get ads => text().nullable()();` with the comment "The
    bootstrap's `ads` block, canonical JSON (M11 research R11)".

  Bump `schemaVersion` to 6 in `app_database.dart` and add `from5To6` to `upgradeSteps`, rebuilding
  both checked tables as M10's step 4→5 does. Commit the exported schema in `drift_schemas/app/`.
  T013 passes.
- [X] T015 In `apps/mobile/lib/core/economy/domain/op.dart` add `adRewardSeen('ad_reward_seen')` to
  `OpType`, with a comment naming B07 and M11 research R13.
  - In `apps/mobile/lib/core/economy/domain/` add the validator (refuse `alreadyRecorded` when the
    store has a row with that nonce).
  - In `fold.dart`, skip it; `stillValid` is always true for it.
- [X] T016 In `apps/mobile/lib/core/economy/economy.dart` and `economy_service.dart` add
  `markAdRewardSeen`, `adRewardSeen`, `adRewardsOn` and `tripStarts` (contracts/economy-ops.md), with
  their store queries in `drift_economy_store.dart` (the store remains the only writer).
  - Update every `Economy` fake under `apps/mobile/test/helpers/`.
  - T010 and T011 pass.
- [X] T017 In `apps/mobile/lib/core/sync/`, send `ad_reward_seen` through `op_wire.dart`, and leave
  it out of the rollback toast in `sync_engine.dart`, beside `_counterPlacements`. Add
  `SyncTrigger.adReward`. T012 passes.

### The bootstrap's `ads` block (research R11): tests first

- [X] T018 [P] Write `apps/mobile/test/core/sync/bootstrap_ads_test.dart`:
  - B07's example block (contracts/api.md) parses to `AdsBlock(piggyAvailable: true, unseen: [one
    PiggyGrant with nonce, jenehat 30, bonat 2, grantedAtMs])`;
  - a bootstrap without `ads` parses as `available: false`, `unseen: []`;
  - more than 5 entries keep all that came (the server caps at 5);
  - a malformed entry fails like other wire errors (`WireObject`'s path in the message);
  - `DriftAccountStore` round-trips it through `server_info.ads`, and `serverInfoProvider.ads`
    reads it back offline.

### The bootstrap's `ads` block: implementation

- [X] T019 In `apps/mobile/lib/core/sync/domain/wire/bootstrap.dart` add `AdsBlock` and `PiggyGrant`
  (data-model.md "`AdsBlock`") and `BootstrapSnapshot.ads`. Write and read the block in
  `apps/mobile/lib/core/account/drift_account_store.dart` and `ServerInfo`. Add `adsBlockProvider` in
  `apps/mobile/lib/core/sync/sync_providers.dart`, beside `dailyBlockProvider`. T018 passes.

### The rules (data-model.md "Rules"): tests first

- [X] T020 [P] Write `apps/mobile/test/core/ads/ad_offer_test.dart`, a table over `adOffer(placement,
  AdFacts)` for every row of data-model.md's rule:
  - `result_double`: hidden on failed, unpaid, already doubled, and tutorial trips 1–2; offered on
    tutorial trip 3;
  - `trip_revive`: hidden when revived or not revivable;
  - `traffic_jam`: hidden with stock, or with one ad used this trip;
  - every placement except `result_double` hidden before the tutorial is done;
  - `fuel_refill`: hidden with a full tank, `LimitReached` at 3 today, offered at 2;
  - `morning_piggy`: hidden with no block, `available: false`, a stale day, or attempted today;
  - `NeedsNetwork` offline, `NotReady` with nothing loaded, `Offered` otherwise.
- [X] T021 [P] Write `apps/mobile/test/core/ads/interstitial_due_test.dart`, a table over
  `interstitialDue`:
  - trips 9 → false and 10 → true (with 10 since the last);
  - `trips − lastInterstitialAt` 2 → false, 3 → true;
  - `lastRewardedAt == trips` → false;
  - tutorial not done, `removeAds`, `noInterstitials`, offline and not loaded → each false;
  - grace and cadence read from the arguments (tunables), with 0 and 1 edge values.
- [X] T022 [P] Write `apps/mobile/test/core/ads/piggy_plan_test.dart`: the waits are 1000, 2000 and
  4000 ms, so the asks fall at 1 s, 3 s and 7 s after the reward. Add the outcome reducer:
  `NotYet` ×3 → `gaveUp`; `Granted` at any ask → `granted`; `Refused` → `refused`.

### The rules: implementation

- [X] T023 Create `apps/mobile/lib/core/ads/domain/ad_offer.dart` (`AdFacts`, `AdOffer` sealed:
  `Offered`, `NotReady`, `LimitReached`, `NeedsNetwork`, `Hidden`), `interstitial_due.dart`,
  `piggy_plan.dart` and `ad_timing.dart`. The last holds the named constants of research R16: expiry
  55 minutes; back-off 30, 60 and 120 s; with a comment that they are SDK hygiene, not tunables
  (constitution VIII). T020–T022 pass.

### The gateway (contracts/ads-gateway.md)

- [X] T024 Create `apps/mobile/lib/core/ads/ads_gateway.dart`: `AdsGateway`, `ShowOutcome`
  (`Rewarded`, `Closed`, `ShowFailed`), `Readiness`, `RequestConfig`, `PiggyVerification`, and
  `TripRunningProbe` (a `ValueListenable<bool>`).
- [X] T025 [P] Create `apps/mobile/test/helpers/fake_ads_gateway.dart`:
  - scripted outcomes per unit, scripted readiness, a call log;
  - `failOnCallWhileRunning(TripRunningProbe)` throws a `TestFailure` naming the call when the probe
    reads true;
  - a scripted consent result (`canRequestAds`, `formShown`).
- [X] T026 Create `apps/mobile/lib/core/ads/gma_ads_gateway.dart`, the only `google_mobile_ads`
  import (research R1, R5, R6, R16):
  - `start`: UMP `requestConsentInfoUpdate`, `loadAndShowConsentFormIfRequired`, `canRequestAds`,
    then `MobileAds.instance.updateRequestConfiguration(...)` and `initialize()`;
  - the configuration comes from the pure `adRequestConfig()` in
    `lib/core/ads/domain/request_config.dart` (analysis G1). It returns `RequestConfig(rating: T,
    childDirected: false, underAgeOfConsent: false, testDeviceIds: [])`. The gateway only maps it
    onto `RequestConfiguration(maxAdContentRating: MaxAdContentRating.t,
    tagForChildDirectedTreatment: TagForChildDirectedTreatment.no, tagForUnderAgeOfConsent:
    TagForUnderAgeOfConsent.no)`, with one `switch` per field and no defaults of its own;
  - `load` and `show` for `RewardedAd` and `InterstitialAd`, with one held ad per unit;
  - expiry and back-off from `ad_timing.dart`;
  - the piggy's `ServerSideVerificationOptions(userId, customData)`;
  - `show` resolving after dismissal, `Rewarded` once `onUserEarnedReward` fired.

  It has no unit test (the plugin needs a device); §3 of quickstart.md covers it.

### `AdsService`, the checkpoint and preloads (contracts/ads-gateway.md): tests first

- [X] T027 Write `apps/mobile/test/core/ads/ads_service_test.dart` over `FakeAdsGateway` and the real
  economy:
  - `ensureReady` calls `start` once per launch and never while the probe reads true;
  - `watch` table: `Rewarded` → `applyAdReward` with one request id even on a double tap →
    `RewardApplied`; `Closed` and `ShowFailed` → `NoReward` and nothing stored; a refusal after the
    ad (tank already full) → `RewardRefused(tankFull)`;
  - `watch` writes `pref.ads_last_rewarded_trip = tripStarts()` on `Rewarded` only;
  - `fuel_refill`'s daily count is checked before the show and again before the apply;
  - `offer` reads caches only, with no gateway call;
  - `preloadForNextTrip` loads the rewarded units the next trip and result may offer, and none
    before tutorial trip 3;
  - `events` emits `offered`, `rewarded`, `loadFailed`;
  - `adRequestConfig()` is rating T, not child-directed, not under the age of consent, with no test
    devices (spec FR-025, research R5). `FakeAdsGateway.start` records the config it got, and the
    service passes exactly that one.

### `AdsService`: implementation

- [X] T028 Create `apps/mobile/lib/core/ads/ads_service.dart` (`AdsService` and its implementation)
  and `apps/mobile/lib/core/ads/ads_providers.dart`:
  - `adsGatewayProvider` (`GmaAdsGateway` in the app, overridden in tests);
  - `adsServiceProvider` (keep-alive);
  - `tripRunningProbeProvider`;
  - `adsReadinessProvider(AdPlacement)` for the buttons.

  It reads `SettingsStore` for the two prefs (data-model.md "Device preferences"), the tunables
  through `ConfigSource`, `entitlementsProvider`, `isOnlineProvider`, `firstSessionProvider`,
  `adsBlockProvider` and `trustedClockProvider`. T027 passes.
- [X] T029 Create `apps/mobile/lib/core/ads/ads_checkpoint.dart`: `AdsCheckpoint implements
  BetweenTripsCheckpoint`.
  - `pass()` takes no trip id (M08's seam), so it decides from `firstSessionProvider` (analysis U2):
    ads may start when `session.tutorialDone`, or when at least two of `session.facts.tutorialTrips`
    are finished (`isFinished(session.facts.progress[trip])`). That means the next start is tutorial
    trip 3 or later. Put this in a pure function, `adsMayStart(FirstSession)`, in
    `lib/core/ads/domain/`.
  - When ads may start, `pass()` runs `ensureReady()`, then `preloadForNextTrip()`. Otherwise it
    returns at once with no gateway call.
  - The interstitial comes in US4 (T058).
  - Override `betweenTripsCheckpointProvider` in the app's provider scope in
    `apps/mobile/lib/bootstrap/`. The `tripAdOffersProvider` override is T040's.
  - **The path is verified** (analysis U1): the tutorial result's continue
    (`result_screen.dart` `_again` → `startNextTrip`), Home's start button, Lines and the apartment
    all reach `startNextTrip`, which calls `pass()` before M07's scene and fuel-lesson redirects. If
    a later change adds a start that bypasses `startNextTrip`, T054 fails.
  - Add tests to `ads_service_test.dart` for `adsMayStart`: false with 0 or 1 tutorial trips
    finished, true with 2, true when done. The checkpoint before tutorial trip 2 calls nothing;
    before trip 3 it starts the SDK and preloads `result_double`.
- [X] T030 Have the trip controller set `tripRunningProbe` from its phase:
  `apps/mobile/lib/features/trip/application/trip_controller.dart`, true exactly while the engine's
  status is `running`. Extend `apps/mobile/test/features/trip/trip_controller_test.dart`: the probe
  follows start, pause, resume, fail, finish and a resume at launch.

### Strings and the debug panel

- [X] T031 [P] Add contracts/ads-gateway.md "Strings" to `apps/mobile/lib/l10n/app_ar.arb`, with
  plurals for `refillAdLeft`. Use `piggyUsed` and `piggyArrived*` from the brief's drafts until T064.
  The ARB key-uniqueness guard passes.
- [X] T032 [P] Add an «Ads» card to the debug panel (`apps/mobile/lib/features/dev/`), in dev and
  staging builds only:
  - consent status and `canRequestAds`;
  - each unit's readiness;
  - the last piggy reference, with a copy button for `ads_dev_callback --nonce`;
  - a consent test-geography switch (EEA / not EEA) and «reset consent» (dev only);
  - «show <placement>» buttons (spec FR-029), disabled while a trip runs.

**Checkpoint**: the SDK, rules, service and storage are in place; stories can start.

---

## Phase 3: User Story 1 - Double the pay on the result (Priority: P1) 🎯 MVP

**Goal**: «اقبض ×٢» under the pay; one ad doubles it once (spec US1, FR-010, FR-011, FR-007a).

**Independent Test**: finish a paying trip, watch the ad: the wallet grows by exactly the pay, one
`ad_reward` `result_double` is stored, and the offer is gone (spec US1).

### Tests for User Story 1 ⚠️

- [X] T033 [P] [US1] Write `apps/mobile/test/features/result/result_double_offer_test.dart`:
  - each `adOffer` state draws its `RewardedAdButton` state («اقبض ×٢» / «+١٧٠ بدل ٨٥»; not ready;
    offline);
  - hidden for failed, unpaid and doubled results and tutorial trips 1–2;
  - a reward makes the result's pay show 170 through the existing `doubled` read, and the offer go;
  - `Closed` changes nothing;
  - the decline link is ≥ 44×44 and hides the offer for this result only.
- [X] T034 [P] [US1] Extend `apps/mobile/test/design/result_layout_test.dart` and the result goldens
  (`test/goldens/`) with the offer's ready and not-ready states, in both digit styles.

### Implementation for User Story 1

- [X] T035 [US1] Create `apps/mobile/lib/features/result/presentation/result_double_offer.dart`
  (contracts/seams.md "`ResultDoubleOffer`") and override `resultDoubleSlotProvider` in the app scope.
  Update `test/design/samples/result.dart` to draw it. T033 and T034 pass.

**Checkpoint**: US1 works alone with a scripted gateway.

---

## Phase 4: User Story 2 - Revive a failed trip or buy time with an ad (Priority: P1)

**Goal**: the ad revive on the Fail card; the ad «زحمة» in the booster card (spec US2, FR-008,
FR-009, FR-012–FR-014; research R7, R8).

**Independent Test**: with the spy gateway, revive by ad and use the ad «زحمة»: each reward applies
once, every call happens paused or failed, and the spy never fires (spec US2).

### Tests for User Story 2 ⚠️

- [X] T036 [P] [US2] Extend `apps/mobile/test/features/trip/trip_controller_test.dart` with
  `FakeAdsGateway.failOnCallWhileRunning`:
  - **`reviveWithAd`:** `Rewarded` → the economy's `trip_revive` row, then `Revive`, with reputation
    40%; `Closed` → no change; already revived → not offered; the kill point `adRewardApplied`
    recovers on reopen through `unfinished.revived` (M02 R7).
  - **`trafficJamWithAd`:** from `boosterCard` only, `Rewarded` → the `trip_intent` row (kind
    `ad_reward`, booster `traffic_jam`), then `ad_reward` `traffic_jam`, the engine's booster
    command, the row cleared, then the pause card; `Closed` → the card stays; the kill points
    `adIntentWritten` and `adRewardApplied` recover once each; a second ad in the same trip is not
    offered.
  - The background during an ad (an app-lifecycle pause) keeps the trip paused.
  - A resume at launch makes no gateway call.
- [X] T037 [P] [US2] Write `apps/mobile/test/core/ads/ads_trip_offers_test.dart`:
  - `isOffered` reads caches only, and is callable while the probe reads true;
  - `show` while the probe reads true fails;
  - `isOffered(trafficJam)` is true only with stock 0 and `trafficJamAds == 0`.
- [X] T038 [P] [US2] Widget tests and goldens:
  - `FailureCard` with the ad revive in `adSlotKey` above the BONAT revive (ready, not ready,
    offline);
  - `BoostersRow` with the «إعلان» badge;
  - `BoosterCard` for `traffic_jam` with the ad button above «اشتري واستعمل».

  In `apps/mobile/test/features/trip/presentation/` and `test/goldens/`.
- [X] T039 [P] [US2] Remove the M11 skip (box 12) in `apps/mobile/test/design/fail_layout_test.dart`.
  Make `trip_events_layout_test.dart` check the «زحمة» ad badge. Update `test/design/samples/fail.dart`
  and `trip_events.dart` to draw them.

### Implementation for User Story 2

- [X] T040 [US2] Create `apps/mobile/lib/core/ads/ads_trip_offers.dart` (contracts/seams.md
  "`TripAdOffers`") and override `tripAdOffersProvider`. Edit
  `apps/mobile/lib/features/trip/application/trip_ad_offers.dart`'s doc comments to the new rule:
  `isOffered` at any time, `show` paused or failed only.
- [X] T041 [US2] In `apps/mobile/lib/features/trip/application/trip_controller.dart`, add
  `reviveWithAd()` and `trafficJamWithAd()` (contracts/seams.md):
  - `PauseReason.ad`;
  - the kill points `adIntentWritten` and `adRewardApplied` in
    `lib/features/trip/data/trip_kill_point.dart`;
  - the `trip_intent` row through `drift_trip_records.dart`, and its recovery at open beside the
    `use_booster` rows.

  `TripView` gains `reviveAdOffered`, and the booster slot's `adOffered` comes from `isOffered`
  (`lib/features/trip/domain/projection.dart`). T036 and T037 pass.
- [X] T042 [US2] UI:
  - `apps/mobile/lib/features/trip/presentation/cards/failure_card.dart` fills `adSlotKey` with
    `RewardedAdButton` («صالح الركاب»);
  - `cards/booster_card.dart` adds the ad button for `traffic_jam`;
  - `dashboard/boosters_row.dart` draws the «إعلان» badge (`TripEvents`).

  Remove "M11" placeholders from their comments. T038 and T039 pass.
- [X] T043 [US2] Edit `specs/008-m02-trip-screen/contracts/trip-controller.md` "Ads" to research R7's
  rule and the two new methods.

**Checkpoint**: US1 and US2 work; the spy holds.

---

## Phase 5: User Story 3 - The morning piggy (Priority: P1)

**Goal**: the banner, the ad with SSV, the polling, the cards and `ad_reward_seen` (spec US3,
FR-015–FR-019; research R11–R14).

**Independent Test**: against the dev stack, the ad carries the player id and a fresh reference; the
app asks until granted; the wallet rebases; the banner hides; the reward is confirmed and never
shows again (spec US3).

### Tests for User Story 3 ⚠️

- [X] T044 [P] [US3] Write `apps/mobile/test/core/ads/piggy_api_test.dart` over a fake `AuthorizedApi`:
  - 200 granted → `Granted(30, 2, …)`, with `wallet` ignored;
  - 200 refused with each reason → `Refused`;
  - 404 → `NotYet`;
  - timeouts, network errors and 5xx → `NotYet`;
  - the path is `/v1/ads/rewards/<nonce>`.
- [X] T045 [P] [US3] Write `apps/mobile/test/core/ads/piggy_service_test.dart` with `fake_async`:
  - the verification is `userId = player_id` and
    `customData = '{"placement":"morning_piggy","nonce":"<uuid4>"}'` exactly, with a new nonce per
    ad;
  - `Closed` → no polling, banner stays;
  - asks at 1 s, 3 s and 7 s;
  - granted at ask 2 → no third ask, `ad_reward_seen` queued, `SyncTrigger.adReward` requested;
  - refused → `ad_reward_seen` queued;
  - gave up → no op queued;
  - the banner hides for the day after the reward in every case;
  - `pref.ads_last_rewarded_trip` is written;
  - no call while the probe reads true (the piggy is on Home, but the guard holds).
- [X] T046 [P] [US3] Write `apps/mobile/test/features/home/piggy_banner_test.dart`:
  - each row of contracts/seams.md "`PiggyBanner`": hidden (no block, `available: false`, a stale
    day, attempted today), ready, not ready, offline (`HomeStates` row 7), asking;
  - the outcome cards open for granted, refused and gave up.
- [X] T047 [P] [US3] Write `apps/mobile/test/features/home/piggy_arrival_test.dart`:
  - due with an unseen entry and no local `ad_reward_seen`;
  - not due after its close (the op is stored, even unsynced, while bootstrap still lists it);
  - rank 40 after the due scene and the name sheet;
  - one per arrival when two are unseen.
- [X] T048 [P] [US3] Layout and goldens: the piggy in `c_home_layout_test.dart` (row 6) and
  `home_states_layout_test.dart` (row 7), with `test/design/samples/c_home.dart` and
  `home_states.dart` overriding `morningPiggySlotProvider` with the real banner in a scripted state.

### Implementation for User Story 3

- [X] T049 [US3] Create `apps/mobile/lib/core/ads/piggy_api.dart` (`PiggyLookup`, over `AuthorizedApi`,
  contracts/economy-ops.md "The piggy's lookup") and `piggy_service.dart` (research R12: `watch()`,
  `PiggyAttempt` per game day, the outcomes stream). Providers go in `ads_providers.dart`. T044 and
  T045 pass.
- [X] T050 [US3] Create `apps/mobile/lib/features/home/presentation/piggy_banner.dart`, a variant of
  `RewardedAdButton` per HANDOFF Home row 6. Its non-token lip (#EED38A) goes in
  `lib/core/theme/tokens/design_extras.dart` as `DesignExtras.piggyLip`, beside the other values the
  design draws outside the tokens. Don't hand-edit the generated token files: the repo guard checks
  them against `docs/design/tokens.json` (analysis U3). Override `morningPiggySlotProvider`. T046
  and T048 pass.
- [X] T051 [US3] Create `apps/mobile/lib/features/home/presentation/piggy_cards.dart` (`PiggyArrived`,
  `PiggyUsed`, `PiggyLater`, built from contracts/design-briefs.md until T064) and
  `apps/mobile/lib/features/home/application/piggy_arrival.dart` (`PiggyArrival`, rank 40). Add it to
  `arrivalItemsProvider` in `arrival_queue.dart` after M07's two. Its button records
  `markAdRewardSeen`. T047 passes.
- [X] T052 [US3] Write `apps/mobile/test/backend/piggy_test.dart` (tag `backend`, quickstart §4.5).
  Against `WASSAL_E2E_API`:
  - create a player and watch with a fake gateway;
  - sign the callback by running the command in the env var `WASSAL_E2E_ADS_CALLBACK` with
    `Process.run`, appending `--user <player_id> --nonce <reference>` (analysis U4). Locally it is
    `uv run --directory ../../backend manage.py ads_dev_callback`. Set it in CI's `sync-e2e` job in
    `.github/workflows/mobile.yml` to the job's `docker compose exec -T api python manage.py
    ads_dev_callback` line. The job's first run also creates the dev key; restart the API once, as
    B07 quickstart §2 says. Without the variable, the test skips, saying why;
  - expect granted within 7 s and the wallet rebased after the pass;
  - expect `unseen` emptied after `ad_reward_seen` syncs.

**Checkpoint**: US1–US3 work.

---

## Phase 6: User Story 6 - Consent before the first ad (Priority: P1)

**Goal**: UMP before any request; no form before tutorial trip 3; non-personalised ads on refusal;
ATT through UMP on iOS (spec US6, FR-023–FR-026, SC-006, SC-008; research R5, R6).

**Independent Test**: on a fresh install with the EEA test geography, reach the first ad: the form
shows first and no request is sent before it closes (spec US6).

### Tests for User Story 6 ⚠️

- [X] T053 [P] [US6] Extend `ads_service_test.dart` with consent:
  - no `start` during the opening and tutorial trips 1–2;
  - `start` at the checkpoint before trip 3;
  - `canRequestAds: false` → no load, and every offer `NotReady`;
  - `start` runs once per launch;
  - a form shown and closed → loads follow;
  - offline `start` passes at once with nothing loaded.
- [X] T054 [P] [US6] Extend M07's `apps/mobile/integration_test/first_session_test.dart` (headless)
  with a recording `FakeAdsGateway`:
  - no gateway call before the checkpoint before tutorial trip 3, and none while any trip runs
    (SC-008);
  - `ensureReady` (the gateway's `start`) happens on trip 2's result → continue path, before
    `/trip/<tutorial trip 3>` opens;
  - trip 3's result shows the ×2 offer (analysis U1).
- [X] T055 [P] [US6] Write `apps/mobile/test/repo/ad_privacy_test.dart`: `player_id` is passed to the
  gateway only in `PiggyVerification` (a source scan of `lib/core/ads/` for `playerId` uses),
  FR-026.

### Implementation for User Story 6

- [X] T056 [US6] Finish the consent path in `gma_ads_gateway.dart` and `ads_service.dart` (research R6):
  - the debug panel's test geography sets `ConsentDebugSettings` in dev only;
  - «reset consent» calls `ConsentInformation.instance.reset()` in dev only;
  - the request configuration of research R5 is set before `initialize()`.

  T053–T055 pass.

**Checkpoint**: consent holds; all P1 stories are done.

---

## Phase 7: User Story 4 - Interstitials between trips, within the rules (Priority: P2)

**Goal**: the interstitial at the checkpoint only, by glossary §3.4 (spec US4, FR-020–FR-022;
research R10).

**Independent Test**: scripted histories decide "show" or "pass" exactly as §3.4 says; on a device,
one shows only at the checkpoint (spec US4).

### Tests for User Story 4 ⚠️

- [X] T057 [P] [US4] Extend `ads_service_test.dart` with `betweenTrips()`:
  - due + loaded → `show(interstitial)`, then `pref.ads_last_interstitial_trip = trips` and a reload;
  - `ShowFailed` → no write (FR-022);
  - not due → no call;
  - `remove_ads` bought mid-session → the next checkpoint passes;
  - from Home, «مشوار تاني», Lines and the apartment's card the checkpoint is called once per start,
    and never after «اطلع» (extend M08's `start_next_trip` tests and M09's and M10's card tests to
    assert the checkpoint call count).

### Implementation for User Story 4

- [X] T058 [US4] In `ads_checkpoint.dart` and `ads_service.dart`, finish `betweenTrips()` (contracts/ads-gateway.md
  "Interstitial"), reading `ads_interstitial_grace_trips` and `ads_interstitial_every_n_trips`
  through `ConfigSource`, and emit `interstitialShown`. T057 passes.

**Checkpoint**: US4 works.

---

## Phase 8: User Story 5 - Free refill with an ad (Priority: P2)

**Goal**: `FuelRefillAdOffer` on the out-of-fuel card and the placeholder fuel sheet, 3 a day (spec
US5, FR-002, FR-030; research R9, R17).

**Independent Test**: with an empty tank, three refills in one game day fill the tank; the fourth is
refused on the phone; the server accepts the three (spec US5).

### Tests for User Story 5 ⚠️

- [X] T059 [P] [US5] Write `apps/mobile/test/features/fuel/fuel_refill_ad_offer_test.dart`:
  - ready with «باقيلك ٣ النهارده», 2, then 1;
  - limit reached («خلصت النهارده», 45%, no lip) at 3;
  - not ready; offline; hidden with a full tank;
  - the reward fills the tank once and calls `onFilled`;
  - a day change (scripted trusted clock crossing Cairo midnight) restores 3;
  - **the BONAT refill is always beside the ad** (constitution IX, analysis C1): «فوّل الخزان» with a `PriceChip` «٣٠ بون»
    from the catalog's `refuel_full` price shows in every ad state (ready, not ready, limit, offline).
    It buys through `buy(kind: SkuKind.fuel, skuId: refuelFullSku)` with its own held request id;
    short of BONAT it shows «ناقصك …»; a write failure says so, and a retry reuses the id.
- [X] T060 [P] [US5] Goldens for the offer, with its BONAT refill, on `NoFuelCard` and on the
  placeholder sheet, in both digit styles (`test/goldens/`). Once T063's `NoFuelAd` and
  `NoFuelAdLimit` boards land, T064 adds their layout tests.
- [X] T061 [P] [US5] Write `apps/mobile/integration_test/fuel_ad_test.dart`, headless and offline
  except for the fake gateway (constitution XIII "empty fuel through an ad"):
  1. empty the tank;
  2. start a trip: the out-of-fuel card;
  3. the refill ad;
  4. the trip starts;
  5. repeat to the cap;
  6. the fourth shows «خلصت النهارده» with the BONAT refill beside it.

### Implementation for User Story 5

- [X] T062 [US5] Create `apps/mobile/lib/features/fuel/presentation/fuel_refill_ad_offer.dart`
  (contracts/seams.md). The widget draws the ad and the BONAT refill side by side
  (`buy(kind: SkuKind.fuel, skuId: refuelFullSku)`, `spend_rules.dart`), so the BONAT option is next
  to the ad wherever it is placed (constitution IX). Place it in
  `apps/mobile/lib/features/trip/presentation/cards/no_fuel_card.dart`, above «البنزين» and the way
  back, with `onFilled` retrying the start through the controller. Place it in the `/shop/fuel`
  placeholder page (a small `fuel_placeholder_page.dart` in `lib/features/fuel/`, routed from
  `lib/core/routing/router.dart` in place of the placeholder screen). T059–T061 pass.

**Checkpoint**: every placement works.

---

## Phase 9: The Owner's Boards and Ids

**Purpose**: what only the owner can provide (plan "Owner actions"). Phases 3–8 build from the brief
and the dev ids, so only these checks wait.

- [X] T063 **Owner:** draw `PiggyArrived`, `PiggyUsed`, `PiggyLater`, `NoFuelAd`, `NoFuelAdLimit`
  and `BoosterAdCard` on the Claude Design canvas, and export them into
  `docs/design/{screens,png,boxes}/`, or hand the export to Claude (contracts/design-briefs.md;
  `docs/owner-actions.md` section 018, item 1).

  Done on 2026-11-03: drawn in the canvas row «الإعلانات», exported on `design/m11-ad-boards`
  (`2cc4786`), and the 25 files brought onto `018-m11-ads`. The choices and the two copy changes
  are in contracts/design-briefs.md "As drawn". PiggyUsed and PiggyLater are toasts with no button,
  so T064's `piggy_cards.dart` builds those two as toasts.
- [X] T064 After T063, align the code to the boards: `piggy_cards.dart`, `fuel_refill_ad_offer.dart`
  with `no_fuel_card.dart`, and `booster_card.dart`'s ad button.
  - Add `test/design/samples/piggy_states.dart` and `ad_states.dart`, with
    `test/design/piggy_states_layout_test.dart` and `ad_states_layout_test.dart` checking the six
    boards, and their goldens (both digit styles).
  - move the boards' copy into `app_ar.arb`;
  - write "As drawn (date)" in `contracts/design-briefs.md`;
  - add the boards to M11's row of `docs/delivery-plan.md` "Design sources".
- [X] T065 **Owner:** create the AdMob ad units: rewarded × 5 (one per placement; `morning_piggy` is
  B07's existing unit) and one interstitial, for Android, and iOS when it sells. Send the ids.
  Claude puts them in `ad_ids.dart` and the per-flavor app ids (T003–T005). T002 then passes.
  Done for Android on 2026-11-04; iOS keeps the sample ids until it launches (owner's decision).
- [ ] T066 **Owner:** in AdMob, set up AppLovin and Unity Ads mediation; register the test phone as a
  test device; turn on Privacy & messaging's GDPR form and the IDFA explainer (research R2, R4, R6).
- [ ] T067 **Owner:** the Arabic `NSUserTrackingUsageDescription` text for T005. Waits for the iOS release (owner's decision, 2026-11-04).

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: the documents, the guides, the size, the full checks, the reviews and the owner's list.

- [X] T068 [P] Update `docs/architecture-mobile.md`:
  - §15.1: the real API (contracts/ads-gateway.md), the consent order, `ad_reward_seen` through the
    economy, and the wallet through the sync pass;
  - §24.3: resolved (research R2);
  - §5: `lib/core/ads/`, `lib/features/fuel/`;
  - §12: `ad_reward_seen` and schema 6.
- [X] T069 [P] Update `docs/architecture-backend.md` §22.8: resolved (research R5), and §8.4 step 7
  on how the phone moves the wallet (research R12).
- [X] T070 [P] Update `docs/delivery-plan.md`:
  - step 8's "Resolve" marks mobile §24.3 and backend §22.8 settled;
  - "Handed on from B07" gets the wallet note;
  - add the Progress line for `018-m11-ads` when it merges.
- [X] T071 [P] Update `apps/mobile/CLAUDE.md`:
  - M11 in "What the app has";
  - the widened ad SDK guard and the `lib/core/ads/domain/` import list;
  - schema 6 and its writers;
  - the new integration test's command;
  - the debug panel's «Ads» card;
  - the ad ids table, and where the app ids sit per flavor.
- [X] T072 [P] Update the root `CLAUDE.md`'s features line with "018 M11 ads".
- [ ] T073 Measure the dev and prod release APK sizes before and after (`fvm flutter build apk
  --flavor prod --release --analyze-size`). Record them in the PR; the download stays < 80 MB.
  Dev release, measured 2026-11-04 (`--split-per-abi`, arm64 being what a Play download is): 33.9 MB
  before (27fd524), 39.5 MB after, so ads add 5.6 MB; the universal APK is 96.5 MB before, 104.0 MB
  after. Prod can't be built yet: `checkBundledPack` refuses until a promoted pack is bundled
  (`docs/runbooks/content-publishing.md` §3). Open until then.
- [X] T074 Run quickstart §1, §2 and §6 in full on the VPS: `--exclude-tags backend`, the drift tests,
  `fuel_ad_test.dart`, the first-session test, the design tests, the coverage gate ≥ 80%, analyze and
  format.
- [X] T075 Run quickstart §4 against the dev stack (the `backend`-tagged `piggy_test.dart`), and
  `economy_check`.
- [X] T076 [P] Code review with the flutter-reviewer agent over the change set, and a security review
  (the player id to the ad network, the SSV custom data, prefs holding no token). Fix CRITICAL and
  HIGH.
- [X] T077 Add M11's section to `docs/owner-actions.md`, and its row to "Open now":
  - before merge: T063, T065–T067;
  - after merge: quickstart §3 on the Redmi Note 7 (dev); quickstart §5 (staging with real units,
    SC-004); Play Console's ads and data-safety declarations and the 13+ target audience; B07 item 4
    (production's callback URL) before the release.
- [ ] T078 Run quickstart §3 on the owner's phone (dev build, test ads), steps 1–8, with the owner
  watching, and record the outcome in `docs/owner-actions.md`.
- [X] T079 Check `docs/design/README.md` "Checking a screen against the design" for every changed
  board: Fail, Result, Home and HomeStates (the piggy), `TripEvents`, and the booster card's
  `States` layout.
- [X] T081 Settings' way back to the consent form (owner's decision, 2026-11-04): `AdsGateway`'s
  `privacyOptionsRequired`, `showPrivacyOptions` and `mayRequestAds`, `AdsService`'s wrappers, and a
  row in `settings_screen.dart` shown only where UMP requires it. Tests:
  `test/core/ads/ads_service_test.dart`, `test/features/settings/settings_ad_privacy_test.dart`. The
  real form can only be checked on the phone, once the European message is published (T078).
- [X] T080 Run Codemagic's `ios-dev-unsigned` once on the branch: it builds with the Swift Packages and
  no Podfile (research R1, R2). Record the build link in the PR.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none. T003's staging and prod ids wait on T065, but the placeholders let
  everything else proceed.
- **Foundational (Phase 2)**: after Setup. It blocks every story.
- **US1 (Phase 3)**, **US2 (Phase 4)**, **US3 (Phase 5)**, **US6 (Phase 6)**: after Phase 2; they are
  independent of each other.
- **US4 (Phase 7)**: after Phase 2; it extends the checkpoint (T029).
- **US5 (Phase 8)**: after Phase 2.
- **Owner (Phase 9)**: in parallel with everything. T064 waits on T063; T002's merge gate waits on
  T065.
- **Polish (Phase 10)**: after the stories. T078 and T080 can run once US1–US5 are in.

### Within each phase

- Tests are written first and fail before implementation.
- Order: game day → schema → operation → economy reads → bootstrap → rules → gateway → service →
  checkpoint.
- `trip_controller.dart` is touched by T030 and T041. Do them in that order.

### Parallel opportunities

- Setup: T002–T006 together after T001.
- Foundational: T007, T008, T010–T012, T018, T020–T022 and T025 are separate files, so they can be
  written together. Implementation then follows the order above.
- After Phase 2: US1, US2, US3 and US5 touch different features (`result/`, `trip/`, `home/`,
  `fuel/`), so they can run in parallel. US6 and US4 touch `ads_service.dart` and
  `ads_checkpoint.dart`, so run them one after the other.

## Parallel Example: after Phase 2

```text
Task: T033 [US1] result_double_offer_test.dart
Task: T036 [US2] trip_controller_test.dart ads cases
Task: T044 [US3] piggy_api_test.dart
Task: T059 [US5] fuel_refill_ad_offer_test.dart
```

## Implementation Strategy

### MVP first

1. Phases 1–2.
2. US1 (×2): the main rewarded income, from day one. Check it on the phone with test ads.
3. US2, US3, then US6, which completes the P1 set and step 8's "done when" for SSV and consent.
4. US4 and US5.
5. The owner's boards and ids, then polish.

### Notes

- Nothing here changes the engine, the parity fixtures or the content schemas.
- Staging and prod ids are placeholders until T065. Without them T002 fails, so the PR can't merge.
- Never run `flutter test` on the laptop. Use `rtest` on the VPS.
