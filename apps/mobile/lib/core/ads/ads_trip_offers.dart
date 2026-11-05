// The trip's rewarded ads over the ads service (specs/018-m11-ads,
// contracts/seams.md "`TripAdOffers`"): `traffic_jam` and `trip_revive`.
// [slot] reads the service's caches, so the trip asks at any time; [show]
// goes through `AdsService.showRewarded`, which refuses while the probe
// reads true. The controller applies the reward (research R8).
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/economy/economy.dart' show AdPlacement;
import 'package:wassal/features/trip/application/trip_ad_offers.dart';
import 'package:wassal/features/trip/domain/ad_slot.dart';

final class AdsTripOffers implements TripAdOffers {
  const AdsTripOffers(this._service);

  final AdsService _service;

  @override
  AdSlot slot(AdPlacement placement) => switch (_service.offer(placement)) {
    Offered() => AdSlot.ready,
    NotReady() => AdSlot.notReady,
    NeedsNetwork() => AdSlot.offline,
    LimitReached() || Hidden() => AdSlot.hidden,
  };

  @override
  Future<bool> show(AdPlacement placement) => _service.showRewarded(placement);

  @override
  Stream<void> get changes => _service.offersChanged;
}
