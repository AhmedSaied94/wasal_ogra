// The sleeper (rules.md §2.4, §3 step 2, §4.5, §9.3, clarification 5).
// line_gamaa: hop 1100 ms, trip_wake_ms 1000, trip_sleeper_awake_ms 15000.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripEngine _sleeper({List<int> payment = const [500, 100, 100]}) => startTrip(
  (TripBuilder()
        ..station('gamaa', 40)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'gamaa',
          payment: payment,
          paysAt: 1,
          archetype: Archetype.sleeper,
        ))
      .build(),
);

void main() {
  test('he starts asleep, and a tap wakes him after trip_wake_ms', () {
    final engine = _sleeper();
    expect(engine.passenger('p1').alertness, Alertness.asleep);
    engine.stepToSeconds(2);
    expect(engine.state.tMs, 2013);
    final tap = engine.ok(const Tap('p1'));
    expect(eventsOf<PassengerWaking>(tap).single.passengerId, 'p1');
    expect(engine.passenger('p1').alertness, Alertness.waking);
    expect(engine.passenger('p1').alertUntilMs, 3013);
    engine.rejects(const Tap('p1'), RejectionCode.noEffect);

    expect(eventsOf<PassengerWoke>(engine.stepTo(3003)), isEmpty);
    final woke = engine.step();
    expect(eventsOf<PassengerWoke>(woke).single.tMs, 3036);
    expect(spoken(woke, 'p1').first, SpeechSlot.woke);
    expect(engine.passenger('p1').alertness, Alertness.awake);
    expect(engine.passenger('p1').alertUntilMs, 3036 + 15000);
  });

  test('he pays at the first step he is able, after his pays_at_seconds', () {
    final engine = _sleeper();
    expect(eventsOf<FareSent>(engine.stepToSeconds(2)), isEmpty);
    engine.ok(const Tap('p1'));
    final woke = engine.stepTo(3036);
    expect(eventsOf<FareSent>(woke).single.tMs, 3036);
  });

  test('he falls asleep again 15 s after waking, even when settled', () {
    final engine = _sleeper()..stepToSeconds(2);
    engine.ok(const Tap('p1'));
    engine.stepTo(18018);
    expect(engine.passenger('p1').isOwed, isFalse);
    expect(engine.passenger('p1').alertness, Alertness.awake);
    final asleep = engine.step();
    expect(eventsOf<PassengerFellAsleep>(asleep).single.tMs, 18051);
    expect(engine.passenger('p1').alertness, Alertness.asleep);
    expect(engine.passenger('p1').alertUntilMs, isNull);
  });

  test('asleep as a middle holder, he blocks the chain until woken', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 40)
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
              archetype: Archetype.sleeper,
            ))
          .build(),
    );
    final blocked = engine.stepToSeconds(2);
    expect(eventsOf<TokenBlocked>(blocked).single.by, 'p2');
    expect(eventsOf<TokenHopStarted>(blocked), isEmpty);
    engine.ok(const Tap('p2'));
    final unblocked = engine.stepTo(3036);
    expect(eventsOf<TokenUnblocked>(unblocked).single.tMs, 3036);
    expect(eventsOf<TokenHopStarted>(unblocked).map((e) => e.to.wire), ['p2']);
  });

  group('asleep as the target, then at his stop', () {
    late TripEngine engine;
    late List<DomainEvent> events;

    setUp(() {
      // Woken at 0, he pays 1000 at 1023 and falls asleep at 16038. The
      // change sent at 17 s waits for him and he sleeps through gamaa.
      engine = _sleeper(payment: [1000])..ok(const Tap('p1'));
      engine.stepToSeconds(17);
      for (final piece in [100, 100, 100]) {
        engine.ok(PickFromTray(piece));
      }
      engine.ok(const SendHand('p1'));
      events = engine.stepToSeconds(60);
    });

    test('the change is blocked by him', () {
      expect(eventsOf<TokenBlocked>(events).single.by, 'p1');
      expect(eventsOf<ChangeDelivered>(events), isEmpty);
    });

    test(
      'he misses his stop: reputation, a count and an unreturned mistake',
      () {
        final missed = eventsOf<ReputationChanged>(events)
            .where((e) => e.cause == RepCause.missedStop)
            .single;
        expect(missed.delta, -engine.params.repMissedStop);
        final result = engine.result!;
        expect(result.missedStops, 1);
        expect(result.mistakes.single.toJson(), {
          'passenger_id': 'p1',
          'kind': 'unreturned',
          'amount_piasters': 300,
        });
        expect(engine.passenger('p1').outcome, AlightOutcome.missedStop);
      },
    );

    test('a missed stop is not a fight', () {
      expect(engine.result!.fights, 0);
      expect(spoken(events, 'p1'), isNot(contains(SpeechSlot.fight)));
      final speech = eventsOf<PassengerSpeaks>(events)
          .lastWhere((e) => e.slot == SpeechSlot.missedStop);
      expect(speech.stationId, 'gamaa');
    });
  });

  test('unpaid and asleep at his stop, he is a lost fare as well', () {
    final engine = _sleeper()..stepToSeconds(60);
    final result = engine.result!;
    expect(result.missedStops, 1);
    expect(result.lostFares, 1);
    expect(result.mistakes, isEmpty);
    expect(result.reputation, 100 - engine.params.repMissedStop);
  });
}
