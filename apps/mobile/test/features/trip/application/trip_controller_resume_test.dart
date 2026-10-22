import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/config/tunable_snapshot.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// Opening an unfinished trip (tasks.md T046, contracts/trip-controller.md
// "Opening" step 3, "Ending without a record").

FixedTrip fixedOf(ParityFixture fixture) => FixedTrip(
  definition: fixture.definition,
  params: fixture.params,
  seed: fixture.seed,
);

/// The state's JSON without its status: a rebuilt trip comes back paused.
Map<String, Object> withoutStatus(TripState state) =>
    state.toJson()..remove('status');

void main() {
  test('a running trip comes back paused, with no new start', () async {
    final fixture = loadFixture('sample__line_hay_01_three_stars');
    final economy = await testEconomy();
    final first = testController(economy);
    await first.open('line_hay.01');
    await playCommands(first, fixture.commandLog.take(3));
    advanceMs(first, 500);
    // Leaving the screen saves the clock of a running trip.
    first.dispose();
    await settle();
    final live = first.engine!.state;
    final start = economy.service.view.unfinished!.startTxn;
    final fuel = economy.service.view.fuel.liters;

    final second = testController(economy);
    await second.open('line_hay.01');
    expect(second.phase, TripPhase.paused);
    expect(second.model.pauseReason, PauseReason.lifecycle);
    expect(second.session!.startTxn, start);
    expect(second.engine!.status, TripStatus.paused);
    expect(withoutStatus(second.engine!.state), withoutStatus(live));
    expect(economy.service.view.fuel.liters, fuel);
    expect(await opCount(economy, 'trip_start'), 1);

    second.resume();
    expect(second.phase, TripPhase.running);
  });

  test('an open dispute is asked after «كمّل المشوار»', () async {
    final fixture = loadFixture('sample__line_hay_02_three_stars');
    final answer = fixture.commandLog
        .map((e) => e.command)
        .whereType<ResolveDispute>()
        .single;
    final economy = await testEconomy();
    final first = testController(economy, fixed: fixedOf(fixture));
    await first.open('line_hay.02');
    await playCommands(
      first,
      fixture.commandLog.takeWhile((e) => e.command is! ResolveDispute),
    );
    runOut(first);
    expect(first.phase, TripPhase.disputeOpen);
    final asked = first.engine!.state.tMs;
    first.dispose();
    await settle();

    final second = testController(economy);
    await second.open('line_hay.02');
    expect(second.phase, TripPhase.paused);
    expect(second.engine!.state.tMs, asked);
    expect(second.view!.choices.whereType<DisputeChoice>(), isEmpty);

    second.resume();
    expect(second.phase, TripPhase.disputeOpen);
    final dispute = second.view!.choices.whereType<DisputeChoice>().single;
    expect(dispute.disputeId, answer.disputeId);
    second.answerDispute(answer.paidPassengerId);
    expect(second.phase, TripPhase.running);
  });

  test('a finished trip records its result and goes to it', () async {
    final fixture = loadFixture('sample__line_hay_01_three_stars');
    final interceptor = FailingInterceptor();
    final economy = await testEconomy(
      executor: (inner) => inner.interceptWith(interceptor),
    );
    final first = testController(economy);
    await first.open('line_hay.01');
    await playCommands(first, fixture.commandLog);
    await settle();
    // The result doesn't reach the economy before the kill.
    interceptor.failInserts = true;
    runOut(first);
    await settle();
    interceptor.failInserts = false;
    expect(first.phase, TripPhase.ending);
    first.dispose();
    await settle();

    final second = testController(economy);
    await second.open('line_hay.01');
    await settle();
    expect(second.phase, TripPhase.ended);
    final exit = second.model.exit! as ExitToResult;
    expect(exit.result.toJson(), fixture.expectedResult.toJson());
    expect(await opCount(economy, 'trip_result'), 1);
    expect(await rowCount(economy, 'trip_record'), 0);
  });

  group('ending without a record', () {
    Future<void> expectAbandoned(TestEconomy economy) async {
      final c = testController(economy);
      await c.open('line_hay.01');
      await settle();
      expect(c.phase, TripPhase.ended);
      expect(c.model.exit, const ExitToHome());
      expect(economy.service.view.lastResult!.outcome, TripOutcome.abandoned);
      expect(economy.service.view.unfinished, isNull);
      expect(await rowCount(economy, 'trip_record'), 0);

      final again = testController(economy);
      await again.open('line_hay.01');
      expect(again.phase, TripPhase.running);
    }

    test('no record: abandoned, and trips start again', () async {
      final economy = await testEconomy();
      await economy.service.startTrip(
        economy.service.newRequestId(),
        tripId: 'line_hay.01',
      );
      await expectAbandoned(economy);
    });

    test('a command refused on replay: abandoned too', () async {
      final economy = await testEconomy();
      final first = testController(economy);
      await first.open('line_hay.01');
      first.dispose();
      await settle();
      // The drawer has no 200 at 0 ms.
      await DriftTripRecords(economy.db).appendCommand(
        economy.service.view.unfinished!.startTxn,
        const LoggedCommand(0, PickFromTray(20000)),
      );
      await expectAbandoned(economy);
    });
  });

  test('both abandoned results have the same JSON', () {
    final definition = sampleContent().trip('line_hay.01')!;
    TripParams params(TripDefinition d) =>
        TripParams.fromTunables(tunableSnapshot(bundledConfig()), d.lineId);
    expect(
      abandonedResult('line_hay.01', null, params).toJson(),
      abandonedResult('line_hay.01', definition, params).toJson(),
    );
  });
}
