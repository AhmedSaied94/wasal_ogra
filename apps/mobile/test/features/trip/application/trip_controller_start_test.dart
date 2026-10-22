import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/config/tunable_snapshot.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/glossary/ids.dart' as glossary;
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_kill_point.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

void main() {
  test('starts: record first, then the start; fuel drops by one', () async {
    final economy = await testEconomy();
    final fuelBefore = economy.service.view.fuel.liters;
    TxnId? recorded;
    final controller = testController(
      economy,
      onKillPoint: (point) {
        if (point == TripKillPoint.recordCreated) {
          // The record exists before the economy hears of the start.
          expect(economy.service.view.unfinished, isNull);
        }
      },
    );
    await controller.open('line_hay.01');
    expect(controller.phase, TripPhase.running);
    final unfinished = economy.service.view.unfinished!;
    recorded = unfinished.startTxn;
    expect(controller.session!.startTxn, recorded);
    expect(await rowCount(economy, 'trip_record'), 1);
    expect(economy.service.view.fuel.liters, fuelBefore - 1);
    expect(controller.view, isNotNull);
    expect(controller.view!.phase, TripPhase.running);
  });

  test('params and the line tunables come from the config', () async {
    final economy = await testEconomy();
    final controller = testController(economy);
    await controller.open('line_gamaa.01');
    final facts = controller.session!.facts;
    final config = bundledConfig();
    expect(
      facts.params.toJson(),
      TripParams.fromTunables(
        tunableSnapshot(config),
        LineId.lineGamaa,
      ).toJson(),
    );
    expect(
      facts.bubbleMinMs,
      config.read(Tunable.tripBubbleMinMs(glossary.LineId.lineGamaa)),
    );
    expect(facts.hintMode, HintMode.firstTime);
  });

  test('no fuel: the record is deleted and the next liter shown', () async {
    final economy = await testEconomy(
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(fuel: FuelState(liters: 0, countedFromMs: nowMs)),
    );
    final controller = testController(economy);
    await controller.open('line_hay.01');
    await settle();
    expect(controller.phase, TripPhase.noFuel);
    expect(controller.model.nextLiterAtMs, isNotNull);
    expect(await rowCount(economy, 'trip_record'), 0);
  });

  test('a trip the economy does not know ends to Home', () async {
    final economy = await testEconomy();
    economy.content = TripContent(sampleContent(), hidden: {'line_hay.01'});
    final controller = testController(economy, content: sampleContent);
    await controller.open('line_hay.01');
    await settle();
    expect(controller.phase, TripPhase.ended);
    expect(controller.model.exit, const ExitToHome());
    expect(await rowCount(economy, 'trip_record'), 0);
  });

  test('a trip missing from the pack ends to Home', () async {
    final economy = await testEconomy();
    final controller = testController(economy);
    await controller.open('line_hay.42');
    expect(controller.phase, TripPhase.ended);
    expect(controller.model.exit, const ExitToHome());
  });

  test('a start refused for an unfinished trip that isn\'t there, twice, '
      'goes Home', () async {
    final economy = await testEconomy();
    var starts = 0;
    final service = ScriptedEconomy(
      economy.service,
      onStartTrip: (id, tripId) {
        starts++;
        return Future.value(const OpRefused(EconomyRefusal.tripUnfinished));
      },
    );
    final controller = testController(economy, service: service);
    await controller.open('line_hay.01');
    expect(starts, 2);
    expect(controller.phase, TripPhase.ended);
    expect(controller.model.exit, const ExitToHome());
    expect(await rowCount(economy, 'trip_record'), 0);
  });

  test('another unfinished trip redirects there', () async {
    final economy = await testEconomy();
    await economy.service.startTrip(
      economy.service.newRequestId(),
      tripId: 'line_hay.02',
    );
    final controller = testController(economy);
    await controller.open('line_hay.01');
    expect(controller.phase, TripPhase.ended);
    expect(controller.model.exit, const ExitToTrip('line_hay.02'));
  });

  test(
    'a start that fails to write keeps the record and retries with its id',
    () async {
      final interceptor = FailingInterceptor();
      final economy = await testEconomy(
        executor: (inner) => inner.interceptWith(interceptor),
      );
      final controller = testController(
        economy,
        onKillPoint: (point) {
          if (point == TripKillPoint.recordCreated) {
            interceptor.failInserts = true;
          }
        },
      );
      await controller.open('line_hay.01');
      interceptor.failInserts = false;
      expect(controller.phase, TripPhase.opening);
      expect(controller.model.retry, TripRetry.start);
      expect(await rowCount(economy, 'trip_record'), 1);
      final recordId =
          (await economy.db
                  .customSelect('SELECT start_txn FROM trip_record')
                  .getSingle())
              .read<String>('start_txn');

      await controller.retry();
      expect(controller.phase, TripPhase.running);
      expect(economy.service.view.unfinished!.startTxn.value, recordId);
    },
  );

  test(
    'intents apply commands only while running; each appends a row',
    () async {
      final economy = await testEconomy();
      final controller = testController(economy);
      await controller.open('line_hay.01');
      controller
        ..pick(100)
        ..pick(50)
        ..returnHand()
        ..pick(500);
      await settle();
      final start = controller.session!.startTxn;
      final stored = (await DriftTripRecords(economy.db).load(start))!;
      expect(stored.commandJsons, hasLength(4));
      expect(controller.view!.hand.pieces, {500: 1});

      controller.pause(PauseReason.button);
      controller.pick(100);
      await settle();
      expect(controller.view!.hand.pieces, {500: 1});
      expect(
        (await DriftTripRecords(economy.db).load(start))!.commandJsons,
        hasLength(4),
      );
    },
  );

  test('a rejected command changes nothing and gives feedback', () async {
    final economy = await testEconomy();
    final controller = testController(economy);
    await controller.open('line_hay.01');
    final cues = <TripCue>[];
    controller.cues.listen(cues.add);
    controller.returnHand();
    expect(cues.whereType<FeedbackCue>().single.code, RejectionCode.handEmpty);
    expect(controller.view!.rejection, isNull);
  });

  test(
    'plays to the end: result recorded, record deleted, result route',
    () async {
      final fixture = loadFixture('sample__line_hay_01_three_stars');
      final economy = await testEconomy();
      final controller = testController(economy);
      final cues = <TripCue>[];
      controller.cues.listen(cues.add);
      await controller.open('line_hay.01');
      expect(
        controller.engine!.definition.toJson(),
        fixture.definition.toJson(),
      );
      await playCommands(controller, fixture.commandLog);
      runOut(controller);
      await settle();

      expect(controller.phase, TripPhase.ended);
      final exit = controller.model.exit! as ExitToResult;
      expect(exit.tripId, 'line_hay.01');
      expect(exit.result.toJson(), fixture.expectedResult.toJson());
      expect(economy.service.view.unfinished, isNull);
      expect(economy.service.view.lastResult, isNotNull);
      expect(await rowCount(economy, 'trip_record'), 0);
      expect(await rowCount(economy, 'trip_record_command'), 0);
      expect(cues.whereType<SoundCue>(), isNotEmpty);
    },
  );

  test(
    'a result that fails to write stays ending, then records once',
    () async {
      final fixture = loadFixture('sample__line_hay_01_three_stars');
      final interceptor = FailingInterceptor();
      final economy = await testEconomy(
        executor: (inner) => inner.interceptWith(interceptor),
      );
      final controller = testController(economy);
      await controller.open('line_hay.01');
      await playCommands(controller, fixture.commandLog);
      await settle();
      interceptor.failInserts = true;
      runOut(controller);
      await settle();
      expect(controller.phase, TripPhase.ending);
      expect(controller.model.retry, TripRetry.result);
      interceptor.failInserts = false;
      // The record was kept.
      expect(await rowCount(economy, 'trip_record'), 1);

      await controller.retry();
      await settle();
      expect(controller.phase, TripPhase.ended);
      expect(
        await economy.db
            .customSelect(
              "SELECT COUNT(*) AS n FROM ledger_ops WHERE op_type = 'trip_result'",
            )
            .getSingle()
            .then((r) => r.read<int>('n')),
        1,
      );
      expect(await rowCount(economy, 'trip_record'), 0);
    },
  );

  test('result_exists on a retry counts as recorded', () async {
    final fixture = loadFixture('sample__line_hay_01_three_stars');
    final economy = await testEconomy();
    final controller = testController(
      economy,
      onKillPoint: (point) {
        // The economy recorded it; the process dies before the delete.
        if (point == TripKillPoint.resultRecorded) throw const _Kill();
      },
    );
    await controller.open('line_hay.01');
    await playCommands(controller, fixture.commandLog);
    await runZonedGuarded(() async {
      runOut(controller);
      await settle();
    }, (error, _) => expect(error, isA<_Kill>()));
    expect(economy.service.view.unfinished, isNull);

    // Relaunch: no unfinished trip; the stale record goes at launch.
    final records = DriftTripRecords(economy.db);
    await records.deleteAllExcept(economy.service.view.unfinished?.startTxn);
    expect(await rowCount(economy, 'trip_record'), 0);
  });
}

final class _Kill implements Exception {
  const _Kill();
}
