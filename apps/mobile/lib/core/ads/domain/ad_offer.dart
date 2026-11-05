// What an ad button shows now (specs/018-m11-ads, data-model.md "Rules",
// research R9, R15). Pure: `AdsService` gathers the facts from the caches
// the phone already holds, and the buttons draw the answer.
import 'package:wassal/core/economy/domain/op.dart' show AdPlacement;

/// Everything `adOffer` decides from. A fact that doesn't concern a
/// placement is ignored for it.
final class AdFacts {
  const AdFacts({
    required this.online,
    required this.loaded,
    required this.tutorialDone,
    this.resultDoublable = false,
    this.resultTutorialIndex,
    this.revivable = false,
    this.revived = false,
    this.trafficJamStock = 0,
    this.trafficJamAds = 0,
    this.tankFull = true,
    this.refillsToday = 0,
    this.refillCap = 0,
    this.piggyBannerShows = false,
  });

  final bool online;

  /// The placement's unit holds a loaded ad.
  final bool loaded;
  final bool tutorialDone;

  /// The latest result finished, paid and isn't doubled yet.
  final bool resultDoublable;

  /// The finished trip's index in the tutorial (0-based), or null when it
  /// isn't a tutorial trip (M07's `TutorialPlan`, research R15).
  final int? resultTutorialIndex;

  /// The trip failed in a way a revive can undo.
  final bool revivable;
  final bool revived;

  /// «زحمة» boosters held, and «زحمة» ads used this trip.
  final int trafficJamStock;
  final int trafficJamAds;
  final bool tankFull;

  /// Refill ads on today's game day, and the daily cap (the tunable).
  final int refillsToday;
  final int refillCap;

  /// The piggy banner's rule (research R11): the cached block says
  /// available, for today, and today's attempt hasn't ended.
  final bool piggyBannerShows;

  AdFacts copyWith({
    bool? online,
    bool? loaded,
    bool? tutorialDone,
    bool? resultDoublable,
    int? resultTutorialIndex,
    bool? revivable,
    bool? revived,
    int? trafficJamStock,
    int? trafficJamAds,
    bool? tankFull,
    int? refillsToday,
    int? refillCap,
    bool? piggyBannerShows,
  }) => AdFacts(
    online: online ?? this.online,
    loaded: loaded ?? this.loaded,
    tutorialDone: tutorialDone ?? this.tutorialDone,
    resultDoublable: resultDoublable ?? this.resultDoublable,
    resultTutorialIndex: resultTutorialIndex ?? this.resultTutorialIndex,
    revivable: revivable ?? this.revivable,
    revived: revived ?? this.revived,
    trafficJamStock: trafficJamStock ?? this.trafficJamStock,
    trafficJamAds: trafficJamAds ?? this.trafficJamAds,
    tankFull: tankFull ?? this.tankFull,
    refillsToday: refillsToday ?? this.refillsToday,
    refillCap: refillCap ?? this.refillCap,
    piggyBannerShows: piggyBannerShows ?? this.piggyBannerShows,
  );
}

/// What a button shows.
sealed class AdOffer {
  const AdOffer();
}

/// Ready: one tap shows the ad. [left] is the refills left today, for
/// `fuel_refill` only.
final class Offered extends AdOffer {
  const Offered({this.left});

  final int? left;
}

/// Online, but no ad is loaded yet.
final class NotReady extends AdOffer {
  const NotReady();
}

/// `fuel_refill`'s daily cap is reached.
final class LimitReached extends AdOffer {
  const LimitReached();
}

final class NeedsNetwork extends AdOffer {
  const NeedsNetwork();
}

/// The placement doesn't apply now: the button takes no space.
final class Hidden extends AdOffer {
  const Hidden();
}

/// Tutorial trips 1 and 2 have no ×2 (spec Clarifications, research R15).
const _firstDoubledTutorialTrip = 2;

bool _applies(AdPlacement placement, AdFacts f) {
  if (placement != AdPlacement.resultDouble && !f.tutorialDone) return false;
  return switch (placement) {
    AdPlacement.resultDouble =>
      f.resultDoublable &&
          (f.resultTutorialIndex == null ||
              f.resultTutorialIndex! >= _firstDoubledTutorialTrip),
    AdPlacement.tripRevive => f.revivable && !f.revived,
    AdPlacement.trafficJam => f.trafficJamStock == 0 && f.trafficJamAds == 0,
    AdPlacement.fuelRefill => !f.tankFull,
    AdPlacement.morningPiggy => f.piggyBannerShows,
  };
}

AdOffer adOffer(AdPlacement placement, AdFacts facts) {
  if (!_applies(placement, facts)) return const Hidden();
  if (!facts.online) return const NeedsNetwork();
  final refill = placement == AdPlacement.fuelRefill;
  if (refill && facts.refillsToday >= facts.refillCap) {
    return const LimitReached();
  }
  if (!facts.loaded) return const NotReady();
  return Offered(left: refill ? facts.refillCap - facts.refillsToday : null);
}
