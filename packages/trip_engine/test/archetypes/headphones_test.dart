// Headphones (rules.md §2.4, §3 step 2.3, §4.5 case 3): muted until called
// twice, then attentive for trip_headphones_attentive_ms (15 s).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripEngine _headphones({int? paysAt = 1, List<int> payment = const [1000]}) =>
    startTrip(
      (TripBuilder()
            ..station('gamaa', 60)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'gamaa',
              payment: payment,
              paysAt: paysAt,
              archetype: Archetype.headphones,
            ))
          .build(),
    );

void main() {
  test('they start muted; the second tap makes them attentive for 15 s', () {
    final engine = _headphones();
    expect(engine.passenger('p1').alertness, Alertness.muted);
    final first = engine.ok(const Tap('p1'));
    expect(eventsOf<PassengerCalled>(first).single.taps, 1);
    expect(engine.passenger('p1').taps, 1);
    final second = engine.ok(const Tap('p1'));
    expect(eventsOf<PassengerAttentive>(second).single.passengerId, 'p1');
    expect(spoken(second, 'p1'), [SpeechSlot.attentive]);
    final p1 = engine.passenger('p1');
    expect(
      (p1.alertness, p1.alertUntilMs, p1.taps),
      (Alertness.attentive, 15000, 0),
    );
  });

  test('then they are muted again, with taps reset', () {
    final engine = _headphones()
      ..ok(const Tap('p1'))
      ..ok(const Tap('p1'))
      ..ok(const Tap('p1'));
    expect(eventsOf<PassengerMuted>(engine.stepTo(14982)), isEmpty);
    final muted = engine.step();
    expect(eventsOf<PassengerMuted>(muted).single.tMs, 15015);
    final p1 = engine.passenger('p1');
    expect(
      (p1.alertness, p1.taps, p1.alertUntilMs),
      (Alertness.muted, 0, null),
    );
  });

  test('while muted, a tap never asks for the fare', () {
    final engine = _headphones(paysAt: null);
    final taps = [...engine.ok(const Tap('p1')), ...engine.ok(const Tap('p1'))];
    expect(eventsOf<FareSent>(taps), isEmpty);
    final third = engine.ok(const Tap('p1'));
    expect(eventsOf<FareSent>(third).single.passengerId, 'p1');
  });

  test('their scheduled payment waits until they are attentive', () {
    final engine = _headphones();
    expect(eventsOf<FareSent>(engine.stepToSeconds(5)), isEmpty);
    engine
      ..ok(const Tap('p1'))
      ..ok(const Tap('p1'));
    expect(eventsOf<FareSent>(engine.step()).single.tMs, 5049);
  });

  test('muted as a middle holder, they block the chain', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 60)
            ..passenger(
              'p1',
              seat: 'C_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
              paysAt: 1,
            )
            ..passenger(
              'p2',
              seat: 'B_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
              archetype: Archetype.headphones,
            ))
          .build(),
    );
    final events = engine.stepToSeconds(4);
    expect(eventsOf<TokenBlocked>(events).single.by, 'p2');
    engine
      ..ok(const Tap('p2'))
      ..ok(const Tap('p2'));
    expect(eventsOf<TokenUnblocked>(engine.step()), hasLength(1));
  });

  test('muted again as the target, they block their change', () {
    // Attentive from 0 to 15 s: they pay 1000 at 1023 and go muted at 15015.
    final engine = _headphones()
      ..ok(const Tap('p1'))
      ..ok(const Tap('p1'))
      ..stepToSeconds(16);
    for (final piece in [100, 100, 100]) {
      engine.ok(PickFromTray(piece));
    }
    engine.ok(const SendHand('p1'));
    final events = engine.stepToSeconds(20);
    expect(eventsOf<TokenBlocked>(events).single.by, 'p1');
    expect(eventsOf<ChangeDelivered>(events), isEmpty);
  });
}
