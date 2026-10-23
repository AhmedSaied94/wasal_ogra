import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';
import 'package:wassal/features/trip/domain/talk_log.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../../helpers/trip.dart';

void main() {
  test('keeps the last two lines, newest last', () {
    var log = TalkLog.empty;
    for (final kind in [LogKind.dropped, LogKind.lost, LogKind.fareUp]) {
      log = log.push(LogLine(kind: kind, amountPiasters: 50));
    }
    expect(log.lines.map((l) => l.kind), [LogKind.lost, LogKind.fareUp]);
  });

  test('labels come from the look; a group payer is the group', () {
    final definition = sampleTrip('line_hay.02');
    final facts = factsFor(definition);
    final engine = TripEngine.start(definition, facts.params);
    engine.stepTo(33);
    final payer = definition.passengers.firstWhere(
      (p) => p.archetype.name == 'groupPayer',
    );
    expect(
      speakerOf(payer.passengerId, engine.state, facts).labelKey,
      groupLabelKey,
    );
    final hajja = definition.passengers.firstWhere(
      (p) => p.skin == 'hajja_black',
    );
    expect(
      speakerOf(hajja.passengerId, engine.state, facts).labelKey,
      skinLooks['hajja_black']!.labelKey,
    );
  });

  test('two aboard with the same label get their station letter', () {
    // line_hay.02 seats two worker_blue regulars.
    final definition = sampleTrip('line_hay.02');
    final facts = factsFor(definition);
    final engine = TripEngine.start(definition, facts.params);
    engine.stepTo(33);
    final workers = [
      for (final p in definition.passengers)
        if (p.skin == 'worker_blue') p.passengerId,
    ];
    expect(workers, hasLength(2));
    final aboard = [
      for (final id in workers)
        if (engine.state.passenger(id)!.presence == Presence.aboard) id,
    ];
    if (aboard.length == 2) {
      for (final id in aboard) {
        final label = speakerOf(id, engine.state, facts);
        expect(label.labelKey, 'tripLookWorker');
        expect(label.slot, facts.slotOf(id));
      }
    }
    final alone = sampleTrip('line_hay.01');
    final aloneFacts = factsFor(alone);
    final aloneEngine = TripEngine.start(alone, aloneFacts.params)..stepTo(33);
    expect(speakerOf('p1', aloneEngine.state, aloneFacts).slot, isNull);
  });
}
