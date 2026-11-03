# Research: Ads Integration (M11)

Every **NEEDS CLARIFICATION** this feature touches is resolved here or in the spec's Clarifications:

- mobile §24.3, the mediation networks: R2, and spec Clarifications;
- backend §22.8, the age rating and the ad content rating: R5, and spec Clarifications.

The spec's one outstanding item, the piggy banner shown from a state of an earlier day, is R11.

## R1. The SDK and its version

- **Decision:** `google_mobile_ads` ^9.2.0. It holds the ads, the User Messaging Platform (UMP)
  consent API (`ConsentInformation`, `ConsentForm`) and the request configuration
  (`maxAdContentRating`, `tagForChildDirectedTreatment`, `tagForUnderAgeOfConsent`).
- **Rationale:** It is Google's own plugin. Version 8.0.0 added Swift Package Manager support,
  which this app needs because it has no Podfile (apps/mobile/CLAUDE.md "Builds"). It asks for
  Flutter ≥ 3.38.1, and the app pins 3.47.7. On Android it needs `minSdk` 21, and the app has 24.
- **Alternatives considered:** a community plugin, rejected: no mediation adapters and no UMP.
  Raw platform channels to the native SDKs, rejected: more code for the same thing.

## R2. Mediation (resolves mobile §24.3)

- **Decision:** AdMob bidding with AppLovin and Unity Ads, through Google's adapter plugins
  `gma_mediation_applovin` ^2.6.4 and `gma_mediation_unity` ^1.11.0. Both require
  `google_mobile_ads` ^9.1.0, and both added Swift Package Manager support (2.6.3 and 1.10.0). The
  owner sets up the networks in the AdMob console (owner action).
- **Rationale:** The owner's choice (spec Clarifications). Two strong bidding networks fill the
  Egyptian market with light adapters. Each adapter is a plugin, so a later network needs a release.
- **Alternatives considered:** all four candidates (a larger app, more console work); AdMob alone
  (simplest, but less competition for each impression).

## R3. Where the code lives

- **Decision:** a new core module, `lib/core/ads/`:
  - `domain/`: pure rules. The interstitial decision (`interstitialDue`), the cap checks
    (`adOffer`) and the piggy's polling plan, with no Flutter or plugin import (the repo guard
    lists the folder).
  - `ads_gateway.dart`: the interface the constitution names (`AdsGateway`).
  - `gma_ads_gateway.dart`: the only file that imports `google_mobile_ads`.
  - `ads_service.dart`: offers, caps, history and rewards, over the gateway and the economy.
  - `piggy_service.dart`: the morning piggy.

  The feature folders fill the seams M02 and M08 left (contracts/seams.md). No ad SDK import goes
  under `lib/features/`. The guard that bans one under `lib/features/trip/` widens to
  `lib/features/` and `lib/core/` except `lib/core/ads/gma_ads_gateway.dart`.
- **Rationale:** Constitution "Architecture boundaries": every plugin sits behind its interface, and
  the domain stays pure. The trip already depends only on `TripAdOffers`.
- **Alternatives considered:** `lib/features/ads/`, rejected: ads serve several features and hold
  no screen of their own.

## R4. Ad ids per flavor (FR-027)

- **Decision:** one table, `lib/core/ads/ad_ids.dart`, gives each flavor its ad unit per placement,
  the way `api_environment.dart` gives each flavor its API host. Ad unit ids aren't secrets: they
  ship in every APK.
  - **dev:** Google's sample test units (rewarded and interstitial) and the sample app id. The
    piggy's server check can't reach a laptop, so in dev the piggy runs against the dev stack with
    `ads_dev_callback --nonce <reference>` (B07 quickstart §2). The debug panel shows the reference.
  - **staging and prod:** the owner's real units: one rewarded unit per rewarded placement, so the
    piggy's server-check callback sits on its own unit (B07), plus one interstitial unit. Staging
    serves test ads only to the devices the owner registers as test devices in the AdMob console.
    No device id goes in code.

  The AdMob app id goes in each flavor's Android manifest placeholder (`productFlavors`,
  `com.google.android.gms.ads.APPLICATION_ID`) and in iOS `Info.plist` through each scheme's
  `GADApplicationIdentifier` build setting. A test checks that every flavor names a unit for every
  placement, and that dev names only Google's sample ids.
- **Rationale:** The piggy's server check works only on a real unit (B07 owner action 1a, and its
  staging check with a real ad). The console's test devices keep staging away from live traffic
  without shipping device ids.
- **Alternatives considered:** `--dart-define-from-file` per flavor, rejected: every build command
  and CI job would change, for ids that aren't secret. Test units on staging, rejected: the piggy
  could not be checked end to end before production.

## R5. Age rating and ad content rating (resolves backend §22.8)

- **Decision:** the stores list the game as not designed for children, 13+. Every request goes out
  with `RequestConfiguration(maxAdContentRating: T, tagForChildDirectedTreatment: no,
  tagForUnderAgeOfConsent: no)`, set once before the SDK starts. Play Console's target audience is
  13–15, 16–17 and 18+ (owner action). The constitution's line "Content MUST stay within all-ages
  limits until the store age rating is decided" is then settled for ads. The game's own content
  stays within its product limits, which don't change.
- **Rationale:** The owner's choice (spec Clarifications), which matches the docs' proposal. T keeps
  the ads in step with a 13+ audience without Families policy limits.
- **Alternatives considered:** in the spec Clarifications.

## R6. Consent (FR-023, FR-024)

- **Decision:** UMP, from `google_mobile_ads`. `AdsService.ensureReady()` runs once per launch,
  before the first SDK call:
  1. `ConsentInformation.requestConsentInfoUpdate` with no debug settings (dev may set a test
     geography from the debug panel);
  2. `ConsentForm.loadAndShowConsentFormIfRequired`;
  3. `canRequestAds()`; only then `MobileAds.instance.initialize()`, then the preloads.

  On iOS, the ATT prompt comes from UMP's IDFA explainer message, which the owner turns on in the
  AdMob console (Privacy & messaging). `Info.plist` gets `NSUserTrackingUsageDescription` and
  Google's `SKAdNetworkItems` list. There is no separate ATT plugin. When consent is refused or
  tracking is denied, the SDK serves non-personalised ads by itself, and the app does nothing extra.
  Settings gets no privacy-options entry in M11: Egypt shows no form today, and M14 builds Settings
  (handed on).

  `ensureReady()` runs at the first between-trips checkpoint where an ad may come next: before
  tutorial trip 3 starts (spec Clarifications), or at any later checkpoint while it hasn't run
  this launch. It never runs while a trip runs (constitution IX). It runs offline too, and then
  passes at once with nothing loaded.
- **Rationale:** Constitution IX names UMP before the first request and ATT before personalised
  ads on iOS. UMP's IDFA message is Google's own ATT path, so no extra plugin is needed.
- **Alternatives considered:** `app_tracking_transparency`, rejected: a second plugin for a prompt
  UMP already shows. Consent at launch, rejected: it would interrupt the first session's opening
  (constitution V, spec SC-008).

## R7. What "no ad call while a trip runs" covers (FR-008, FR-009)

- **Decision:** an ad call is any call into the SDK through `AdsGateway`: consent, initialise,
  load, show. Reading a placement's cached readiness (`isReady`) and the service's own caps isn't
  one, so the dashboard can show «زحمة»'s ad mark while the trip runs.
  - The `AdsGateway` test fake fails the test on any call while a `TripRunningProbe` says the
    engine runs.
  - The probe is a `ValueListenable<bool>` the trip controller sets on its status changes.
  - The trip-controller contract (`specs/008-m02-trip-screen/contracts/trip-controller.md` "Ads")
    changes its rule: `isOffered` may be called at any time; `show` only while paused or failed.

  Preloads happen at the checkpoint before a trip and right after an in-trip ad closes, while the
  engine is still paused. An ad that finishes loading during a trip is the SDK's callback, not an
  app call.
- **Rationale:** The guarantee is about interrupting play. A cached flag interrupts nothing.
- **Alternatives considered:** hiding the ad mark while running, rejected: the design draws it
  (`TripEvents`), and HANDOFF §9.1 #11 pauses only on the tap.

## R8. In-trip ads, and recovery after a kill

- **Decision:**
  - **Ad revive:** the controller calls `ads.show(tripRevive)` in `failed`. On reward,
    `economy.applyAdReward(tripRevive)` sets the unfinished trip's `revived`, and then comes
    `_applyRevive()`, exactly as after a BONAT revive. A kill between the two recovers through the
    existing path: at load, `unfinished.revived && !state.revived` applies the revive (M02 R7).
  - **Ad «زحمة»:** a tap on «زحمة» with none left already pauses the engine and opens M02's
    `BoosterCard`. For `traffic_jam` the card gains the ad button above its BONAT purchase. On
    reward, the controller writes a `trip_intent` row (kind `ad_reward`, booster `traffic_jam`)
    before calling `applyAdReward(trafficJam)`. Then it sends the engine's booster command and
    clears the row, the way the BONAT booster's outbox works. Schema 6 widens `trip_intent.kind`.
    The card then gives way to the pause card (`PauseReason.ad`), and the player resumes.
    The dashboard's «إعلان» badge only signals the offer, so no small target starts an ad.
  - Kill points `adRewardApplied` and `adIntentWritten` join `TripKillPoint`.
- **Rationale:** It reuses M02's recovery, so a reward is never lost after the economy has
  applied it, and never applied twice.
- **Alternatives considered:** applying the time before the ad closes, rejected: an ad closed early
  must grant nothing.

## R9. The daily refill cap and game days on the phone (FR-002)

- **Decision:** a pure `gameDayOf(int trustedMs)` in `lib/core/economy/domain/game_day.dart` gives
  Cairo's calendar date: UTC+2, or UTC+3 from the last Friday of April 00:00 to the last Thursday of
  October 24:00, Egypt's rule since 2023. A shared fixture, `fixtures/economy/game_day.json`, comes
  from the backend's `game_date` (Python `zoneinfo`, `Africa/Cairo`). It holds instants around
  every switch and midnight from 2026 to 2035, and Dart replays it, like `fuel.json`. Pytest
  checks it against `game_date`, so a tzdata change fails CI.

  Today's refill count comes from `Economy.adRewardsOn(placement, gameDay)`, a read of the
  `ledger_ops` rows of type `ad_reward` with that placement whose trusted `occurred_at_ms` falls on
  that day and whose `sync_status` isn't `rejected`. `AdsService` checks the count against
  `ads_fuel_refill_daily_cap` before offering and again before applying. The economy's rule stays
  as it is (M05 left the daily caps to M11), and the server still refuses `cap_reached`.
- **Rationale:** No timezone package (the IANA data is hundreds of KB) for one zone whose rule the
  fixture pins. M13 reuses `gameDayOf` for its daily reward.
- **Alternatives considered:** the `timezone` package (size). Asking the server for the day's end
  (a backend change to merged B03/B07). A projection field (it would make the fold depend on the
  clock).

## R10. The interstitial's history (FR-020–FR-022)

- **Decision:** `interstitialDue(...)` in `lib/core/ads/domain/` decides from:
  - `trips`: the count of `trip_start` rows in `ledger_ops` (`Economy.tripStarts()`), the trips of
    the spec's clarification;
  - `lastInterstitialAt`: the trip count when an interstitial last showed;
  - `lastRewardedAt`: the trip count when a rewarded ad last paid, the piggy included;
  - `tutorialDone`, the entitlements' `removeAds` or `noInterstitials`, online, and loaded.

  It shows when `trips ≥ ads_interstitial_grace_trips`, the tutorial is done,
  `trips − lastInterstitialAt ≥ ads_interstitial_every_n_trips`, `lastRewardedAt < trips`, neither
  entitlement is set, the phone is online, and one is loaded. Both stored counts are device
  preferences (`pref.ads_last_interstitial_trip`, `pref.ads_last_rewarded_trip`, `SettingsStore`),
  written only by `AdsService`. They are pacing, not game state. A fresh install starts at 0, so the
  grace period plays again, which is harmless.
- **Rationale:** Every input is already on the phone except the two counts. "Right after a rewarded
  ad" becomes "a rewarded ad paid since the last trip start" (spec Assumptions).
- **Alternatives considered:** a drift table (a schema change for two numbers). Counting finished
  trips (the owner chose starts).

## R11. The piggy banner's availability, and a stale day

- **Decision:** the bootstrap answer gains a parsed `ads` block (`AdsBlock`: `available`, `unseen`).
  `server_info` keeps it as canonical JSON in a new column, `ads` (schema 6), beside `daily`. The
  banner shows when the cached block says `available`, the cached `daily.game_date` equals
  `gameDayOf(trusted now)`, and today's local piggy attempt hasn't ended (R12). Offline, the banner
  shows dimmed with «محتاج نت» (`HomeStates` row 7); with no cached block it takes no space.
- **Rationale:** It closes the spec's outstanding item. A block from yesterday says nothing about
  today, and the next bootstrap brings today's.
- **Alternatives considered:** the live answer only, rejected: the offline state (row 7) needs the
  cache.

## R12. The piggy's polling and the wallet (FR-016–FR-019)

- **Decision:** `PiggyService.watch()`:
  1. `ensureReady()`; a fresh UUIDv4 reference; `ServerSideVerificationOptions(userId: playerId,
     customData: '{"placement":"morning_piggy","nonce":"<ref>"}')`, compact JSON in that key order;
  2. show the ad; if it closes without a reward, nothing happens and the banner stays;
  3. on reward, record `lastRewardedAt`, then `GET /v1/ads/rewards/{ref}` after waits of 1 s, 2 s
     and 4 s, so at 1 s, 3 s and 7 s after the reward (SC-004's 7 s). A 404 means "not yet", and so
     does a network error;
  4. granted: the card shows the lookup's amounts, `ad_reward_seen` is queued, and a sync pass is
     requested (`SyncEngine.request(SyncTrigger.adReward)`);
  5. refused: the "today's piggy is used" message, and `ad_reward_seen`, so it doesn't come back;
  6. given up: «المكافأة في الطريق، هتلاقيها أول ما توصل»; the grant comes later in bootstrap's `unseen`.

  The banner hides for the rest of the game day after step 3, whatever the outcome, through an
  in-memory "attempted today" flag plus the next bootstrap's `available: false`.

  **The wallet.** B07 hands on "replace the wallet from the lookup's `wallet`". The phone's wallet is
  a fold of the server's base and the pending operations (M06), so a wallet alone can't replace it
  without dropping pending operations. The grant moved `state_version`, so the requested pass
  fetches the full state and rebases (M06's `replaceFromServer`). The pills move when that pass
  ends, typically within 2 s on a working network, and the card shows the amounts at once. The
  lookup's `wallet` is read but not applied.
- **Rationale:** Constitution IV: BONAT comes only from the server, and only M06's fold may change
  the projection. One extra state fetch is cheap.
- **Alternatives considered:** a wallet-only replacement (it breaks the fold with pending
  operations). Waiting for the next scheduled pass (the pills would lag for minutes).

## R13. `ad_reward_seen` on the phone

- **Decision:** a new operation, `OpType.adRewardSeen` (`ad_reward_seen`, payload `{"nonce"}`),
  recorded by `Economy.markAdRewardSeen(TxnId, {required String nonce})`. It has no deltas and
  doesn't change the projection, and the fold skips it. A second one for the same nonce is
  `OpRefused(alreadyRecorded)` and stores nothing. M06 sends it like any other operation; the
  server always accepts it. Schema 6 widens `ledger_ops.op_type`'s check (M10's rebuild pattern).
  - The late-reward card shows for each `unseen` entry with no local `ad_reward_seen` for its
    nonce (`Economy.adRewardSeen(nonce)`). So a card queued but not yet synced never shows twice,
    even while bootstrap still lists the reward.
  - It is in `_counterPlacements`' spirit: M06's rollback toast ignores it, because it changes
    nothing visible.
- **Rationale:** M06 makes the economy the only writer of operations, so a sync-only op still goes
  through it.
- **Alternatives considered:** a separate outbox (a second sync path).

## R14. The late-reward card, an arrival item

- **Decision:** `PiggyArrival` (rank 40, M08's seam) is due when the cached `ads.unseen` holds an
  entry with no local `ad_reward_seen`. It opens the reward-arrived card (the owner's board,
  contracts/design-briefs.md) for the newest entry, and the other entries one per arrival. Closing
  the card records `ad_reward_seen`. The banner's polling outcomes are shown in place, not as
  arrival items.
- **Rationale:** M08's queue already orders one item per arrival. The name sheet and the due scene
  outrank it.
- **Alternatives considered:** one card listing all unseen rewards (at most 5, rare): it needs a
  board of its own, for an edge case.

## R15. The ×2 in the first session (spec Clarifications)

- **Decision:** `resultDoubleSlot` builds the offer when the finished trip isn't tutorial trip 1 or 2
  (`TutorialPlan`'s index < 2), `ensureReady()` has run, and the economy's `lastResult` is doublable.
  The checkpoint before tutorial trip 3 runs `ensureReady()` and preloads `result_double`. While the
  tutorial isn't done, `AdsService.offer()` answers "not offered" for every other placement. The
  boosters are locked until then anyway (M07 FR-038).
- **Rationale:** It follows the owner's answer exactly.

## R16. Preloading and readiness (FR-007)

- **Decision:** one loaded rewarded ad per rewarded unit, at most, plus one interstitial, held by
  `GmaAdsGateway`.
  - **Load at:** `ensureReady()`; every checkpoint (all rewarded placements the next trip or its
    result may offer, and the interstitial when one could be due within a trip); right after a
    rewarded ad closes (that placement again, while still paused or between trips); Home's
    appearance (the piggy, when the banner may show).
  - **Expiry:** an ad older than 55 minutes is dropped and reloaded at the next allowed moment.
    Google's rewarded and interstitial ads expire after an hour.
  - **Failures:** a failed load waits 30 s, then 60 s, then 120 s, before the next try at an allowed
    moment.

  Readiness is a `ValueListenable` per placement, which the buttons read for the not-ready state.
  These delays are SDK hygiene, not balancing numbers, so they are named constants in
  `lib/core/ads/domain/`, not tunables (constitution VIII covers balancing).
- **Rationale:** HANDOFF draws "not ready" as rare. Reloading at each allowed moment keeps it rare
  without loading during a trip.

## R17. The refill offer before M12 (spec Clarifications, FR-030)

- **Decision:** one widget, `FuelRefillAdOffer` (in `lib/features/fuel/presentation/`, a new small
  feature folder M12 extends): «اتفرج على إعلان وخد تفويلة كاملة», «باقيلك {n} النهارده», with the
  `RewardedAdButton` states.
  - The widget always draws the BONAT refill («فوّل الخزان» with a `PriceChip` «٣٠ بون», the catalog's `refuel_full` price)
    beside the ad, as equal choices. So wherever it shows, constitution IX's "BONAT option next to
    the ad" holds (analysis C1). The BONAT refill buys through M05's
    `buy(kind: SkuKind.fuel, skuId: refuelFullSku)` (`spend_rules.dart`),
    with its own request id. It stays tappable when the ad is not ready, at its limit or offline
    (offline it spends optimistically, as every BONAT spend does).
  - M11 shows it on the trip's `NoFuelCard`, above «البنزين» and the way back (the owner's
    `NoFuelAd` and `NoFuelAdLimit` boards), and in the placeholder `/shop/fuel` page.
  - After the reward, the card's start path retries the trip start, so the player plays at once.
  - M12 places the same widget in its `Fuel` sheet.
- **Rationale:** The owner's answer. One widget keeps one set of goldens.

## R18. Analytics hooks

- **Decision:** `AdsService` emits `AdEvent`s (`offered`, `rewarded`, `interstitialShown`,
  `loadFailed`, `piggyGaveUp`) on a stream. M15 maps them to `ad_offer_shown`,
  `ad_reward_granted` and `ad_interstitial_shown` (mobile §17). M11 logs only `loadFailed` counts in
  debug builds.
- **Rationale:** The spec leaves the reporting to M15. A stream keeps M11 from defining the sink.

## R19. Tests

- **Decision:**
  - Unit tests (written first) for `interstitialDue`, `adOffer`, `gameDayOf` (with the shared
    fixture), the piggy's polling plan and `ad_reward_seen`'s rule.
  - Controller tests for both in-trip ads under the spy gateway (R7). They cover kill points, a
    resume at launch, and the background during an ad.
  - Widget tests and goldens (RTL, both digit styles) for every button state on Result, Fail,
    «زحمة», Home's piggy (online, offline), the refill offer, and the owner's three boards once they
    land.
  - Layout tests remove the `Fail` skip (box 12) and check `TripEvents`' ad badge. Drift migration
    tests cover 5 → 6.
  - An `integration_test` covers empty fuel → refill ad → trip (constitution XIII).
  - `fake_ads_gateway.dart` and `fake_piggy_api.dart` serve the tests. A `backend`-tagged test runs
    the piggy against the dev stack, signing with `ads_dev_callback`.
- **Rationale:** Constitution XIII's levels and test-first for the cap and reward rules.

## Handed to later features

- **M12:** put `FuelRefillAdOffer` in the `Fuel` sheet; the shop's `remove_ads` changes
  `Entitlements.removeAds`, which the checkpoint already reads.
- **M13:** reuse `gameDayOf` for the daily reward and tasks.
- **M14:** Settings' privacy entry (`ConsentForm.showPrivacyOptionsForm` when
  `privacyOptionsRequirementStatus` is required), and the iOS backup exclusion as before.
- **M15:** map `AdEvent`s to analytics; report the piggy's give-up rate (B07 SC-003).
- **B09:** nothing new on the phone; deletion already clears local data.
