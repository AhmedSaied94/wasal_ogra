// payment_dispute (rules.md §4.7, §8): two passengers each say they paid;
// the driver names the one who did.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

// p1 pays at 1 s unless [p1Pays] is false; p2 only when [p2Pays].
TripEngine _trip({bool p1Pays = true, bool p2Pays = false}) => startTrip(
  (TripBuilder()
        ..station('kobri', 10)
        ..station('gamaa', 40)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'gamaa',
          payment: [500, 100, 100],
          paysAt: p1Pays ? 1 : null,
        )
        ..passenger(
          'p2',
          seat: 'A_m',
          dest: 'gamaa',
          payment: [500, 100, 100],
          paysAt: p2Pays ? 2 : null,
        )
        ..passenger(
          'p3',
          seat: 'A_l',
          dest: 'kobri',
          payment: [500, 100, 100],
          paysAt: 3,
        )
        ..event(EventId.paymentDispute, 5, passengers: ['p1', 'p2']))
      .build(),
)..stepToSeconds(6);

void main() {
  test('it opens with both passengers speaking', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 40)
            ..passenger('p1', seat: 'A_r', dest: 'gamaa', payment: [1000])
            ..passenger('p2', seat: 'A_m', dest: 'gamaa', payment: [1000])
            ..event(EventId.paymentDispute, 5, passengers: ['p1', 'p2']))
          .build(),
    );
    final events = engine.stepToSeconds(6);
    final raised = eventsOf<DisputeRaised>(events).single;
    expect(raised.disputeId, 0);
    expect(raised.passengerIds, ['p1', 'p2']);
    expect(spoken(events, 'p1'), [SpeechSlot.dispute]);
    expect(spoken(events, 'p2'), [SpeechSlot.dispute]);
    expect(engine.state.disputes.keys, [0]);
  });

  test('the right answer: the other pays and the liar is caught', () {
    final engine = _trip();
    setReputation(engine, 80);
    final events = engine.ok(const ResolveDispute(0, 'p1'));
    expect(eventsOf<FareSent>(events).single.passengerId, 'p2');
    expect(eventsOf<LiarCaught>(events).single.passengerId, 'p2');
    expect(spoken(events, 'p2').first, SpeechSlot.caught);
    expect(eventsOf<ReputationChanged>(events).single.value, 90);
    expect(eventsOf<DisputeResolved>(events).single.right, isTrue);
    expect(engine.state.counters.caughtLiars, 1);
    expect(engine.state.disputes, isEmpty);
  });

  for (final (name, p1Pays, p2Pays, paid) in [
    ('a wrong answer', true, false, 'p2'),
    ('both having paid', true, true, 'p1'),
    ('neither having paid', false, false, 'p1'),
  ]) {
    test('$name is a false accusation against the other', () {
      final engine = _trip(p1Pays: p1Pays, p2Pays: p2Pays);
      final other = paid == 'p1' ? 'p2' : 'p1';
      final events = engine.ok(ResolveDispute(0, paid));
      expect(eventsOf<FalseAccusation>(events).single.passengerId, other);
      expect(spoken(events, other), [SpeechSlot.accused]);
      expect(eventsOf<DisputeResolved>(events).single.right, isFalse);
      expect(engine.state.counters.fights, 1);
    });
  }

  test('a third passenger is a bad argument', () {
    _trip().rejects(const ResolveDispute(0, 'p3'), RejectionCode.badArgument);
  });

  test('once resolved, there is no choice', () {
    final engine = _trip()..ok(const ResolveDispute(0, 'p1'));
    engine.rejects(const ResolveDispute(0, 'p1'), RejectionCode.noChoice);
    engine.rejects(const ResolveDispute(7, 'p1'), RejectionCode.noChoice);
  });

  test('it is dropped when either passenger gets off', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('kobri', 10)
            ..station('gamaa', 40)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
              paysAt: 1,
            )
            ..passenger(
              'p2',
              seat: 'A_m',
              dest: 'kobri',
              payment: [500, 100, 100],
            )
            ..event(EventId.paymentDispute, 5, passengers: ['p1', 'p2']))
          .build(),
    );
    final events = engine.stepToSeconds(12);
    expect(engine.state.disputes, isEmpty);
    expect(eventsOf<DisputeResolved>(events), isEmpty);
    engine.rejects(const ResolveDispute(0, 'p1'), RejectionCode.noChoice);
  });

  test('it may be resolved while paused', () {
    final engine = _trip()..pause();
    final outcome = engine.apply(const ResolveDispute(0, 'p1'));
    expect(outcome, isA<Accepted>());
    expect(engine.status, TripStatus.paused);
  });
}
