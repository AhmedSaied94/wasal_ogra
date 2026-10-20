// Paying on schedule or when tapped (rules.md §3 step 4, §4.5 cases 4 and 6,
// clarification 4).
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripEngine _trip({int? paysAt, List<int> payment = const [1000]}) => startTrip(
  (TripBuilder()
        ..station('kobri', 30, fare: 850)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'kobri',
          payment: payment,
          paysAt: paysAt,
        ))
      .build(),
);

void main() {
  test('a passenger pays at pays_at_seconds', () {
    final engine = _trip(paysAt: 5);
    expect(eventsOf<FareSent>(engine.stepTo(4983)), isEmpty);
    final sent = eventsOf<FareSent>(engine.step()).single;
    expect(sent.tMs, 5016);
  });

  test('a tap before that time pays at once, and only once', () {
    final engine = _trip(paysAt: 5)..stepTo(990);
    final events = engine.ok(const Tap('p1'));
    expect(eventsOf<FareSent>(events).single.tMs, 990);
    expect(eventsOf<FareSent>(engine.stepToSeconds(20)), isEmpty);
    expect(engine.passenger('p1').fareSent, isTrue);
  });

  test('a passenger with no payment time pays only when tapped', () {
    final engine = _trip();
    expect(eventsOf<FareSent>(engine.stepToSeconds(20)), isEmpty);
    expect(engine.passenger('p1').fareSent, isFalse);
    expect(eventsOf<FareSent>(engine.ok(const Tap('p1'))), hasLength(1));
  });

  test('a tap on a passenger who owes makes them pay the rest', () {
    final engine = _trip(paysAt: 0, payment: [500])..step();
    expect(engine.passenger('p1').balance, -350);
    final events = engine.ok(const Tap('p1'));
    expect(eventsOf<FareSent>(events).single.amountPiasters, 350);
    expect(engine.passenger('p1').balance, 0);
    engine.stepToSeconds(5);
    expect(engine.passenger('p1').paidIn, 850);
  });

  test('a tap on a passenger who is not aboard is rejected', () {
    final engine = _trip();
    engine.rejects(const Tap('p9'), RejectionCode.notAboard);
  });
}
