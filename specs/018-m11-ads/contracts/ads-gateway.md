# Contract: `AdsGateway` and `AdsService`

`lib/core/ads/`. Only `gma_ads_gateway.dart` imports `google_mobile_ads` or the mediation adapters
(repo guard, research R3).

## `AdsGateway` (the plugin boundary, constitution "Architecture boundaries")

```dart
enum AdUnit { resultDouble, fuelRefill, tripRevive, trafficJam, morningPiggy, interstitial }

sealed class ShowOutcome {}
final class Rewarded extends ShowOutcome {}   // the SDK's reward callback fired
final class Closed extends ShowOutcome {}     // closed with no reward (and every interstitial)
final class ShowFailed extends ShowOutcome {} // not loaded, expired, or the SDK failed to show

abstract interface class AdsGateway {
  /// UMP, then the SDK's start (research R6). Completes with whether ads may be requested.
  Future<bool> start(RequestConfig config);

  Future<void> load(AdUnit unit);

  /// The placement's readiness; reading it is not an SDK call (research R7).
  ValueListenable<Readiness> readiness(AdUnit unit);

  /// [verification] only for `morningPiggy`.
  Future<ShowOutcome> show(AdUnit unit, {PiggyVerification? verification});
}

final class RequestConfig {
  // maxAdContentRating T, not child-directed, not under the age of consent (research R5).
}

final class PiggyVerification {
  final String userId;     // player_id
  final String customData; // {"placement":"morning_piggy","nonce":"<uuid4>"}, compact, in this key order
}
```

- `show` resolves after the ad's full-screen content is dismissed. A reward fires before the
  dismissal, so `Rewarded` means "earned", whatever happens to the app after.
- `GmaAdsGateway` holds at most one loaded ad per unit and applies the expiry and the back-off
  (research R16).
- **The test fake** (`test/helpers/fake_ads_gateway.dart`) scripts the outcomes and the readiness,
  and records every call. With a `TripRunningProbe`, it fails the test on any call while the probe
  reads true (research R7, spec FR-009).

## `AdsService` (application, Riverpod `adsServiceProvider`, keep-alive)

```dart
abstract interface class AdsService {
  /// Consent and the SDK start, once per launch; preloads after (R6, R16). Never while a trip runs.
  Future<void> ensureReady();

  /// What a button shows now (data-model.md `adOffer`). Synchronous; reads caches only.
  AdOffer offer(AdPlacement placement, {String? tripId});
  Stream<void> get offersChanged;

  /// Shows the rewarded ad and, on `Rewarded`, applies the reward through the economy (except the
  /// piggy: `PiggyService`). One call at a time; a second while one runs returns the first's result.
  Future<RewardOutcome> watch(AdPlacement placement);

  /// The between-trips decision and the interstitial (R10).
  Future<void> betweenTrips();

  /// Preloads what the next trip and its result may offer (R16).
  void preloadForNextTrip();

  Stream<AdEvent> get events; // for M15 (R18)
}

sealed class RewardOutcome {}
final class RewardApplied extends RewardOutcome { final OpApplied applied; }
final class RewardRefused extends RewardOutcome { final EconomyRefusal code; } // e.g. tank_full after the ad
final class NoReward extends RewardOutcome {}      // Closed or ShowFailed
```

`watch` for a client placement (`result_double`, `fuel_refill`, `trip_revive`, `traffic_jam`):

1. Re-check `offer`. If it isn't `Offered`, the result is `NoReward`, with no SDK call.
2. Take the request id: one per player intent, held across a double tap (M05 R10).
3. `gateway.show(unit)`.
4. On `Rewarded`: write `pref.ads_last_rewarded_trip`; for `fuel_refill`, check the daily count
   again; then `economy.applyAdReward(id, placement)`. Outcome → `RewardApplied` or
   `RewardRefused`.
5. Reload the unit at once if the caller says the moment allows it. The trip controller calls
   `preloadAfterAd` itself while still paused.

The in-trip pair goes through `TripAdOffers` (contracts/seams.md), so the controller can put its
intent row and engine command around step 4.

## Interstitial: `betweenTrips()`

Implements `BetweenTripsCheckpoint.pass()` (M08):

1. If `ensureReady()` hasn't run and the next trip is tutorial trip 3 or later, or the tutorial is
   done, run it. Then `preloadForNextTrip()`.
2. If `interstitialDue(...)` (data-model.md), `gateway.show(interstitial)`. When it closes, write
   `pref.ads_last_interstitial_trip = trips` and reload the interstitial.
3. Return. The caller then opens the pre-trip card or the trip (M08 contracts/home.md step 2). A
   `ShowFailed` writes nothing (spec FR-022).

## Strings (`app_ar.arb`; the boards win where they differ)

| Key | Text |
| --- | --- |
| `adNotReady` | «الإعلان مش جاهز» (button), «الإعلان مش جاهز دلوقتي، جرّب كمان شوية» (`States` 2) |
| `adLimitReached` | «خلصت النهارده» (`States` 3) |
| `adNeedsNetwork` | «محتاج نت» |
| `resultDoubleTitle` / `resultDoubleBenefit` | «اقبض ×٢» / «+{doubled} بدل {pay}» |
| `reviveAdTitle` | «صالح الركاب» |
| `trafficJamAdBadge` | «إعلان» |
| `refillAdTitle` / `refillAdLeft` | «اتفرج على إعلان وفوّل» / «باقيلك {n} النهارده» (plural forms; `NoFuelAd`) |
| `refillBonatTitle` | «فوّل الخزان», with a `PriceChip` of the catalog's price (`NoFuelAd`) |
| `trafficJamAdTitle` / `trafficJamAdBenefit` | «زحمة ببلاش» / «+{seconds} ثواني للمحطة الجاية» (`BoosterAdCard`) |
| `piggyTitle` / `piggyBody` / `piggyCta` | «حصّالة الصبح» / «اتفرج على إعلان وخد جنيهات وبونات» / «ببلاش» (HANDOFF Home) |
| `piggyLater` | «المكافأة في الطريق، هتلاقيها أول ما توصل» |
| `piggyUsed` | «الحصّالة اتفتحت النهارده، تعالى بكرة» (`PiggyUsed`, a toast) |
| `piggyArrivedTitle` / `piggyArrivedOk` | «الحصّالة وصلت!» / «تمام» (`PiggyArrived`) |
