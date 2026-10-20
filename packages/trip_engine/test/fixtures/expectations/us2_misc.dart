// What the US2 `archetype__`, `ending__`, `command__` and `sample__` fixtures
// pin (rules.md §4, §6, §11).
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../../support/fixture_io.dart';
import '../../support/scripts.dart';

final us2Expectations = <String, Expectation>{
  'archetype__regular.json': (run) {
    // §4.5: a regular with no pays_at pays when tapped.
    final tap = run.engine.commandLog.first;
    expect(tap.toJson(), [tap.tMs, 'Tap', 'p1']);
    expect(eventsOf<FareSent>(run.events).single.tMs, tap.tMs);
    expect(
      eventsOf<ChangeDelivered>(run.events).single.result,
      ChangeResult.exact,
    );
    expect(resultOf(run).stars, 3);
  },
  'archetype__honest_returns_excess.json': (run) {
    // §6.5: an honest passenger sends the excess back; it is still a mistake,
    // but nothing is overpaid.
    expect(eventsOf<ExcessReturned>(run.events).single.amountPiasters, 200);
    expect(spoken(run.events, 'p1'), contains(SpeechSlot.returnsExcess));
    final result = resultOf(run);
    expect(result.overpaidPiasters, 0);
    expect(result.mistakes.single.kind, MistakeKind.over);
    expect(result.earningsJenehat, 7);
    expect(result.stars, 2);
  },
  'ending__three_stars.json': (run) {
    final result = resultOf(run);
    expect(result.stars, 3);
    expect(result.starFlags.toJson(), {
      'reached': true,
      'no_fights': true,
      'no_mistakes': true,
    });
    expect(result.earningsJenehat, 19);
  },
  'ending__two_stars.json': (run) {
    // A mistake (50 over) with no fight is 2 stars.
    final result = resultOf(run);
    expect(result.stars, 2);
    expect(
      (result.starFlags.noFights, result.starFlags.noMistakes),
      (true, false),
    );
    expect(result.earningsJenehat, 18);
  },
  'ending__one_star.json': (run) {
    // A fight (p2 at kobri) is 1 star, whatever else went right.
    final result = resultOf(run);
    expect(result.stars, 1);
    expect(result.starFlags.noFights, isFalse);
    expect(result.fights, 1);
    expect(result.earningsJenehat, 19);
  },
  'command__pick_return_send.json': (run) {
    // §4.1 to §4.3: picks, a return and a send are logged; the rejected
    // commands met while authoring are not, and inserting them changes
    // nothing.
    final log = run.engine.commandLog;
    expect(log.map((e) => e.command.name), [
      'PickFromTray',
      'ReturnHand',
      'PickFromTray',
      'PickFromTray',
      'PickFromTray',
      'SendHand',
    ]);
    final engine = TripEngine.start(
      run.engine.definition,
      run.engine.params,
      seed: run.engine.seed,
    );
    engine
      ..rejects(const SendHand('p1'), RejectionCode.handEmpty)
      ..rejects(const PickFromTray(1000), RejectionCode.trayEmpty);
    for (final (i, entry) in log.indexed) {
      engine
        ..stepTo(entry.tMs)
        ..ok(entry.command);
      if (i == 0) engine.rejects(const SendHand('p9'), RejectionCode.notAboard);
    }
    engine.stepTo(1 << 30);
    expect(engine.result?.toJson(), resultOf(run).toJson());
  },
  'sample__line_hay_01_three_stars.json': (run) {
    // Sample line_hay.01 played to 3 stars: p2 is a student paying 350.
    expect(run.engine.definition.tripId, 'line_hay.01');
    expect(run.engine.passenger('p2').farePiasters, 350);
    expect(eventsOf<ChangeDelivered>(run.events).map((e) => e.result), [
      ChangeResult.exact,
      ChangeResult.exact,
    ]);
    expect(resultOf(run).stars, 3);
    expect(resultOf(run).earningsJenehat, 10);
  },
};
