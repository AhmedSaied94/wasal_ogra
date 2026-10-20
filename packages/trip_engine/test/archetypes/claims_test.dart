// Claims (rules.md §3 step 4, §4.5 cases 4, 5 and 7, §4.6, §6.3, §7.4,
// §9.3.1): the false claimer, and the truthful claim of a passenger who has
// paid.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

TripEngine _claimer({int? paysAt = 1}) => startTrip(
  (TripBuilder()
        ..station('gamaa', 30)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'gamaa',
          payment: [1000],
          paysAt: paysAt,
          archetype: Archetype.falseClaimer,
        ))
      .build(),
);

// p1 pays exactly at 1 s, so a tap after that opens a truthful claim.
TripEngine _paid() => startTrip(
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
);

void main() {
  group('a false claimer', () {
    test('claims at their payment time instead of paying', () {
      final engine = _claimer();
      final events = engine.stepTo(1023);
      expect(eventsOf<ClaimRaised>(events).single.passengerId, 'p1');
      expect(spoken(events, 'p1'), [SpeechSlot.claimsPaid]);
      expect(eventsOf<FareSent>(events), isEmpty);
      expect(engine.state.claims['p1']?.truthful, isFalse);
    });

    test('claims when tapped', () {
      final engine = _claimer(paysAt: null);
      final events = engine.ok(const Tap('p1'));
      expect(eventsOf<ClaimRaised>(events), hasLength(1));
      expect(eventsOf<FareSent>(events), isEmpty);
    });

    test('a tap while the claim is open has no effect', () {
      final engine = _claimer()..stepTo(1023);
      engine.rejects(const Tap('p1'), RejectionCode.noEffect);
    });

    test('insisting catches the liar: reputation, a count, and they pay', () {
      final engine = _claimer()..stepTo(1023);
      setReputation(engine, 80);
      final events = engine.ok(const ResolveClaim('p1', insist: true));
      expect(eventsOf<LiarCaught>(events).single.passengerId, 'p1');
      final gain = eventsOf<ReputationChanged>(events).single;
      expect(
        (gain.cause, gain.delta, gain.value),
        (RepCause.liarCaught, engine.params.repLiarCaught, 90),
      );
      expect(spoken(events, 'p1'), [SpeechSlot.caught, SpeechSlot.pays]);
      expect(eventsOf<FareSent>(events).single.amountPiasters, 1000);
      expect(engine.state.counters.caughtLiars, 1);
      expect(engine.state.claims, isEmpty);
      expect(engine.passenger('p1').claimResolved, isTrue);
    });

    test('believing them makes them never pay, and they leave unpaid', () {
      final engine = _claimer()..stepTo(1023);
      final accept = engine.ok(const ResolveClaim('p1', insist: false));
      expect(eventsOf<ClaimAccepted>(accept).single.passengerId, 'p1');
      expect(engine.passenger('p1').neverPays, isTrue);
      final tap = engine.ok(const Tap('p1'));
      expect(tap.map((e) => e.name), ['PassengerSpeaks']);
      expect(spoken(tap, 'p1'), [SpeechSlot.claimsPaid]);
      engine.stepToSeconds(40);
      expect(engine.passenger('p1').outcome, AlightOutcome.leftUnpaid);
      expect(engine.result!.lostFares, 1);
    });

    test('an open claim at their stop counts as accepted', () {
      final engine = _claimer();
      final events = engine.stepToSeconds(40);
      final reached = eventsOf<StationReached>(events).single.tMs;
      expect(eventsOf<ClaimAccepted>(events).single.tMs, reached);
      expect(
        spoken(events, 'p1').where((s) => s == SpeechSlot.claimsPaid),
        hasLength(1),
      );
      expect(engine.passenger('p1').outcome, AlightOutcome.leftUnpaid);
      expect(engine.state.claims, isEmpty);
    });
  });

  group('a truthful claim', () {
    test('a tap on a passenger who has paid opens one', () {
      final engine = _paid()..stepToSeconds(5);
      final events = engine.ok(const Tap('p1'));
      expect(eventsOf<ClaimRaised>(events), hasLength(1));
      expect(engine.state.claims['p1']?.truthful, isTrue);
    });

    test('insisting is a false accusation: reputation and a fight', () {
      final engine = _paid()..stepToSeconds(5);
      engine.ok(const Tap('p1'));
      final events = engine.ok(const ResolveClaim('p1', insist: true));
      expect(eventsOf<FalseAccusation>(events).single.passengerId, 'p1');
      final drop = eventsOf<ReputationChanged>(events).single;
      expect(
        (drop.cause, drop.delta),
        (RepCause.falseAccusation, -engine.params.repFalseAccusation),
      );
      expect(spoken(events, 'p1'), [SpeechSlot.accused]);
      expect(engine.state.counters.fights, 1);
      engine.stepToSeconds(40);
      expect(engine.result!.stars, 1);
    });

    test('a false accusation fails a no-fights trip', () {
      final engine = startTrip(
        (TripBuilder()
              ..station('gamaa', 30)
              ..passenger(
                'p1',
                seat: 'A_r',
                dest: 'gamaa',
                payment: [500, 100, 100],
                paysAt: 1,
              )
              ..rules(noFightsRequired: true))
            .build(),
      )..stepToSeconds(5);
      engine.ok(const Tap('p1'));
      engine.ok(const ResolveClaim('p1', insist: true));
      expect(engine.status, TripStatus.failed);
      expect(engine.state.revivable, isFalse);
    });

    test('one resolved claim per passenger: later taps only speak', () {
      final engine = _paid()..stepToSeconds(5);
      engine
        ..ok(const Tap('p1'))
        ..ok(const ResolveClaim('p1', insist: false));
      final tap = engine.ok(const Tap('p1'));
      expect(tap.map((e) => e.name), ['PassengerSpeaks']);
      expect(spoken(tap, 'p1'), [SpeechSlot.claimsPaid]);
      expect(engine.state.claims, isEmpty);
    });
  });

  test('ResolveClaim with no open claim is no_choice', () {
    final engine = _paid()..stepToSeconds(5);
    engine.rejects(
      const ResolveClaim('p1', insist: true),
      RejectionCode.noChoice,
    );
  });
}
