// What a finished trip hands its result (specs/013-m08-home-result,
// contracts/result.md "The hand-over from the trip", research R14): the
// result, the start, the replay record, and the best stars and JENEHAT read
// just before the result is recorded, built the same way by a rebuild.
import 'package:drift/drift.dart' show ApplyInterceptor;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

const _fixture = 'sample__line_hay_01_three_stars';
const _jenehat = 500;
const _bestStars = 2;

/// A player with [_jenehat] and two stars on the fixture's trip.
Future<TestEconomy> _economy({FailingInterceptor? interceptor}) => testEconomy(
  executor: interceptor == null
      ? null
      : (inner) => inner.interceptWith(interceptor),
  firstState: (nowMs) =>
      EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
        jenehat: _jenehat,
        progress: {
          'line_hay.01': const TripProgress(
            bestStars: _bestStars,
            plays: 1,
            firstCompletedAtMs: 1,
          ),
        },
      ),
);

void main() {
  final fixture = loadFixture(_fixture);

  test('a finished trip exits with its ResultArgs', () async {
    final economy = await _economy();
    final controller = testController(economy);
    await controller.open('line_hay.01');
    final start = controller.session!.startTxn;
    await playCommands(controller, fixture.commandLog);
    runOut(controller);
    await settle();

    final exit = controller.model.exit! as ExitToResult;
    expect(exit.tripId, 'line_hay.01');
    final args = exit.args;
    expect(args.result.toJson(), fixture.expectedResult.toJson());
    expect(args.startTxn, start);
    expect(args.replay.definition.toJson(), fixture.definition.toJson());
    expect(
      [for (final e in args.replay.commandLog) e.toJson()],
      [for (final e in fixture.commandLog) e.toJson()],
    );
    expect(args.bestStarsBefore, _bestStars);
    expect(args.jenehatBefore, _jenehat);
    // The economy has the result now.
    expect(
      economy.service.view.jenehat,
      _jenehat + fixture.expectedResult.earningsJenehat,
    );
    expect(economy.service.view.progress['line_hay.01']!.bestStars, 3);
  });

  test('a result that failed to write once still hands the balance before '
      'it', () async {
    final interceptor = FailingInterceptor();
    final economy = await _economy(interceptor: interceptor);
    final controller = testController(economy);
    await controller.open('line_hay.01');
    await playCommands(controller, fixture.commandLog);
    await settle();
    interceptor.failInserts = true;
    runOut(controller);
    await settle();
    interceptor.failInserts = false;
    expect(controller.model.retry, TripRetry.result);

    await controller.retry();
    await settle();
    final args = (controller.model.exit! as ExitToResult).args;
    expect(args.bestStarsBefore, _bestStars);
    expect(args.jenehatBefore, _jenehat);
  });

  test('a rebuild that finds the trip finished builds the same args', () async {
    final interceptor = FailingInterceptor();
    final economy = await _economy(interceptor: interceptor);
    final first = testController(economy);
    await first.open('line_hay.01');
    final start = first.session!.startTxn;
    await playCommands(first, fixture.commandLog);
    await settle();
    // The result doesn't reach the economy before the kill.
    interceptor.failInserts = true;
    runOut(first);
    await settle();
    interceptor.failInserts = false;
    first.dispose();
    await settle();

    final second = testController(economy);
    await second.open('line_hay.01');
    await settle();
    final args = (second.model.exit! as ExitToResult).args;
    expect(args.result.toJson(), fixture.expectedResult.toJson());
    expect(args.startTxn, start);
    expect(
      [for (final e in args.replay.commandLog) e.toJson()],
      [for (final e in fixture.commandLog) e.toJson()],
    );
    expect(args.bestStarsBefore, _bestStars);
    expect(args.jenehatBefore, _jenehat);
  });
}
