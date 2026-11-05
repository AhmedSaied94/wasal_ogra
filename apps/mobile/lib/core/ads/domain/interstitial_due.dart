// The interstitial's decision between trips (specs/018-m11-ads, research
// R10, glossary §3.4). Trips are `trip_start` rows; the two "at" counts are
// the trip counts when an interstitial last showed and when a rewarded ad
// last paid (device preferences, written only by `AdsService`).

/// Whether an interstitial shows at this checkpoint.
bool interstitialDue({
  required int trips,
  required int lastInterstitialAt,
  required int lastRewardedAt,
  required bool tutorialDone,
  required bool removeAds,
  required bool noInterstitials,
  required bool online,
  required bool loaded,
  required int graceTrips,
  required int everyNTrips,
}) =>
    tutorialDone &&
    !removeAds &&
    !noInterstitials &&
    online &&
    loaded &&
    trips >= graceTrips &&
    trips - lastInterstitialAt >= everyNTrips &&
    // Not right after a rewarded ad: one paid since the last trip start.
    lastRewardedAt < trips;
