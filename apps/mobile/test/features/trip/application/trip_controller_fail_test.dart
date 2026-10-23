import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_kill_point.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// Failing, the BONAT revive, and leaving or restarting from the failure
// card (tasks.md T082, contracts/trip-controller.md "Revive", "Leave",
// "Restart", "Opening").

final int revivePrice = sampleContent().price(SkuKind.revive, 'revive')!.amount;

/// An economy holding [bonat].
Future<TestEconomy> withBonat(int bonat, {bool onFile = false}) => testEconomy(
  dbFile: onFile ? tempDbFile() : null,
  firstState: (nowMs) =>
      EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(bonat: bonat),
);

FixedTrip fixedOf(String fixture, {TripDefinition? definition}) {
  final f = loadFixture(fixture);
  return FixedTrip(
    definition: definition ?? f.definition,
    params: f.params,
    seed: f.seed,
  );
}

/// `ending__failed` with two more passengers for the second station: it
/// fails at the first (four fights), and again at the second after a
/// revive (two more from `rep_revive_to`).
TripDefinition failsTwice() {
  final json = jsonDecode(
    jsonEncode(loadFixture('ending__failed').definition.toJson()),
  ) as Map<String, Object?>;
  final passengers = (json['passengers']! as List).cast<Map<String, Object?>>();
  json['passengers'] = [
    ...passengers,
    for (final (id, seat) in [('p5', 'B_m'), ('p6', 'B_l')])
      {
        ...passengers.first,
        'passenger_id': id,
        'seat_id': seat,
        'dest_station_id': 'mostashfa',
      },
  ];
  return TripDefinition.fromJson(json);
}

/// Steps [c] until its phase is [phase].
void untilPhase(TripController c, TripPhase phase, {int maxMs = 120000}) {
  for (var t = 0; t < maxMs && c.phase != phase; t += engineStepMs) {
    c.advance(const Duration(milliseconds: engineStepMs));
  }
  expect(c.phase, phase);
}

Future<TripController> openFailed(
  TestEconomy economy, {
  Economy? service,
  String fixture = 'ending__failed',
  TripDefinition? definition,
  void Function(TripKillPoint point)? onKillPoint,
  bool disposeAtTearDown = true,
}) async {
  final c = testController(
    economy,
    service: service,
    fixed: fixedOf(fixture, definition: definition),
    onKillPoint: onKillPoint,
    disposeAtTearDown: disposeAtTearDown,
  );
  await c.open('line_gamaa.01');
  untilPhase(c, TripPhase.failed);
  return c;
}

final class _Killed implements Exception {}

void main() {
  group('the failure', () {
    test('stops the trip, frowns, and offers the revive', () async {
      final c = await openFailed(await withBonat(revivePrice));
      final view = c.view!;
      expect(c.engine!.status, TripStatus.failed);
      expect(view.failSummary!.causes, [
        const FailCause(cause: RepCause.fight, count: 4),
      ]);
      expect(
        view.failSummary!.revive,
        ReviveOffer(priceBonat: revivePrice, affordable: true),
      );
      expect(view.passengers.every((p) => p.mood == 3), isTrue);
      // The clock stays where it failed.
      final at = c.engine!.state.tMs;
      c.advance(const Duration(seconds: 2));
      expect(c.engine!.state.tMs, at);
    });

    test('shows the revive unaffordable below its price', () async {
      final c = await openFailed(await withBonat(revivePrice - 1));
      expect(
        c.view!.failSummary!.revive,
        ReviveOffer(priceBonat: revivePrice, affordable: false),
      );
      await c.revive();
      expect(c.engine!.status, TripStatus.failed);
      expect(c.phase, TripPhase.failed);
    });

    test('a story trip failed by a fight offers no revive', () async {
      final c = await openFailed(
        await withBonat(revivePrice),
        fixture: 'ending__story_fight_fails',
      );
      expect(c.view!.failSummary!.causes, isNotEmpty);
      expect(c.view!.failSummary!.revive, isNull);
    });
  });

  group('revive', () {
    test('charges first, then revives, saves it and runs on', () async {
      final economy = await withBonat(revivePrice);
      late final TripController c;
      var bought = 0;
      final service = ScriptedEconomy(
        economy.service,
        onBuy: (id, kind, skuId) {
          expect(kind, SkuKind.revive);
          // Not revived until the economy says so.
          expect(c.engine!.state.revived, isFalse);
          bought++;
          return null;
        },
      );
      c = await openFailed(economy, service: service);
      await c.revive();
      await settle();

      expect(bought, 1);
      expect(c.engine!.state.revived, isTrue);
      expect(c.engine!.status, TripStatus.running);
      expect(c.engine!.state.reputation, c.session!.params.repReviveTo);
      expect(c.phase, TripPhase.running);
      expect(economy.service.view.bonat, 0);
      final stored = (await DriftTripRecords(economy.db)
          .load(c.session!.startTxn))!;
      expect(stored.commandJsons.last, contains('Revive'));
      expect(c.view!.failSummary, isNull);
    });

    test('insufficient_funds keeps the card', () async {
      final economy = await withBonat(revivePrice);
      final service = ScriptedEconomy(
        economy.service,
        onBuy: (_, _, _) =>
            Future.value(const OpRefused(EconomyRefusal.insufficientFunds)),
      );
      final c = await openFailed(economy, service: service);
      await c.revive();
      expect(c.phase, TripPhase.failed);
      expect(c.engine!.state.revived, isFalse);
      expect(c.view!.failSummary!.revive, isNotNull);
    });

    test('already_revived revives when the engine still allows it', () async {
      final economy = await withBonat(revivePrice);
      final service = ScriptedEconomy(
        economy.service,
        onBuy: (_, _, _) =>
            Future.value(const OpRefused(EconomyRefusal.alreadyRevived)),
      );
      final c = await openFailed(economy, service: service);
      await c.revive();
      expect(c.engine!.state.revived, isTrue);
      expect(c.phase, TripPhase.running);
      expect(economy.service.view.bonat, revivePrice);
    });

    test('a failed write applies nothing; the retry reuses the id', () async {
      final economy = await withBonat(revivePrice);
      final ids = <TxnId>[];
      final service = ScriptedEconomy(
        economy.service,
        onBuy: (id, _, _) {
          ids.add(id);
          return ids.length == 1 ? Future.value(const OpWriteFailed()) : null;
        },
      );
      final c = await openFailed(economy, service: service);
      await c.revive();
      expect(c.engine!.state.revived, isFalse);
      expect(c.phase, TripPhase.failed);
      expect(c.model.retry, TripRetry.revive);

      await c.retry();
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(1));
      expect(c.engine!.state.revived, isTrue);
      expect(c.model.retry, isNull);
      expect(economy.service.view.bonat, 0);
      expect(await opCount(economy, 'spend_bonat'), 1);
    });

    test('a kill after the charge: the rebuild revives, uncharged', () async {
      final before = await withBonat(revivePrice, onFile: true);
      final live = await openFailed(
        before,
        disposeAtTearDown: false,
        onKillPoint: (point) {
          if (point == TripKillPoint.reviveBought) throw _Killed();
        },
      );
      await expectLater(live.revive(), throwsA(isA<_Killed>()));
      expect(live.engine!.state.revived, isFalse);
      expect(before.service.view.unfinished!.revived, isTrue);

      final after = await reopen(before);
      final rebuilt = testController(after, fixed: fixedOf('ending__failed'));
      await rebuilt.open('line_gamaa.01');
      await settle();
      expect(rebuilt.engine!.state.revived, isTrue);
      // Back like any other trip: paused.
      expect(rebuilt.phase, TripPhase.paused);
      expect(after.service.view.bonat, 0);
      expect(await opCount(after, 'spend_bonat'), 1);
    });

    test('a second failure offers no revive', () async {
      final economy = await withBonat(2 * revivePrice);
      final c = await openFailed(economy, definition: failsTwice());
      await c.revive();
      expect(c.phase, TripPhase.running);
      untilPhase(c, TripPhase.failed);
      expect(c.view!.failSummary!.revive, isNull);
      // Waiting owed, the two also ran out of patience.
      expect(
        c.view!.failSummary!.causes.first,
        const FailCause(cause: RepCause.fight, count: 6),
      );
      await c.revive();
      expect(economy.service.view.bonat, revivePrice);
    });
  });

  group('from the card', () {
    test('«ارجع الموقف» records it failed, without Abandon', () async {
      final economy = await withBonat(0);
      final c = await openFailed(economy);
      await c.leave();
      await settle();
      expect(c.model.exit, isA<ExitToHome>());
      expect(economy.service.view.lastResult!.outcome, TripOutcome.failed);
      expect(economy.service.view.unfinished, isNull);
      expect(
        c.engine!.commandLog.map((e) => e.command).whereType<Abandon>(),
        isEmpty,
      );
      expect(await rowCount(economy, 'trip_record'), 0);
    });

    test('«عيد المشوار» records it failed and starts again', () async {
      final economy = await withBonat(0);
      final c = await openFailed(economy);
      final liters = economy.service.view.fuel.liters;
      await c.restart();
      await settle();
      expect(economy.service.view.lastResult!.outcome, TripOutcome.failed);
      expect(await opCount(economy, 'trip_start'), 2);
      expect(economy.service.view.fuel.liters, liters - 1);
      expect(c.phase, TripPhase.running);
      expect(c.engine!.status, TripStatus.running);
      expect(c.engine!.state.tMs, 0);
    });

    test('a failed trip comes back failed, with its card', () async {
      final before = await withBonat(revivePrice, onFile: true);
      final live = await openFailed(before, disposeAtTearDown: false);
      final at = live.engine!.state.tMs;

      final after = await reopen(before);
      final rebuilt = testController(after, fixed: fixedOf('ending__failed'));
      await rebuilt.open('line_gamaa.01');
      await settle();
      expect(rebuilt.phase, TripPhase.failed);
      expect(rebuilt.engine!.state.tMs, at);
      expect(
        rebuilt.view!.failSummary!.revive,
        ReviveOffer(priceBonat: revivePrice, affordable: true),
      );
      expect(after.service.view.bonat, revivePrice);
    });
  });
}
