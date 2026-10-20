// Patience (rules.md §3 step 6, §7.3, clarification 2): it starts when a
// passenger is first owed and drains 33 per step while they are owed and
// aboard. p1 pays 1000 at 1023 for 700 on line_gamaa.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/default_params.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

TripEngine _owed({Archetype archetype = Archetype.regular}) => startTrip(
  (TripBuilder()
        ..station('gamaa', 60)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'gamaa',
          payment: [1000],
          paysAt: 1,
          archetype: archetype,
        ))
      .build(),
);

void _give(TripEngine engine, List<int> pieces) {
  for (final piece in pieces) {
    engine.ok(PickFromTray(piece));
  }
  engine.ok(const SendHand('p1'));
}

void main() {
  test('it starts when he is first owed, and drains in that step', () {
    final engine = _owed()..stepTo(990);
    expect(engine.passenger('p1').patienceMs, isNull);
    engine.step();
    expect(engine.passenger('p1').patienceStartMs, 20000);
    expect(engine.passenger('p1').patienceMs, 20000 - 33);
    expect(engine.passenger('p1').patiencePermille, 998);
  });

  test("a hurried passenger's patience is half (10 s)", () {
    final engine = _owed(archetype: Archetype.hurry)..stepTo(1023);
    expect(engine.passenger('p1').patienceStartMs, 10000);
  });

  test('a passenger who paid exactly never starts patience', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 30)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
              paysAt: 1,
            ))
          .build(),
    )..stepToSeconds(20);
    expect(engine.passenger('p1').patienceMs, isNull);
  });

  test('wants_change is said once, at half', () {
    final engine = _owed();
    final events = engine.stepTo(30000);
    final wants = eventsOf<PassengerSpeaks>(events)
        .where((e) => e.slot == SpeechSlot.wantsChange);
    // The 304th drain takes 20000 to 9968, at 1023 + 303 × 33.
    expect(wants.map((e) => (e.tMs, e.amountPiasters)), [(11022, 300)]);
  });

  test('at zero: reputation once, a count, the event and the speech', () {
    final engine = _owed();
    final events = engine.stepTo(21021);
    final ranOut = eventsOf<PatienceRanOut>(events).single;
    expect(ranOut.tMs, 21021);
    final drop = eventsOf<ReputationChanged>(events).single;
    expect(
      (drop.cause, drop.delta),
      (RepCause.impatient, -engine.params.repImpatient),
    );
    expect(spoken(events, 'p1').last, SpeechSlot.impatient);
    final p1 = engine.passenger('p1');
    expect((p1.patienceMs, p1.impatient), (0, true));
    expect(engine.state.counters.impatient, 1);
  });

  test('it never refills or repeats', () {
    final engine = _owed()..stepTo(21021);
    _give(engine, [100, 100]);
    final later = engine.stepToSeconds(70);
    expect(eventsOf<ChangeDelivered>(later).single.result, ChangeResult.short);
    expect(eventsOf<PatienceRanOut>(later), isEmpty);
    expect(engine.passenger('p1').patienceMs, 0);
    expect(engine.result!.impatient, 1);
  });

  test('it stops draining once he is settled', () {
    final engine = _owed()..stepTo(2145);
    _give(engine, [100, 100, 100]);
    engine.stepToSeconds(5);
    final settled = engine.passenger('p1').patienceMs;
    engine.stepToSeconds(30);
    expect(engine.passenger('p1').balance, 0);
    expect(engine.passenger('p1').patienceMs, settled);
  });

  test('while traffic is active it drains scale(33, 150) = 49 per step', () {
    final engine = _owed()..stepTo(1023);
    setTrafficActive(engine, true);
    engine.step();
    expect(engine.passenger('p1').patienceMs, 20000 - 33 - 49);
  });

  test('one drain can reach half and zero: wants_change, then impatient', () {
    // Patience of one step: the drain in the step he pays empties it.
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 60)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'gamaa',
              payment: [1000],
              paysAt: 1,
            ))
          .build(),
      params: paramsWith({
        'trip_patience_ms': 33,
        'trip_patience_pct_hurry': 100,
      }),
    );
    final events = engine.stepTo(1023);
    expect(spoken(events, 'p1'), [
      SpeechSlot.pays,
      SpeechSlot.wantsChange,
      SpeechSlot.impatient,
    ]);
    expect(eventsOf<PatienceRanOut>(events).single.tMs, 1023);
    expect(engine.passenger('p1').patienceMs, 0);
  });
}
