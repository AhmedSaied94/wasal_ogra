import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_kill_point.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/wire.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// Using and buying boosters during a trip (tasks.md T073,
// contracts/trip-controller.md "Booster use", "Booster purchase").

const _bag = BoosterId.changeBag;

/// The catalog price of [booster] in the sample pack.
int priceOf(BoosterId booster) =>
    sampleContent().price(SkuKind.booster, wireOf(booster))!.amount;

/// An economy with [stock] of each booster and [bonat].
Future<TestEconomy> stocked({
  Map<BoosterId, int> stock = const {_bag: 2},
  int bonat = 0,
  bool onFile = false,
}) => testEconomy(
  dbFile: onFile ? tempDbFile() : null,
  firstState: (nowMs) => EconomyState.newPlayer(
    fuelMax: 5,
    nowMs: nowMs,
  ).copyWith(inventory: stock, bonat: bonat),
);

final class _Killed implements Exception {}

/// Intents waiting to reach the economy.
Future<int> intents(TestEconomy economy) => rowCount(economy, 'trip_intent');

BoosterSlotView slotOf(TripController c, BoosterId booster) =>
    c.view!.boosters.singleWhere((s) => s.booster == booster);

void main() {
  group('with stock', () {
    test('applied first, written with its intent, then charged once', () async {
      final economy = await stocked();
      late final TripController c;
      TxnId? charged;
      final service = ScriptedEconomy(
        economy.service,
        onUseBooster: (id, booster) async {
          // The engine has it, and the record holds the command and the
          // intent, before the economy hears of it.
          expect(c.engine!.state.boostersUsed, [_bag]);
          final stored = (await DriftTripRecords(economy.db)
              .load(c.session!.startTxn))!;
          expect(stored.commandJsons.last, contains('UseBooster'));
          expect(stored.intents.single.requestTxn, id);
          charged = id;
          return economy.service.useBooster(id, booster: booster);
        },
      );
      c = testController(economy, service: service);
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      final tray = c.engine!.state.tray.total;

      await c.useBooster(_bag);
      await settle();
      expect(charged, isNotNull);
      expect(c.engine!.state.tray.total, greaterThan(tray));
      expect(economy.service.view.inventory[_bag], 1);
      expect(await opCount(economy, 'use_booster'), 1);
      expect(await intents(economy), 0);
      expect(slotOf(c, _bag).count, 1);
      expect(c.phase, TripPhase.running);
    });

    test('a kill after its transaction: the rebuild charges it once', () async {
      final before = await stocked(onFile: true);
      var armed = true;
      final live = testController(
        before,
        disposeAtTearDown: false,
        onKillPoint: (point) {
          if (armed && point == TripKillPoint.boosterUseWritten) {
            armed = false;
            throw _Killed();
          }
        },
      );
      await live.open('line_hay.01');
      advanceMs(live, 1000);
      await expectLater(live.useBooster(_bag), throwsA(isA<_Killed>()));
      expect(before.service.view.inventory[_bag], 2);
      expect(await intents(before), 1);

      final after = await reopen(before);
      final rebuilt = testController(after);
      await rebuilt.open('line_hay.01');
      await settle();
      expect(rebuilt.engine!.state.boostersUsed, [_bag]);
      expect(after.service.view.inventory[_bag], 1);
      expect(await opCount(after, 'use_booster'), 1);
      expect(await intents(after), 0);

      // Once: a second launch has nothing left to send.
      final again = await reopen(after);
      await testController(again).open('line_hay.01');
      await settle();
      expect(again.service.view.inventory[_bag], 1);
      expect(await opCount(again, 'use_booster'), 1);
    });

    test(
      'a kill inside its transaction leaves neither use nor charge',
      () async {
        final before = await stocked(onFile: true);
        final live = testController(
          before,
          disposeAtTearDown: false,
          onKillPoint: (point) {
            if (point == TripKillPoint.boosterCommandRow) throw _Killed();
          },
        );
        await live.open('line_hay.01');
        advanceMs(live, 1000);
        await expectLater(live.useBooster(_bag), throwsA(isA<_Killed>()));

        final after = await reopen(before);
        final rebuilt = testController(after);
        await rebuilt.open('line_hay.01');
        await settle();
        expect(rebuilt.engine!.state.boostersUsed, isEmpty);
        expect(after.service.view.inventory[_bag], 2);
        expect(await opCount(after, 'use_booster'), 0);
        expect(await intents(after), 0);
      },
    );

    test('a failed charge keeps the intent; the next use sends both', () async {
      final economy = await stocked();
      var fail = true;
      final ids = <TxnId>[];
      final service = ScriptedEconomy(
        economy.service,
        onUseBooster: (id, booster) {
          ids.add(id);
          if (!fail) return null;
          fail = false;
          return Future.value(const OpWriteFailed());
        },
      );
      final c = testController(economy, service: service);
      await c.open('line_hay.01');
      advanceMs(c, 1000);

      await c.useBooster(_bag);
      await settle();
      expect(c.engine!.state.boostersUsed, [_bag]);
      expect(economy.service.view.inventory[_bag], 2);
      expect(await intents(economy), 1);

      await c.useBooster(_bag);
      await settle();
      expect(c.engine!.state.boostersUsed, [_bag, _bag]);
      // The first id again, then the second's.
      expect(ids, hasLength(3));
      expect(ids[1], ids[0]);
      expect(economy.service.view.inventory[_bag] ?? 0, 0);
      expect(await opCount(economy, 'use_booster'), 2);
      expect(await intents(economy), 0);
    });

    test('a use not charged yet counts: the next tap opens the card', () async {
      final economy = await stocked(stock: {_bag: 1});
      final gate = Completer<void>();
      final service = ScriptedEconomy(
        economy.service,
        onUseBooster: (id, booster) async {
          await gate.future;
          return economy.service.useBooster(id, booster: booster);
        },
      );
      final c = testController(economy, service: service);
      await c.open('line_hay.01');
      advanceMs(c, 1000);

      final first = c.useBooster(_bag);
      await settle();
      expect(slotOf(c, _bag).count, 0);
      await c.useBooster(_bag);
      expect(c.engine!.state.boostersUsed, [_bag]);
      expect(c.phase, TripPhase.boosterCard);

      gate.complete();
      await first;
      await settle();
      expect(economy.service.view.inventory[_bag] ?? 0, 0);
      expect(await opCount(economy, 'use_booster'), 1);
    });

    test('a use not charged is charged before the result', () async {
      final economy = await stocked();
      var fail = true;
      final service = ScriptedEconomy(
        economy.service,
        onUseBooster: (id, booster) =>
            fail ? Future.value(const OpWriteFailed()) : null,
      );
      final c = testController(economy, service: service);
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      await c.useBooster(_bag);
      await settle();
      expect(await intents(economy), 1);

      c.pause(PauseReason.button);
      await c.leave();
      await settle();
      // Still failing: the result waits, the trip stays open.
      expect(c.model.retry, TripRetry.result);
      expect(c.model.exit, isNull);
      expect(economy.service.view.unfinished, isNotNull);
      expect(await intents(economy), 1);

      fail = false;
      await c.retry();
      await settle();
      expect(await opCount(economy, 'use_booster'), 1);
      expect(economy.service.view.inventory[_bag], 1);
      expect(economy.service.view.unfinished, isNull);
      expect(economy.service.view.lastResult!.outcome, TripOutcome.abandoned);
      expect(await intents(economy), 0);
      expect(c.model.exit, isA<ExitToHome>());
    });

    test('a refused charge drops the intent; the use stands', () async {
      final economy = await stocked();
      final service = ScriptedEconomy(
        economy.service,
        onUseBooster: (id, booster) =>
            Future.value(const OpRefused(EconomyRefusal.noneLeft)),
      );
      final c = testController(economy, service: service);
      await c.open('line_hay.01');
      advanceMs(c, 1000);

      await c.useBooster(_bag);
      await settle();
      expect(c.engine!.state.boostersUsed, [_bag]);
      expect(await intents(economy), 0);
      expect(c.phase, TripPhase.running);
    });

    test('traffic jams stop at the limit and the slot turns off', () async {
      final limit = bundledParams(LineId.lineHay).boosterTrafficJamMaxPerTrip;
      final economy = await stocked(stock: {BoosterId.trafficJam: limit + 2});
      final c = testController(economy);
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      for (var i = 0; i < limit; i++) {
        expect(slotOf(c, BoosterId.trafficJam).enabled, isTrue);
        await c.useBooster(BoosterId.trafficJam);
      }
      await settle();
      expect(slotOf(c, BoosterId.trafficJam).enabled, isFalse);

      await c.useBooster(BoosterId.trafficJam);
      await settle();
      expect(c.engine!.state.boostersUsed, hasLength(limit));
      expect(economy.service.view.inventory[BoosterId.trafficJam], 2);
      expect(c.view!.rejection?.code, RejectionCode.boosterLimit);
    });
  });

  group('none left', () {
    test('opens the card with the clock stopped', () async {
      final economy = await stocked(stock: const {}, bonat: 50);
      final c = testController(economy);
      await c.open('line_hay.01');
      advanceMs(c, 1000);

      await c.useBooster(_bag);
      expect(c.phase, TripPhase.boosterCard);
      expect(c.engine!.status, TripStatus.paused);
      final card = c.model.boosterCard!;
      expect(card.booster, _bag);
      expect(card.priceBonat, priceOf(_bag));
      expect(card.bonat, 50);
      expect(card.shortBy, isNull);
      final tMs = c.engine!.state.tMs;
      advanceMs(c, 1000);
      expect(c.engine!.state.tMs, tMs);
    });

    test('buying charges the price, uses it, and resumes', () async {
      final economy = await stocked(stock: const {}, bonat: 50);
      final c = testController(economy);
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      await c.useBooster(_bag);

      await c.buyBooster();
      await settle();
      expect(economy.service.view.bonat, 50 - priceOf(_bag));
      expect(economy.service.view.inventory[_bag] ?? 0, 0);
      expect(c.engine!.state.boostersUsed, [_bag]);
      expect(c.phase, TripPhase.running);
      expect(c.engine!.status, TripStatus.running);
      expect(c.model.boosterCard, isNull);
      expect(await opCount(economy, 'spend_bonat'), 1);
      expect(await opCount(economy, 'use_booster'), 1);
    });

    test('a second tap on «buy» buys and uses it once', () async {
      final economy = await stocked(stock: const {}, bonat: 50);
      final c = testController(economy);
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      await c.useBooster(_bag);

      await Future.wait([c.buyBooster(), c.buyBooster()]);
      await settle();
      expect(c.engine!.state.boostersUsed, [_bag]);
      expect(economy.service.view.bonat, 50 - priceOf(_bag));
      expect(economy.service.view.inventory[_bag] ?? 0, 0);
      expect(await opCount(economy, 'spend_bonat'), 1);
      expect(await opCount(economy, 'use_booster'), 1);
      expect(c.phase, TripPhase.running);
    });

    test('short of BONAT: the card stays and says how much', () async {
      final economy = await stocked(stock: const {}, bonat: 3);
      final c = testController(economy);
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      await c.useBooster(_bag);

      await c.buyBooster();
      expect(c.phase, TripPhase.boosterCard);
      expect(c.model.boosterCard!.shortBy, priceOf(_bag) - 3);
      expect(economy.service.view.bonat, 3);
      expect(c.engine!.state.boostersUsed, isEmpty);
    });

    test('not for sale: the slot turns off for the trip', () async {
      final economy = await stocked(stock: const {}, bonat: 50);
      final service = ScriptedEconomy(
        economy.service,
        onBuy: (id, kind, skuId) =>
            Future.value(const OpRefused(EconomyRefusal.notForSale)),
      );
      final c = testController(economy, service: service);
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      await c.useBooster(_bag);

      await c.buyBooster();
      expect(c.phase, TripPhase.running);
      expect(slotOf(c, _bag).enabled, isFalse);
      await c.useBooster(_bag);
      expect(c.phase, TripPhase.running);
    });

    test('a failed write keeps the card; the retry charges once', () async {
      final economy = await stocked(stock: const {}, bonat: 50);
      var fail = true;
      final ids = <TxnId>[];
      final service = ScriptedEconomy(
        economy.service,
        onBuy: (id, kind, skuId) {
          ids.add(id);
          if (!fail) return null;
          fail = false;
          return Future.value(const OpWriteFailed());
        },
      );
      final c = testController(economy, service: service);
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      await c.useBooster(_bag);

      await c.buyBooster();
      expect(c.phase, TripPhase.boosterCard);
      expect(c.model.retry, TripRetry.purchase);
      expect(economy.service.view.bonat, 50);

      await c.buyBooster();
      await settle();
      expect(ids, hasLength(2));
      expect(ids[1], ids[0]);
      expect(economy.service.view.bonat, 50 - priceOf(_bag));
      expect(c.model.retry, isNull);
      expect(c.phase, TripPhase.running);
    });

    test('closing the card resumes without charging', () async {
      final economy = await stocked(stock: const {}, bonat: 50);
      final c = testController(economy);
      await c.open('line_hay.01');
      advanceMs(c, 1000);
      await c.useBooster(_bag);

      c.closeBoosterCard();
      expect(c.phase, TripPhase.running);
      expect(c.engine!.status, TripStatus.running);
      expect(economy.service.view.bonat, 50);
      expect(c.engine!.state.boostersUsed, isEmpty);
    });
  });
}
