import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';

import '../../helpers/trip.dart';

// `event__payment_dispute` answers its dispute a second after it opens,
// which the screen can't: the clock stops until the answer (FR-032,
// research R11). Played the screen's way, answered when it opens, its
// result is the engine's own replay of what the controller logged
// (tasks.md T071).

void main() {
  testWidgets('a dispute answered when it opens ends as the engine replays '
      'its log', (tester) async {
    final fixture = loadFixture('event__payment_dispute');
    final economy = await economyFor(fixture);
    final trip = FixedTrip(
      definition: fixture.definition,
      params: fixture.params,
      seed: fixture.seed,
    );
    await pumpTrip(
      tester,
      tripId: trip.definition.tripId,
      economy: economy,
      fixed: trip,
    );
    final c = controllerOf(tester);

    final run = await ScriptedPlayer(tester, fixture).drive();
    expect(run.inexact, isFalse);
    final result = run.result;
    expect(result, isNotNull, reason: '${run.exit}');

    final log = c.engine!.commandLog;
    final answer = log.singleWhere((e) => e.command is ResolveDispute);
    // At the step it opened on: the first at or after its time.
    final at = fixture.definition.events.single.atSeconds * 1000;
    expect(answer.tMs, inInclusiveRange(at, at + engineStepMs - 1));
    expect((answer.command as ResolveDispute).paidPassengerId, 'p1');

    final replayed = replay(trip.definition, trip.params, trip.seed, log);
    expect(result!.toJson(), replayed.toJson());
    // Not the fixture's: it answered a second later.
    expect(result.toJson(), isNot(fixture.expectedResult.toJson()));
  });
}
