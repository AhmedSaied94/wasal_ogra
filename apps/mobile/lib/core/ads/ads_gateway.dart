// The ad SDK's boundary (specs/018-m11-ads, contracts/ads-gateway.md,
// constitution "Architecture boundaries"). Only `gma_ads_gateway.dart`
// implements it over `google_mobile_ads`; tests use
// `test/helpers/fake_ads_gateway.dart`.
import 'package:flutter/foundation.dart';
import 'package:wassal/core/ads/domain/request_config.dart';
import 'package:wassal/core/economy/domain/op.dart' show AdPlacement;

export 'package:wassal/core/ads/domain/request_config.dart';

/// One AdMob ad unit: one per rewarded placement, and the interstitial
/// (glossary §3.4, research R4).
enum AdUnit {
  resultDouble,
  fuelRefill,
  tripRevive,
  trafficJam,
  morningPiggy,
  interstitial;

  /// The unit a rewarded placement shows.
  static AdUnit of(AdPlacement placement) => switch (placement) {
    AdPlacement.resultDouble => resultDouble,
    AdPlacement.fuelRefill => fuelRefill,
    AdPlacement.tripRevive => tripRevive,
    AdPlacement.trafficJam => trafficJam,
    AdPlacement.morningPiggy => morningPiggy,
  };
}

/// What `show` came to.
sealed class ShowOutcome {
  const ShowOutcome();
}

/// The SDK's reward callback fired: the reward was earned.
final class Rewarded extends ShowOutcome {
  const Rewarded();
}

/// Closed with no reward (and every interstitial).
final class Closed extends ShowOutcome {
  const Closed();
}

/// Not loaded, expired, or the SDK failed to show it.
final class ShowFailed extends ShowOutcome {
  const ShowFailed();
}

/// A unit's loaded state, as the buttons read it (research R16). Reading it
/// is not an SDK call (research R7).
enum Readiness { notLoaded, loading, ready, failed }

/// The piggy's server-side verification (B07, research R12). [customData]
/// is `{"placement":"morning_piggy","nonce":"<uuid4>"}`, compact, in that
/// key order.
final class PiggyVerification {
  const PiggyVerification({required this.userId, required this.customData});

  /// The player id: the only place it reaches the ad network (FR-026).
  final String userId;
  final String customData;
}

/// Whether a trip's engine is running. The trip controller sets it; the
/// test fake fails on any SDK call while it reads true (research R7).
typedef TripRunningProbe = ValueListenable<bool>;

/// The consent test geography the debug panel may set (dev only, research
/// R6).
enum ConsentGeography { none, eea, notEea }

/// The debug panel's consent controls (T032, T056). Only dev builds call
/// them; the panel shows nothing of them elsewhere.
abstract interface class AdsDebugControls {
  /// Applied at the next `start` (the next launch).
  ConsentGeography get geography;
  set geography(ConsentGeography value);

  /// What the last `start` found: whether a form showed, and whether ads
  /// may be requested.
  bool get formShown;

  /// UMP's `reset`, so the next launch asks again.
  Future<void> resetConsent();
}

abstract interface class AdsGateway {
  /// UMP's consent update and form, then the request configuration and the
  /// SDK's start (research R6). Completes with whether ads may be requested.
  Future<bool> start(RequestConfig config);

  /// Loads [unit] unless one is held, loading, or waiting out a back-off.
  Future<void> load(AdUnit unit);

  /// [unit]'s readiness. Not an SDK call.
  ValueListenable<Readiness> readiness(AdUnit unit);

  /// Shows [unit] and resolves once its full-screen content is dismissed.
  /// [verification] only for `morningPiggy`.
  Future<ShowOutcome> show(AdUnit unit, {PiggyVerification? verification});
}
