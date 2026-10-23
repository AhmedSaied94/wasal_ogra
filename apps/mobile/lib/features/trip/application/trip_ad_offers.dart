import 'package:wassal/core/economy/domain/op.dart' show AdPlacement;

/// M11's rewarded ads inside a trip (contracts/trip-controller.md "Ads").
/// The trip asks only while the engine is paused or failed: no ad SDK call
/// may run while a trip runs (constitution IX).
abstract interface class TripAdOffers {
  /// Whether an ad can be offered now for [placement] (`traffic_jam`,
  /// `trip_revive`). Only while the engine is paused or failed.
  bool isOffered(AdPlacement placement);

  /// Shows the ad. True when its reward was earned. Same precondition.
  Future<bool> show(AdPlacement placement);
}

/// No ads until M11.
final class NoTripAdOffers implements TripAdOffers {
  const NoTripAdOffers();

  @override
  bool isOffered(AdPlacement placement) => false;

  @override
  Future<bool> show(AdPlacement placement) async => false;
}
