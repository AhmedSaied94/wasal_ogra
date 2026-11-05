import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_trip_offers.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_kill_point.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../../helpers/ads.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/fake_ads_gateway.dart';
import '../../../helpers/trip.dart';

// The trip's rewarded ads (specs/018-m11-ads, US2, contracts/seams.md,
// T036): the revive by ad and the ad «زحمة», over the real ads service and
// the fake gateway, which fails the test on any call while the engine runs.

const _jam = BoosterId.trafficJam;

final class _Killed implements Exception {}

/// The service ready over [economy], and a controller wired to it.
Future<(AdsRig, TripController)> _rig(
  TestEconomy economy, {
  FixedTrip? fixed,
  FakeAdsGateway? gateway,
  void Function(TripKillPoint point)? onKillPoint,
  bool disposeAtTearDown = true,
  Economy? service,
}) async {
  final rig = await AdsRig.open(economy: economy, gateway: gateway);
  await rig.service.ensureReady();
  final c = testController(
    economy,
    service: service,
    fixed: fixed,
    ads: AdsTripOffers(rig.service),
    running: rig.probe,
    onKillPoint: onKillPoint,
    disposeAtTearDown: disposeAtTearDown,
  );
  return (rig, c);
}

/// A trip that fails on its own (`ending__revived`, which a revive saves).
FixedTrip _failing() {
  final f = loadFixture('ending__revived');
  return FixedTrip(definition: f.definition, params: f.params, seed: f.seed);
}

String get _failingId => _failing().definition.tripId;

void _runToFailure(TripController c) {
  while (c.phase == TripPhase.running) {
    c.advance(const Duration(milliseconds: engineStepMs));
  }
}

Future<int> _intents(TestEconomy economy, String kind) async {
  final rows = await economy.db
      .customSelect(
        'SELECT COUNT(*) AS n FROM trip_intent WHERE kind = ?',
        variables: [Variable.withString(kind)],
      )
      .getSingle();
  return rows.read<int>('n');
}

Future<TestEconomy> _noJams({bool onFile = false}) =>
    stockedEconomy(stock: const {_jam: 0}, onFile: onFile);

void main() {
  group('the ad slot while the trip runs', () {
    Future<(TripController, SpyTripAdOffers, void Function(int))> open() async {
      final economy = await _noJams();
      var now = 1000000;
      TripController? controller;
      final spy = SpyTripAdOffers(
        engineStatus: () => controller?.engine?.status,
      )..offered[AdPlacement.trafficJam] = AdSlot.ready;
      final c = testController(economy, ads: spy, nowMs: () => now);
      controller = c;
      await c.open('line_hay.01');
      advanceMs(c, 100);
      return (c, spy, (int ms) => now += ms);
    }

    bool offered(TripController c) =>
        c.view!.boosters.singleWhere((s) => s.booster == _jam).adOffered;

    test('is asked at most once a second, not every frame', () async {
      final (c, spy, _) = await open();
      spy.slotAsks = 0;
      advanceMs(c, 3000);
      expect(spy.slotAsks, 0);
      expect(offered(c), isTrue);
    });

    test('follows the clock', () async {
      final (c, spy, tick) = await open();
      spy.offered[AdPlacement.trafficJam] = AdSlot.hidden;
      advanceMs(c, 100);
      expect(offered(c), isTrue);
      tick(1000);
      advanceMs(c, 100);
      expect(offered(c), isFalse);
    });

    test('follows a change at once', () async {
      final (c, spy, _) = await open();
      spy.offer(AdPlacement.trafficJam, AdSlot.hidden);
      advanceMs(c, 100);
      expect(offered(c), isFalse);
    });
  });

  group('reviveWithAd', () {
    test('Rewarded: the trip_revive reward, then the Revive', () async {
      final economy = await stockedEconomy();
      final (rig, c) = await _rig(economy, fixed: _failing());
      await c.open(_failingId);
      _runToFailure(c);
      expect(c.phase, TripPhase.failed);
      expect(c.view!.failSummary!.reviveAd, AdSlot.ready);

      await c.reviveWithAd();
      expect(rig.gateway.count('show', AdUnit.tripRevive), 1);
      expect(await opCount(economy, 'ad_reward'), 1);
      expect(economy.service.view.unfinished!.revived, isTrue);
      expect(c.engine!.state.revived, isTrue);
      expect(c.engine!.state.reputation, c.session!.params.repReviveTo);
      expect(c.phase, TripPhase.running);
    });

    test('Closed: nothing changes, and the card stays', () async {
      final economy = await stockedEconomy();
      final gateway = FakeAdsGateway()
        ..script(AdUnit.tripRevive, [const Closed()]);
      final (_, c) = await _rig(economy, fixed: _failing(), gateway: gateway);
      await c.open(_failingId);
      _runToFailure(c);
      await c.reviveWithAd();
      expect(await opCount(economy, 'ad_reward'), 0);
      expect(c.engine!.state.revived, isFalse);
      expect(c.phase, TripPhase.failed);
    });

    test('once revived, the ad is not offered', () async {
      final economy = await stockedEconomy();
      final (rig, c) = await _rig(economy, fixed: _failing());
      await c.open(_failingId);
      _runToFailure(c);
      await c.reviveWithAd();
      _runToFailure(c);
      if (c.phase == TripPhase.failed) {
        expect(c.view!.failSummary?.reviveAd ?? AdSlot.hidden, AdSlot.hidden);
        await c.reviveWithAd();
      }
      expect(rig.gateway.count('show', AdUnit.tripRevive), 1);
      expect(await opCount(economy, 'ad_reward'), 1);
    });

    group('a watched ad whose reward fails to save', () {
      /// The first [fails] saves fail; the ids tried go in [ids].
      ScriptedEconomy failing(
        TestEconomy economy,
        List<TxnId> ids,
        int fails,
      ) => ScriptedEconomy(
        economy.service,
        onApplyAdReward: (id, _) {
          ids.add(id);
          return ids.length <= fails
              ? Future.value(const OpWriteFailed())
              : null;
        },
      );

      test('the retry revives with the same id and no second ad', () async {
        final economy = await stockedEconomy();
        final ids = <TxnId>[];
        final (rig, c) = await _rig(
          economy,
          fixed: _failing(),
          service: failing(economy, ids, 2),
        );
        await c.open(_failingId);
        _runToFailure(c);

        await c.reviveWithAd();
        expect(rig.gateway.count('show', AdUnit.tripRevive), 1);
        expect(c.engine!.state.revived, isFalse);
        expect(c.phase, TripPhase.failed);
        expect(c.model.retry, TripRetry.revive);
        // Tappable with no ad loaded: nothing more is asked of the player.
        rig.gateway.setReadiness(AdUnit.tripRevive, Readiness.notLoaded);
        expect(c.view!.failSummary!.reviveAd, AdSlot.ready);

        await c.retry();
        expect(rig.gateway.count('show', AdUnit.tripRevive), 1);
        expect(ids.toSet(), hasLength(1));
        expect(c.engine!.state.revived, isTrue);
        expect(c.model.retry, isNull);
        expect(c.phase, TripPhase.running);
      });

      test('the ad button does the same', () async {
        final economy = await stockedEconomy();
        final ids = <TxnId>[];
        final (rig, c) = await _rig(
          economy,
          fixed: _failing(),
          service: failing(economy, ids, 2),
        );
        await c.open(_failingId);
        _runToFailure(c);
        await c.reviveWithAd();
        await c.reviveWithAd();
        expect(rig.gateway.count('show', AdUnit.tripRevive), 1);
        expect(c.engine!.state.revived, isTrue);
      });

      test('the BONAT button charges nothing for what the ad paid', () async {
        final economy = await stockedEconomy(bonat: 100);
        final ids = <TxnId>[];
        final (_, c) = await _rig(
          economy,
          fixed: _failing(),
          service: failing(economy, ids, 2),
        );
        await c.open(_failingId);
        _runToFailure(c);
        await c.reviveWithAd();
        await c.revive();
        expect(c.engine!.state.revived, isTrue);
        expect(economy.service.view.bonat, 100);
        expect(await opCount(economy, 'spend_bonat'), 0);
      });
    });

    test(
      'refused after the ad: the offer goes, so no second ad is wasted',
      () async {
        final economy = await stockedEconomy();
        final (rig, c) = await _rig(
          economy,
          fixed: _failing(),
          service: ScriptedEconomy(
            economy.service,
            onApplyAdReward: (_, _) =>
                Future.value(const OpRefused(EconomyRefusal.noTrip)),
          ),
        );
        await c.open(_failingId);
        _runToFailure(c);
        await c.reviveWithAd();
        expect(c.model.retry, isNull);
        expect(c.view!.failSummary?.reviveAd ?? AdSlot.hidden, AdSlot.hidden);
        await c.reviveWithAd();
        expect(rig.gateway.count('show', AdUnit.tripRevive), 1);
      },
    );

    test('a kill after the reward: the reopen revives once', () async {
      final economy = await stockedEconomy(onFile: true);
      final (_, live) = await _rig(
        economy,
        fixed: _failing(),
        disposeAtTearDown: false,
        onKillPoint: (point) {
          if (point == TripKillPoint.adRewardApplied) throw _Killed();
        },
      );
      await live.open(_failingId);
      _runToFailure(live);
      await expectLater(live.reviveWithAd(), throwsA(isA<_Killed>()));
      expect(live.engine!.state.revived, isFalse);

      final after = await reopen(economy);
      final (rig, c) = await _rig(after, fixed: _failing());
      await c.open(_failingId);
      expect(c.engine!.state.revived, isTrue);
      expect(c.phase, TripPhase.paused);
      expect(await opCount(after, 'ad_reward'), 1);
      // A resume at launch makes no gateway call.
      expect(rig.gateway.count('show'), 0);
    });
  });

  group('trafficJamWithAd', () {
    Future<(AdsRig, TripController)> openCard(
      TestEconomy economy, {
      FakeAdsGateway? gateway,
      void Function(TripKillPoint point)? onKillPoint,
      bool disposeAtTearDown = true,
    }) async {
      final pair = await _rig(
        economy,
        gateway: gateway,
        onKillPoint: onKillPoint,
        disposeAtTearDown: disposeAtTearDown,
      );
      final c = pair.$2;
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      expect(
        c.view!.boosters.singleWhere((s) => s.booster == _jam).adOffered,
        isTrue,
      );
      await c.useBooster(_jam);
      expect(c.phase, TripPhase.boosterCard);
      expect(c.model.boosterCard!.ad, AdSlot.ready);
      return pair;
    }

    test(
      'Rewarded: the row, the reward, the booster, then the pause card',
      () async {
        final economy = await _noJams();
        final (rig, c) = await openCard(economy);
        await c.trafficJamWithAd();
        await settle();
        expect(rig.gateway.count('show', AdUnit.trafficJam), 1);
        expect(await opCount(economy, 'ad_reward'), 1);
        expect(economy.service.view.unfinished!.trafficJamAds, 1);
        expect(c.engine!.state.boostersUsed, [_jam]);
        expect(await _intents(economy, 'ad_reward'), 0);
        final stored = (await DriftTripRecords(economy.db)
            .load(c.session!.startTxn))!;
        expect(stored.commandJsons.last, contains('UseBooster'));
        expect(c.phase, TripPhase.paused);
        expect(c.model.pauseReason, PauseReason.ad);
        expect(economy.service.view.inventory[_jam] ?? 0, 0);

        c.resume();
        expect(c.phase, TripPhase.running);
      },
    );

    test(
      'a reward that fails to save: the retry uses it with no second ad',
      () async {
        final economy = await _noJams();
        final ids = <TxnId>[];
        final service = ScriptedEconomy(
          economy.service,
          onApplyAdReward: (id, _) {
            ids.add(id);
            return ids.length <= 2 ? Future.value(const OpWriteFailed()) : null;
          },
        );
        final rig = await AdsRig.open(economy: economy);
        await rig.service.ensureReady();
        final c = testController(
          economy,
          service: service,
          ads: AdsTripOffers(rig.service),
          running: rig.probe,
        );
        await c.open('line_hay.01');
        advanceMs(c, 1000);
        await c.useBooster(_jam);
        await c.trafficJamWithAd();
        await settle();
        expect(rig.gateway.count('show', AdUnit.trafficJam), 1);
        expect(c.phase, TripPhase.boosterCard);
        expect(c.model.retry, TripRetry.purchase);
        expect(c.engine!.state.boostersUsed, isEmpty);
        expect(await _intents(economy, 'ad_reward'), 1);
        rig.gateway.setReadiness(AdUnit.trafficJam, Readiness.notLoaded);
        expect(c.model.boosterCard!.ad, AdSlot.ready);

        await c.retry();
        await settle();
        expect(rig.gateway.count('show', AdUnit.trafficJam), 1);
        expect(ids.toSet(), hasLength(1));
        expect(c.engine!.state.boostersUsed, [_jam]);
        expect(await _intents(economy, 'ad_reward'), 0);
        expect(c.model.retry, isNull);
        expect(c.phase, TripPhase.paused);
      },
    );

    test('Closed: the card stays, with nothing charged', () async {
      final economy = await _noJams();
      final gateway = FakeAdsGateway()
        ..script(AdUnit.trafficJam, [const Closed()]);
      final (_, c) = await openCard(economy, gateway: gateway);
      await c.trafficJamWithAd();
      expect(c.phase, TripPhase.boosterCard);
      expect(await opCount(economy, 'ad_reward'), 0);
      expect(await _intents(economy, 'ad_reward'), 0);
      expect(c.engine!.state.boostersUsed, isEmpty);
    });

    for (final point in [
      TripKillPoint.adIntentWritten,
      TripKillPoint.adRewardApplied,
    ]) {
      test('a kill at ${point.name}: the reopen uses it once', () async {
        final economy = await _noJams(onFile: true);
        final (_, live) = await openCard(
          economy,
          disposeAtTearDown: false,
          onKillPoint: (p) {
            if (p == point) throw _Killed();
          },
        );
        await expectLater(live.trafficJamWithAd(), throwsA(isA<_Killed>()));
        expect(await _intents(economy, 'ad_reward'), 1);

        final after = await reopen(economy);
        final (rig, c) = await _rig(after);
        await c.open('line_hay.01');
        await settle();
        expect(c.engine!.state.boostersUsed, [_jam]);
        expect(await opCount(after, 'ad_reward'), 1);
        expect(after.service.view.unfinished!.trafficJamAds, 1);
        expect(await _intents(after, 'ad_reward'), 0);
        expect(rig.gateway.count('show'), 0);

        // Once: a second launch has nothing left to redeem.
        final again = await reopen(after);
        final (_, third) = await _rig(again);
        await third.open('line_hay.01');
        await settle();
        expect(third.engine!.state.boostersUsed, [_jam]);
        expect(await opCount(again, 'ad_reward'), 1);
      });
    }

    test('the app going to the background during the ad keeps the trip '
        'paused', () async {
      final economy = await _noJams();
      final (_, c) = await openCard(economy);
      final watching = c.trafficJamWithAd();
      c.pause(PauseReason.lifecycle);
      await watching;
      expect(c.phase, TripPhase.paused);
      expect(c.engine!.status, TripStatus.paused);
    });
  });
}
