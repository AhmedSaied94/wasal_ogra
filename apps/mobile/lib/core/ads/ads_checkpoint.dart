// M08's between-trips checkpoint, filled by M11 (specs/018-m11-ads,
// contracts/seams.md, research R6, R10): consent and the preloads once ads
// may start, and the interstitial when glossary §3.4 says it is due. Every
// start reaches it through `startNextTrip` (analysis U1): Home, «مشوار
// تاني», Lines, the apartment's card and the tutorial result's continue.
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/features/home/application/checkpoint.dart';

final class AdsCheckpoint implements BetweenTripsCheckpoint {
  const AdsCheckpoint(this._ads);

  final AdsService _ads;

  /// Never throws: an ad problem never keeps the player from a trip.
  @override
  Future<void> pass() async {
    try {
      await _ads.betweenTrips();
      // Anything at all: a provider not ready (a StateError) included.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return;
    }
  }
}
