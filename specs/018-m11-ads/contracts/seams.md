# Contract: The Seams M11 Fills

Earlier features left each of these empty for M11. Overrides go in the app's provider scope
(`lib/bootstrap/`), so tests and the design samples keep their fakes.

| Seam (owner) | M11's value | Where it shows |
| --- | --- | --- |
| `tripAdOffersProvider` (M02) | `AdsTripOffers(adsService)` | Fail card; «زحمة» booster |
| `betweenTripsCheckpointProvider` (M08) | `AdsCheckpoint(adsService)` → `betweenTrips()` | before the pre-trip card or a direct start: from Home, «مشوار تاني», Lines, the apartment's card |
| `resultDoubleSlotProvider` (M08) | `ResultDoubleOffer` | Result, under the pay |
| `morningPiggySlotProvider` (M08) | `PiggyBanner` | Home, under the savings card (row 6) |
| `arrivalItemsProvider` (M08) | adds `PiggyArrival` at rank 40 | Home, on arrival |
| `NoFuelCard` (M02) | gains `FuelRefillAdOffer` | the trip route's out-of-fuel card |
| `/shop/fuel` placeholder | gains `FuelRefillAdOffer` and the BONAT refill | until M12's sheet |

## `TripAdOffers` (M02), as M11 changes it

```dart
abstract interface class TripAdOffers {
  /// May be called at any time: it reads caches only (research R7).
  /// hidden, ready, notReady or offline; traffic_jam, trip_revive.
  AdSlot slot(AdPlacement placement);
  /// Only while the engine is paused or failed.
  Future<bool> show(AdPlacement placement); // true when the reward was earned
  /// Fires when a slot may have changed (readiness, network, caps).
  Stream<void> get changes;
}
```

As built, `slot` replaced the planned `bool isOffered`, so the buttons can show «الإعلان مش جاهز» and «محتاج
نت» as well as hide (`AdSlot` in `lib/features/trip/domain/ad_slot.dart`; `shown` is any state but
`hidden`). Where this file and research R7 say `isOffered`, read `slot(…).shown`.

M02's contract (`specs/008-m02-trip-screen/contracts/trip-controller.md` "Ads") is edited to match.
`AdsTripOffers.show` calls `AdsService` without applying the reward. The controller applies it
(research R8):

- **`TripController.reviveWithAd()`** (phase `failed`): `show(tripRevive)` → true →
  `economy.applyAdReward(tripRevive)` → `_applyRevive()`. `OpRefused(alreadyRevived)` follows the
  BONAT path's handling. False: nothing changes, and the card stays.
- **`TripController.trafficJamWithAd()`** (phase `boosterCard` for `traffic_jam`). M02's
  `useBooster` already paused the engine when it opened the card, so the probe reads false.
  1. `show(trafficJam)` → true;
  2. write the `trip_intent` row (`kind: ad_reward`, `booster: traffic_jam`);
  3. `economy.applyAdReward(trafficJam)`;
  4. the engine's booster command, then clear the row;
  5. close the card into the pause card (`PauseReason.ad`); the player resumes.

  On false: the card stays, with nothing charged, and the ad button shows its current state.

`TripView`'s booster slot sets `adOffered` from `slot(trafficJam).shown`, which is true only
when the stock is 0 and no traffic-jam ad has been used this trip (`unfinished.trafficJamAds`).
`BoostersRow` draws the «إعلان» badge (`TripEvents`) as the sign that an ad is on offer. The tap
works as before: with none left, it pauses and opens `BoosterCard`. For `traffic_jam` with
`adOffered`, `BoosterCard` shows a `RewardedAdButton` («زحمة ببلاش», the board's copy wins) above
«اشتري واستعمل». So the BONAT option sits next to the ad (constitution IX), and both are full-size
targets (XI).

`FailureCard` puts `RewardedAdButton` («صالح الركاب», `ad_play_on_primary`) in its reserved slot
(`adSlotKey`, `DesignExtras.rewardedHeight`) when `TripView.reviveAdOffered`, a new field. The
BONAT revive stays under it (constitution IX).

## `ResultDoubleOffer`

- Reads `ResultArgs` and `economyView.lastResult`. Builds nothing (`SizedBox.shrink`) unless
  `adOffer(resultDouble)` is `Offered`, `NotReady` or `NeedsNetwork`.
- `RewardedAdButton`: «اقبض ×٢» over «+{pay×2} بدل {pay}», in the ready, not-ready and offline
  states. Under it, the 44×44 decline link that M08's slot asks for («لأ، شكرًا»; the board's copy
  wins). The decline only hides the offer for this result.
- On `RewardApplied`, the result screen's existing `doubled` read shows the doubled pay (M08
  `result_screen.dart`, `economyViewProvider.select(...)`).

## `PiggyBanner` (HANDOFF Home row 6; `HomeStates` row 7)

| State | When | Look |
| --- | --- | --- |
| hidden | no cached block; `available` false; a stale day (R11); attempted today | no space |
| ready | online, an ad loaded | Home row 6, chip «ببلاش» |
| not ready | online, no ad loaded | `States` 2 treatment, chip «الإعلان مش جاهز» |
| offline | offline, cached `available` today | `HomeStates` row 7 (0.55, no lip, «محتاج نت») |
| asking | after the reward, up to 7 s | the chip shows `LoadingWheel` (16) |

Outcomes after asking: "granted" opens the reward card (the owner's `PiggyArrived` board) at once;
"refused" shows `PiggyUsed`; "gave up" shows `PiggyLater`. The banner then hides for the day.

A hidden banner keeps its 52 pt slot, so Home's cards stay where they are and don't jump when it hides
(owner's decision, 2026-11-05).

## `PiggyArrival` (rank 40)

`isDue`: the cached `ads.unseen` has an entry with no local `ad_reward_seen`. `open`: the
`PiggyArrived` board for the newest such entry. Its button records `ad_reward_seen` and closes.

## `FuelRefillAdOffer` (for M12 too)

```dart
class FuelRefillAdOffer extends ConsumerWidget {
  const FuelRefillAdOffer({required this.onFilled, super.key});
  final VoidCallback onFilled; // the trip route retries the start; the sheet closes
}
```

It always draws two equal choices: the ad (`RewardedAdButton`) and, beside it, the BONAT refill
(«فوّل الخزان» with a `PriceChip` «٣٠ بون», price from the catalog's `refuel_full`, through
`buy(kind: SkuKind.fuel, skuId: refuelFullSku)`). That keeps constitution IX's "BONAT option next
to the ad" wherever the widget goes (research R17).

The ad's states: ready («باقيلك {n} النهارده»), not ready, limit reached («خلصت النهارده», 45%, no
lip), offline. The BONAT refill keeps its own states: affordable, short («ناقصك …»), and write
failed. The whole widget is hidden when the tank is full. Layout follows the owner's `NoFuelAd` and
`NoFuelAdLimit` boards (contracts/design-briefs.md).
