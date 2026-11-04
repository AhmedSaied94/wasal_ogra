import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart' show TripOutcome;
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/ads/domain/ads_may_start.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';

import '../../helpers/ads.dart';
import '../../helpers/economy.dart';
import '../../helpers/fake_ads_gateway.dart';

// `AdsService` over the fake gateway and the real economy (specs/018-m11-ads,
// contracts/ads-gateway.md, T027, T029, T053, T057).

final _start = TxnId.parse('0192f3a1-7b2c-7d4e-8f00-0000000000aa');

/// A player with a paid result to double, an empty tank and no stock.
Future<TestEconomy> _player({int earnings = 85, bool doubled = false}) =>
    testEconomy(
      firstState: (nowMs) =>
          EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
            fuel: FuelState(liters: 0, countedFromMs: nowMs),
            lastResult: () => LastResult(
              startTxn: _start,
              outcome: TripOutcome.finished,
              earningsJenehat: earnings,
              doubled: doubled,
            ),
          ),
    );

Future<AdsRig> _ready({TestEconomy? economy}) async {
  final rig = await AdsRig.open(economy: economy ?? await _player());
  await rig.service.ensureReady();
  return rig;
}

Future<void> _settle() => pumpEventQueue();

var _rows = 0x300;

/// A refill row today that leaves the projection as it is (the tank stays
/// empty), as an earlier session's refill would read in the log.
Future<void> _refillRow(TestEconomy e) => e.db.customStatement(
  'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
  'content_version, fuel_max, fuel_regen_minutes) VALUES '
  "('0192f3a1-7b2c-7d4e-8f00-${(_rows++).toRadixString(16).padLeft(12, '0')}', "
  '\'ad_reward\', \'{"ad_placement":"fuel_refill"}\', '
  '${e.clock.nowMs()}, 1, 5, 20)',
);

void main() {
  group('ensureReady', () {
    test('starts once per launch with the request configuration', () async {
      final rig = await AdsRig.open();
      await rig.service.ensureReady();
      await rig.service.ensureReady();
      expect(rig.gateway.count('start'), 1);
      expect(rig.gateway.startedWith, adRequestConfig());
      expect(rig.gateway.startedWith!.rating, AdContentRating.t);
      expect(rig.gateway.startedWith!.childDirected, isFalse);
      expect(rig.gateway.startedWith!.underAgeOfConsent, isFalse);
      expect(rig.gateway.startedWith!.testDeviceIds, isEmpty);
    });

    test('never while a trip runs', () async {
      final rig = await AdsRig.open();
      rig.probe.value = true;
      await rig.service.ensureReady();
      expect(rig.gateway.calls, isEmpty);
      rig.probe.value = false;
      await rig.service.ensureReady();
      expect(rig.gateway.count('start'), 1);
    });

    test(
      'offline passes at once with nothing loaded, and starts later',
      () async {
        final rig = await AdsRig.open();
        rig.world.online = false;
        await rig.service.ensureReady();
        expect(rig.gateway.calls, isEmpty);
        expect(rig.service.canRequestAds, isFalse);
        rig.world.online = true;
        await rig.service.ensureReady();
        expect(rig.gateway.count('start'), 1);
      },
    );

    test('consent refused: no load, and every offer is not ready', () async {
      final rig = await AdsRig.open(
        economy: await _player(),
        gateway: FakeAdsGateway(canRequestAds: false),
      );
      await rig.service.ensureReady();
      expect(rig.gateway.methods, ['start']);
      expect(rig.service.offer(AdPlacement.resultDouble), isA<NotReady>());
      expect(rig.service.offer(AdPlacement.fuelRefill), isA<NotReady>());
      rig.service.preloadForNextTrip();
      expect(rig.gateway.count('load'), 0);
    });

    test('a shown and closed form: the loads follow', () async {
      final rig = await AdsRig.open(gateway: FakeAdsGateway(formShown: true));
      await rig.service.ensureReady();
      expect(rig.gateway.methods.first, 'start');
      expect(rig.gateway.count('load'), greaterThan(0));
    });
  });

  group('offer', () {
    test('reads caches only: no gateway call', () async {
      final rig = await _ready();
      final before = rig.gateway.calls.length;
      rig.probe.value = true;
      for (final placement in AdPlacement.values) {
        rig.service.offer(placement);
      }
      expect(rig.gateway.calls, hasLength(before));
    });

    test(
      'the ×2 is ready after the preload, and hidden on tutorial trips 1-2',
      () async {
        final rig = await AdsRig.open(
          economy: await _player(),
          tutorialTrips: ['t1', 't2', 't3'],
        );
        rig.world.tutorialDone = false;
        await rig.service.ensureReady();
        expect(
          rig.service.offer(AdPlacement.resultDouble, tripId: 't1'),
          isA<Hidden>(),
        );
        expect(
          rig.service.offer(AdPlacement.resultDouble, tripId: 't2'),
          isA<Hidden>(),
        );
        expect(
          rig.service.offer(AdPlacement.resultDouble, tripId: 't3'),
          isA<Offered>(),
        );
      },
    );

    test('emits offered once per offer', () async {
      final rig = await _ready();
      final events = <AdEvent>[];
      rig.service.events.listen(events.add);
      rig.service.offer(AdPlacement.resultDouble);
      rig.service.offer(AdPlacement.resultDouble);
      await _settle();
      expect(events.where((e) => e.kind == AdEventKind.offered), hasLength(1));
    });
  });

  group('watch', () {
    test('Rewarded applies the reward once, even on a double tap', () async {
      final rig = await _ready();
      final jenehat = rig.economy.service.view.jenehat;
      final first = rig.service.watch(AdPlacement.resultDouble);
      final second = rig.service.watch(AdPlacement.resultDouble);
      final outcomes = await Future.wait([first, second]);
      expect(outcomes[0], isA<RewardApplied>());
      expect(identical(outcomes[0], outcomes[1]), isTrue);
      expect(rig.gateway.count('show', AdUnit.resultDouble), 1);
      expect(rig.economy.service.view.jenehat, jenehat + 85);
      expect(rig.economy.service.pendingCount, 1);
      expect(rig.service.offer(AdPlacement.resultDouble), isA<Hidden>());
    });

    test('Closed and ShowFailed store nothing', () async {
      for (final outcome in const <ShowOutcome>[Closed(), ShowFailed()]) {
        final rig = await _ready();
        rig.gateway.script(AdUnit.resultDouble, [outcome]);
        expect(
          await rig.service.watch(AdPlacement.resultDouble),
          isA<NoReward>(),
        );
        expect(rig.economy.service.pendingCount, 0);
        expect(rig.settings.values[lastRewardedTripKey], isNull);
      }
    });

    test('not offered: no show', () async {
      final rig = await _ready(economy: await _player(doubled: true));
      expect(
        await rig.service.watch(AdPlacement.resultDouble),
        isA<NoReward>(),
      );
      expect(rig.gateway.count('show'), 0);
    });

    test('a refusal after the ad: the tank filled meanwhile', () async {
      final rig = await _ready();
      rig.gateway.script(AdUnit.fuelRefill, [
        Future(() async {
          await rig.economy.service.applyAdReward(
            rig.economy.service.newRequestId(),
            placement: AdPlacement.fuelRefill,
          );
          return const Rewarded();
        }),
      ]);
      final outcome = await rig.service.watch(AdPlacement.fuelRefill);
      expect((outcome as RewardRefused).code, EconomyRefusal.tankFull);
    });

    test('writes the rewarded trip count on Rewarded only', () async {
      final rig = await _ready();
      await rig.service.watch(AdPlacement.resultDouble);
      expect(rig.settings.values[lastRewardedTripKey], '0');
    });

    test("the refill's daily cap is checked before the show and before the "
        'apply', () async {
      final rig = await _ready();
      rig.world.tunables.refillCap = 1;
      await _refillRow(rig.economy);
      expect(await rig.service.watch(AdPlacement.fuelRefill), isA<NoReward>());
      expect(rig.gateway.count('show', AdUnit.fuelRefill), 0);
    });

    test('the cap reached while the ad runs refuses the reward', () async {
      final rig = await _ready();
      rig.world.tunables.refillCap = 1;
      rig.gateway.script(AdUnit.fuelRefill, [
        Future(() async {
          // Another refill lands in the log while the ad runs.
          await _refillRow(rig.economy);
          return const Rewarded();
        }),
      ]);
      final outcome = await rig.service.watch(AdPlacement.fuelRefill);
      expect((outcome as RewardRefused).code, EconomyRefusal.capReached);
    });
  });

  group('preloadForNextTrip', () {
    test('loads what the next trip and its result may offer', () async {
      final rig = await _ready();
      expect(
        {
          for (final c in rig.gateway.calls)
            if (c.method == 'load') c.unit,
        },
        {
          AdUnit.resultDouble,
          AdUnit.tripRevive,
          AdUnit.trafficJam,
          AdUnit.fuelRefill,
          AdUnit.interstitial,
        },
      );
    });

    test('only the ×2 before the tutorial is done', () async {
      final rig = await AdsRig.open();
      rig.world.tutorialDone = false;
      await rig.service.ensureReady();
      expect(
        {
          for (final c in rig.gateway.calls)
            if (c.method == 'load') c.unit,
        },
        {AdUnit.resultDouble},
      );
    });

    test('nothing before ensureReady', () async {
      final rig = await AdsRig.open();
      rig.service.preloadForNextTrip();
      expect(rig.gateway.calls, isEmpty);
    });
  });

  test('events: rewarded and loadFailed', () async {
    final rig = await _ready();
    final events = <AdEvent>[];
    rig.service.events.listen(events.add);
    await rig.service.watch(AdPlacement.resultDouble);
    rig.gateway.setReadiness(AdUnit.tripRevive, Readiness.failed);
    await _settle();
    expect(
      events.map((e) => e.kind),
      containsAll([AdEventKind.rewarded, AdEventKind.loadFailed]),
    );
  });

  group('adsMayStart (analysis U2)', () {
    test('false with 0 or 1 tutorial trips finished, true with 2 or done', () {
      expect(adsMayStart(tutorialDone: false, tutorialFinished: 0), isFalse);
      expect(adsMayStart(tutorialDone: false, tutorialFinished: 1), isFalse);
      expect(adsMayStart(tutorialDone: false, tutorialFinished: 2), isTrue);
      expect(adsMayStart(tutorialDone: true, tutorialFinished: 0), isTrue);
    });

    test('the checkpoint before trip 2 calls nothing; before trip 3 it starts '
        'and preloads the ×2', () async {
      final rig = await AdsRig.open();
      rig.world
        ..tutorialDone = false
        ..tutorialFinished = 1;
      await rig.service.betweenTrips();
      expect(rig.gateway.calls, isEmpty);
      rig.world.tutorialFinished = 2;
      await rig.service.betweenTrips();
      expect(rig.gateway.methods.first, 'start');
      expect(rig.gateway.count('load', AdUnit.resultDouble), greaterThan(0));
      expect(rig.gateway.count('load', AdUnit.interstitial), 0);
    });
  });

  group('betweenTrips: the interstitial (T057)', () {
    Future<AdsRig> atTrips(int trips) async {
      final rig = await AdsRig.open(
        gateway: FakeAdsGateway(ready: {AdUnit.interstitial}),
      );
      for (var i = 0; i < trips; i++) {
        await rig.economy.db.customStatement(
          'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
          'content_version, fuel_max, fuel_regen_minutes) VALUES '
          "('0192f3a1-7b2c-7d4e-8f00-${(0x500 + i).toRadixString(16).padLeft(12, '0')}', "
          "'trip_start', '{}', 1, 1, 5, 20)",
        );
      }
      return rig;
    }

    test('due and loaded: shown, the count written, and a reload', () async {
      final rig = await atTrips(10);
      await rig.service.betweenTrips();
      expect(rig.gateway.count('show', AdUnit.interstitial), 1);
      expect(rig.settings.values[lastInterstitialTripKey], '10');
      // The preload, then the reload after the show.
      final last = rig.gateway.calls.last;
      expect((last.method, last.unit), ('load', AdUnit.interstitial));
    });

    test('ShowFailed writes nothing (FR-022)', () async {
      final rig = await atTrips(10);
      rig.gateway.script(AdUnit.interstitial, [const ShowFailed()]);
      await rig.service.betweenTrips();
      expect(rig.settings.values[lastInterstitialTripKey], isNull);
    });

    test('not due: no show', () async {
      final rig = await atTrips(9);
      await rig.service.betweenTrips();
      expect(rig.gateway.count('show'), 0);
    });

    test('remove_ads bought mid-session: the next checkpoint passes', () async {
      final rig = await atTrips(10);
      rig.world.entitlements = const Entitlements(
        removeAds: true,
        seasonPasses: [],
        noInterstitials: false,
        fuelMaxBonus: 0,
      );
      await rig.service.betweenTrips();
      expect(rig.gateway.count('show'), 0);
    });

    test('right after a rewarded ad paid: no show', () async {
      final rig = await atTrips(10);
      await rig.settings.writeString(lastRewardedTripKey, '10');
      await rig.service.betweenTrips();
      expect(rig.gateway.count('show'), 0);
    });

    test('a trip started during its awaits: no show (review M1)', () async {
      final rig = await atTrips(10);
      final passing = rig.service.betweenTrips();
      rig.probe.value = true;
      await passing;
      expect(rig.gateway.count('show'), 0);
      rig.probe.value = false;
    });

    test('emits interstitialShown', () async {
      final rig = await atTrips(10);
      final events = <AdEvent>[];
      rig.service.events.listen(events.add);
      await rig.service.betweenTrips();
      await _settle();
      expect(
        events.map((e) => e.kind),
        contains(AdEventKind.interstitialShown),
      );
    });
  });

  group('the piggy banner rule', () {
    test('shows with an available block for today, until attempted', () async {
      final rig = await _ready();
      expect(rig.service.offer(AdPlacement.morningPiggy), isA<Hidden>());
      rig.world.adsBlock = const AdsBlock(piggyAvailable: true, unseen: []);
      rig.gateway.setReadiness(AdUnit.morningPiggy, Readiness.ready);
      expect(rig.service.offer(AdPlacement.morningPiggy), isA<Offered>());
      rig.world.gameDay = '2000-01-01';
      expect(rig.service.offer(AdPlacement.morningPiggy), isA<Hidden>());
      rig.world.gameDay = null;
      rig.service.markPiggyAttempted();
      expect(rig.service.offer(AdPlacement.morningPiggy), isA<Hidden>());
    });
  });
}
