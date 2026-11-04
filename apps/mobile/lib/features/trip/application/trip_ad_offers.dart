import 'package:wassal/core/economy/domain/op.dart' show AdPlacement;
import 'package:wassal/features/trip/domain/ad_slot.dart';

/// M11's rewarded ads inside a trip (specs/018-m11-ads, contracts/seams.md
/// "`TripAdOffers`"; M02's contracts/trip-controller.md "Ads"). [slot]
/// reads caches only, so the trip may ask at any time; [show] runs only
/// while the engine is paused or failed: no ad SDK call may run while a
/// trip runs (constitution IX, research R7). The reward is the
/// controller's to apply (research R8).
abstract interface class TripAdOffers {
  /// What [placement]'s button shows now (`traffic_jam`, `trip_revive`).
  AdSlot slot(AdPlacement placement);

  /// Shows the ad. True when its reward was earned. Paused or failed only.
  Future<bool> show(AdPlacement placement);

  /// Fires when a [slot] may have changed (an ad loaded or expired).
  Stream<void> get changes;
}

/// No ads: tests, and builds without the ads layer.
final class NoTripAdOffers implements TripAdOffers {
  const NoTripAdOffers();

  @override
  AdSlot slot(AdPlacement placement) => AdSlot.hidden;

  @override
  Future<bool> show(AdPlacement placement) async => false;

  @override
  Stream<void> get changes => const Stream.empty();
}
