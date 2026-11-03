# Implementation Plan: Ads Integration — Rewarded, Interstitial, Consent (M11)

**Branch**: `018-m11-ads` | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/018-m11-ads/spec.md`

## Summary

The app gets its ads: five rewarded placements and one interstitial (glossary §3.4), behind
consent, with their caps checked on the phone as the server already checks them (B03, B07).

- **New core module.** A new `lib/core/ads/` wraps `google_mobile_ads` 9.2 (with AppLovin and Unity
  mediation) behind `AdsGateway`. `AdsService` decides each offer from pure rules over what the phone
  already holds: the operation log, the cached bootstrap, the first session, the entitlements and
  the tunables.
- **Seams it fills.** M11 fills the seams M02 and M08 left: the trip's `TripAdOffers` for the ad
  revive and the ad «زحمة», the between-trips checkpoint for the interstitial, the result's ×2 slot,
  Home's piggy slot and its arrival item. It adds one refill-ad offer, which M12's fuel sheet reuses.
- **Morning piggy.** The piggy carries the player id and a one-time reference to B07's server
  check, asks for the grant at 1 s, 3 s and 7 s, and confirms each shown grant with a new
  operation, `ad_reward_seen`.
- **Schema 6.** Drift schema 6 widens two checks and caches the bootstrap's `ads` block.
- **First session.** Trips 1–2 stay ad-free; the ×2 starts at tutorial trip 3, after consent.

## Technical Context

**Language/Version**: Dart 3.13, Flutter 3.47.7 (FVM)

**Primary Dependencies**: existing (`flutter_riverpod`/`riverpod_generator`, `go_router`, `drift`,
`dio`, `rive`, `flame`); new: `google_mobile_ads` ^9.2.0, `gma_mediation_applovin` ^2.6.4,
`gma_mediation_unity` ^1.11.0, all Swift Packages on iOS (research R1, R2)

**Storage**: drift schema 6 (`ledger_ops.op_type` + `ad_reward_seen`, `trip_intent.kind` +
`ad_reward`, `server_info.ads`). Two device preferences for interstitial pacing (data-model.md).

**Testing**: `flutter_test` unit, widget and golden tests (RTL, both digit styles), design layout
tests, drift migration tests, `integration_test` (empty fuel → refill ad → trip), a `backend`-tagged
piggy test against the dev stack, and one pytest for the shared game-day fixture. Flutter tests run
on the VPS (`rtest`).

**Target Platform**: Android (minSdk 24, targetSdk 36) first; iOS 15 (unsigned dev IPA on
Codemagic)

**Project Type**: mobile app (`apps/mobile`); no backend change except one fixture test

**Performance Goals**:

- no ad work while a trip runs, so the trip keeps 008.5's frame gate (≥ 45 fps on the A06);
- cold start < 3 s unchanged: the SDK starts at the first ad checkpoint, not at launch;
- 9 in 10 piggy rewards shown within 7 s (SC-004).

**Constraints**:

- constitution IX: no SDK call while running; BONAT next to the ad; caps on both sides;
  consent first;
- constitution IV: the piggy only through B07;
- Android download < 80 MB with the SDK and two adapters (measured before merge);
- no Podfile.

**Scale/Scope**:

- 6 placements, about 12 widgets or states;
- 3 new boards from the owner;
- one new operation;
- one migration step.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | How M11 satisfies it |
| --- | --- |
| I. Engine purity | No engine change. The ad revive sends the engine's existing `Revive`, and the ad «زحمة» its existing booster command (R8). |
| II. Integer money | Rewards are M05's integer deltas. The piggy's amounts are server integers, shown, never applied locally. |
| III. Parity | No rule change, so no parity fixture changes. The new shared `fixtures/economy/game_day.json` runs in Dart and pytest (R9). |
| IV. Server authority | `morning_piggy` only through B07's SSV. The phone never applies BONAT. The wallet moves through M06's state fetch, not the lookup's wallet (R12). Entitlements are read-only. |
| V. Offline-first | Ads show «محتاج نت» offline and never block play. The checkpoint passes offline. The first session's opening and trips 1–2 have no ads (R15). |
| VI. Idempotency | Every reward uses one request id per intent. `ad_reward_seen` is a UUIDv7 operation and refuses a repeat locally. The trip's intent outbox covers the kill window (R8, R13). Day counts use trusted time (R9). |
| VII. Content, not code | Ad copy is in `app_ar.arb`. The piggy's amounts come from the server. BONAT prices for the alternatives come from the catalog. |
| VIII. Tunables | Caps and cadence come from the existing keys (`ads_interstitial_every_n_trips`, `ads_interstitial_grace_trips`, `ads_fuel_refill_daily_cap`, `ads_morning_piggy_daily_cap`). Preload expiry and back-off are SDK hygiene, not balancing, so they are named constants (R16). |
| IX. No ads in a trip | The spy gateway fails tests on any SDK call while running (R7). The ad «زحمة» runs from the paused booster card, and the revive in `failed`. Interstitials only at the checkpoint, by §3.4's rules (R10). BONAT next to every ad that has one. Caps on the device (R9, R10) and on the server (B03, B07). UMP first, ATT through UMP on iOS (R6). No banners. |
| X. RTL and Arabic first | Every new state gets RTL goldens in both digit styles. The copy is Egyptian Arabic. |
| XI. Accessible minimums | Ad buttons are `RewardedAdButton` (66 high). The decline link is ≥ 44×44. No small badge starts an ad (R8). Disabled is 45% with no lip. |
| XII. No runtime LLM | n/a. |
| XIII. Small, testable features | One spec folder. Rules are tested first (`interstitialDue`, `adOffer`, `gameDayOf`, `ad_reward_seen`). Coverage ≥ 80%. The `integration_test` for empty fuel → ad, as XIII requires. |
| Platform & security | HTTPS only. No secrets: ad ids aren't secret and sit in a per-flavor table (R4). The player id reaches the ad network only as the piggy's SSV user id (FR-026). The locked stack is unchanged. The ad SDK guard is widened (R3). |
| Performance budgets | Cold start unchanged (SDK start deferred). The trip frame gate holds (no ad work in a trip). Download size measured before merge. |

**Result: PASS.** No deviation, so Complexity Tracking is empty. One hand-over from B07 is done
differently from how it was worded: the wallet comes through M06's state fetch rather than the
lookup's `wallet`. That follows constitution IV and M06's fold (research R12), and it is recorded
there.

**Re-check after Phase 1 design: PASS.**

- The contracts keep every SDK import in `gma_ads_gateway.dart` and every domain rule pure.
- Schema 6 keeps each table's one writer.
- The trip-controller contract change (R7) narrows the timing rule to `show`, which is still only
  called while paused or failed.

## Project Structure

### Documentation (this feature)

```text
specs/018-m11-ads/
├── plan.md
├── research.md            # R1–R19; resolves mobile §24.3, backend §22.8
├── data-model.md          # schema 6, ad_reward_seen, AdsBlock, prefs, rules
├── quickstart.md
├── contracts/
│   ├── ads-gateway.md     # AdsGateway, AdsService, strings
│   ├── seams.md           # what M11 fills in M02, M08; the refill offer for M12
│   ├── economy-ops.md     # Economy additions, ad_reward_seen, bootstrap ads, lookup, schema 6
│   ├── platform-config.md # dependencies, ad ids per flavor, Android, iOS, request configuration, doc edits
│   └── design-briefs.md   # the owner's six boards (piggy, out-of-fuel ad, booster ad)
├── checklists/requirements.md
└── tasks.md               # /speckit-tasks
```

### Source Code (repository root)

```text
apps/mobile/
├── lib/core/ads/
│   ├── domain/            # ad_offer.dart, interstitial_due.dart, piggy_plan.dart, ad_timing.dart (pure)
│   ├── ads_gateway.dart   # interface
│   ├── gma_ads_gateway.dart  # the only google_mobile_ads import
│   ├── ad_ids.dart        # per-flavor ids
│   ├── ads_service.dart, piggy_service.dart, piggy_api.dart
│   ├── ads_trip_offers.dart, ads_checkpoint.dart
│   └── ads_providers.dart
├── lib/core/economy/      # markAdRewardSeen, adRewardSeen, adRewardsOn, tripStarts; domain/game_day.dart; OpType.adRewardSeen
├── lib/core/sync/         # AdsBlock in bootstrap.dart, server_info.ads, SyncTrigger.adReward, adsBlockProvider
├── lib/core/storage/      # schema 6 (tables.dart, app_database.dart, steps)
├── lib/features/trip/     # reviveWithAd, trafficJamWithAd, FailureCard, BoosterCard, BoostersRow badge, kill points
├── lib/features/result/   # ResultDoubleOffer
├── lib/features/home/     # PiggyBanner, PiggyArrival, the piggy's cards
├── lib/features/fuel/     # FuelRefillAdOffer (new; M12 extends)
├── lib/features/dev/      # debug panel «Ads» card: consent, readiness, reference, test geography
├── lib/l10n/app_ar.arb
├── android/app/           # manifest placeholder per flavor, meta-data
├── ios/Runner/            # Info.plist keys, ADMOB_APP_ID per scheme
├── test/core/ads/, test/core/economy/game_day_test.dart, test/drift/, test/features/**, test/design/**, test/backend/piggy_test.dart
└── integration_test/fuel_ad_test.dart
fixtures/economy/game_day.json
backend/apps/economy/tests/test_game_day_fixture.py
docs/architecture-mobile.md (§15.1, §24.3), docs/architecture-backend.md (§22.8), specs/008-m02-trip-screen/contracts/trip-controller.md, apps/mobile/CLAUDE.md, docs/owner-actions.md
```

**Structure Decision**: the existing mobile app's layering. Ads are a core module, because several
features use them, and each feature fills its own seam. The only backend change is a test of the
shared fixture.

## Owner actions (for `docs/owner-actions.md` at implement time)

- **Before merge:**
  - create the AdMob ad units: one rewarded per placement and one interstitial, for Android, and
    iOS when it sells; send the ids;
  - set up AppLovin and Unity in AdMob mediation;
  - register the test phone as an AdMob test device;
  - turn on UMP's messages (GDPR form, IDFA explainer) in Privacy & messaging;
  - the Arabic `NSUserTrackingUsageDescription` text;
  - draw the six boards (contracts/design-briefs.md).
- **After merge:**
  - the staging run (quickstart §5);
  - Play Console's ads and data-safety declarations and its target audience (13+);
  - B07's item 4 (production's callback URL) before the release.

## Complexity Tracking

No constitution violations.
