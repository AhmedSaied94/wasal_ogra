// fare_increase (rules.md §6.1, §6.2, §8): fares not yet sent rise; listed
// passengers pay the old fare and owe the rest.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

// +100 at 2 s, with p2 listed. p3 has paid before it.
TripEngine _trip() => startTrip(
  (TripBuilder()
        ..station('gamaa', 40)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'gamaa',
          payment: [500, 100, 100],
          paysAt: 5,
        )
        ..passenger(
          'p2',
          seat: 'A_m',
          dest: 'gamaa',
          payment: [500, 100, 100],
          paysAt: 6,
        )
        ..passenger(
          'p3',
          seat: 'A_l',
          dest: 'gamaa',
          payment: [1000],
          paysAt: 1,
        )
        ..event(EventId.fareIncrease, 2, amount: 100, passengers: ['p2']))
      .build(),
);

void main() {
  test('FareIncreased carries the amount and the total so far', () {
    final events = _trip().stepToSeconds(3);
    final increase = eventsOf<FareIncreased>(events).single;
    expect(
      (increase.amountPiasters, increase.totalIncreasePiasters),
      (100, 100),
    );
  });

  test('an unlisted passenger whose payment is short tops it up', () {
    final engine = _trip();
    final events = engine.stepToSeconds(6);
    final fare = eventsOf<FareSent>(events)
        .singleWhere((e) => e.passengerId == 'p1');
    expect(fare.amountPiasters, 800);
    final p1 = engine.passenger('p1');
    expect((p1.farePiasters, p1.balance), (800, 0));
  });

  test('a listed passenger pays the old fare and owes the difference', () {
    final engine = _trip();
    final events = engine.stepToSeconds(7);
    expect(spoken(events, 'p2'), [SpeechSlot.paysOldFare]);
    expect(engine.passenger('p2').balance, -100);
    final tap = engine.ok(const Tap('p2'));
    expect(spoken(tap, 'p2'), [SpeechSlot.paysRest]);
    expect(eventsOf<FareSent>(tap).single.amountPiasters, 100);
    expect(engine.passenger('p2').balance, 0);
  });

  test('fares already sent do not change', () {
    final engine = _trip()..stepToSeconds(7);
    final p3 = engine.passenger('p3');
    expect((p3.farePiasters, p3.balance), (700, 300));
  });

  test('the unpaid remainder at the stop is missing from fares collected', () {
    final engine = _trip()..stepToSeconds(50);
    expect(engine.passenger('p2').outcome, AlightOutcome.thanked);
    expect(engine.result!.faresCollectedPiasters, 800 + 700 + 700);
  });
}
