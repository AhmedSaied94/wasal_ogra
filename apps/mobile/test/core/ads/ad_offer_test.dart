import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/domain/ad_offer.dart';
import 'package:wassal/core/economy/domain/op.dart';

// What each ad button shows (specs/018-m11-ads, data-model.md "Rules",
// T020): a table over `adOffer`.

/// Facts where every placement is offered, before each row changes one.
const _all = AdFacts(
  online: true,
  loaded: true,
  tutorialDone: true,
  resultDoublable: true,
  resultTutorialIndex: null,
  revivable: true,
  revived: false,
  trafficJamStock: 0,
  trafficJamAds: 0,
  tankFull: false,
  refillsToday: 0,
  refillCap: 3,
  piggyBannerShows: true,
);

void main() {
  test('every placement is offered with every fact in its favour', () {
    for (final placement in AdPlacement.values) {
      expect(adOffer(placement, _all), isA<Offered>(), reason: '$placement');
    }
  });

  group('result_double', () {
    AdOffer of(AdFacts facts) => adOffer(AdPlacement.resultDouble, facts);

    test('hidden on a failed, unpaid or doubled result', () {
      expect(of(_all.copyWith(resultDoublable: false)), isA<Hidden>());
    });

    test('hidden on tutorial trips 1 and 2, offered on trip 3', () {
      expect(of(_all.copyWith(resultTutorialIndex: 0)), isA<Hidden>());
      expect(of(_all.copyWith(resultTutorialIndex: 1)), isA<Hidden>());
      expect(
        of(_all.copyWith(resultTutorialIndex: 2, tutorialDone: false)),
        isA<Offered>(),
      );
    });
  });

  group('trip_revive', () {
    AdOffer of(AdFacts facts) => adOffer(AdPlacement.tripRevive, facts);

    test('hidden when revived or not revivable', () {
      expect(of(_all.copyWith(revived: true)), isA<Hidden>());
      expect(of(_all.copyWith(revivable: false)), isA<Hidden>());
    });
  });

  group('traffic_jam', () {
    AdOffer of(AdFacts facts) => adOffer(AdPlacement.trafficJam, facts);

    test('hidden with stock left, or with one ad used this trip', () {
      expect(of(_all.copyWith(trafficJamStock: 1)), isA<Hidden>());
      expect(of(_all.copyWith(trafficJamAds: 1)), isA<Hidden>());
    });
  });

  test('every placement but result_double is hidden before the tutorial is '
      'done', () {
    final facts = _all.copyWith(tutorialDone: false);
    for (final placement in AdPlacement.values) {
      expect(
        adOffer(placement, facts),
        placement == AdPlacement.resultDouble ? isA<Offered>() : isA<Hidden>(),
        reason: '$placement',
      );
    }
  });

  group('fuel_refill', () {
    AdOffer of(AdFacts facts) => adOffer(AdPlacement.fuelRefill, facts);

    test('hidden with a full tank', () {
      expect(of(_all.copyWith(tankFull: true)), isA<Hidden>());
    });

    test('offered at 2 today, with 1 left; limit reached at 3', () {
      final at2 = of(_all.copyWith(refillsToday: 2));
      expect(at2, isA<Offered>());
      expect((at2 as Offered).left, 1);
      expect(of(_all.copyWith(refillsToday: 3)), isA<LimitReached>());
      expect(of(_all.copyWith(refillsToday: 4)), isA<LimitReached>());
    });

    test('the cap comes from the facts (the tunable)', () {
      expect(
        of(_all.copyWith(refillsToday: 1, refillCap: 1)),
        isA<LimitReached>(),
      );
    });
  });

  group('morning_piggy', () {
    test("hidden when the banner's rule fails", () {
      expect(
        adOffer(
          AdPlacement.morningPiggy,
          _all.copyWith(piggyBannerShows: false),
        ),
        isA<Hidden>(),
      );
    });
  });

  test('NeedsNetwork offline, NotReady with nothing loaded', () {
    for (final placement in AdPlacement.values) {
      expect(
        adOffer(placement, _all.copyWith(online: false)),
        isA<NeedsNetwork>(),
        reason: '$placement',
      );
      expect(
        adOffer(placement, _all.copyWith(loaded: false)),
        isA<NotReady>(),
        reason: '$placement',
      );
    }
  });

  test('a hidden placement stays hidden offline', () {
    expect(
      adOffer(
        AdPlacement.tripRevive,
        _all.copyWith(revived: true, online: false),
      ),
      isA<Hidden>(),
    );
  });
}
