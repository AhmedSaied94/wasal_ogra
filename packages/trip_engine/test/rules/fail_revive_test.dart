// Failing and reviving (rules.md §4.12, §10, clarification 3).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/default_params.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

// p1 pays 1000 at 1 s; short change of 200 reaches him at 3300. p2 is a
// false claimer whose claim stays open.
TripBuilder _trip({bool noFights = false}) => TripBuilder()
  ..station('gamaa', 40)
  ..passenger('p1', seat: 'A_r', dest: 'gamaa', payment: [1000], paysAt: 1)
  ..passenger(
    'p2',
    seat: 'A_m',
    dest: 'gamaa',
    payment: [1000],
    paysAt: 1,
    archetype: Archetype.falseClaimer,
  )
  ..rules(noFightsRequired: noFights);

// Fails the trip at 3300 with short change at reputation 5.
TripEngine _failed({bool noFights = false}) {
  final engine = startTrip(_trip(noFights: noFights).build())..stepTo(2145);
  setReputation(engine, 5);
  engine
    ..ok(const PickFromTray(100))
    ..ok(const PickFromTray(100))
    ..ok(const SendHand('p1'))
    ..stepTo(3300);
  return engine;
}

void main() {
  test('reputation at 0 fails the trip at once, and the clock stops', () {
    final engine = _failed();
    expect(engine.status, TripStatus.failed);
    expect(engine.state.tMs, 3300);
    expect(engine.step(), isEmpty);
    expect(engine.stepToSeconds(20), isEmpty);
    expect(engine.state.tMs, 3300);
    expect(engine.state.claims.keys, ['p2']);
    expect(engine.state.revivable, isTrue);
  });

  test('TripFailed carries the breakdown, short change included', () {
    final engine = startTrip(_trip().build())..stepTo(2145);
    setReputation(engine, 5);
    engine
      ..ok(const PickFromTray(100))
      ..ok(const PickFromTray(100))
      ..ok(const SendHand('p1'));
    final failed = eventsOf<TripFailed>(engine.stepTo(3300)).single;
    expect(failed.reputationLost, {RepCause.shortChange: 5});
    expect(failed.revivable, isTrue);
  });

  test('a failed result has 0 stars and no earnings', () {
    final result = _failed().result!;
    expect(result.outcome, TripOutcome.failed);
    expect((result.stars, result.earningsJenehat), (0, 0));
    expect(result.starFlags.reached, isFalse);
  });

  test('a revive goes on at rep_revive_to from the same point', () {
    final engine = _failed();
    final events = engine.ok(const Revive());
    final revive = eventsOf<ReputationChanged>(events).single;
    expect((revive.cause, revive.value), (RepCause.revive, 40));
    expect(eventsOf<TripRevived>(events).single.reputation, 40);
    expect(engine.status, TripStatus.running);
    expect(engine.result, isNull);
    expect(engine.state.tMs, 3300);
    engine.stepToSeconds(50);
    expect(engine.result!.revived, isTrue);
    expect(engine.result!.outcome, TripOutcome.finished);
  });

  test('a second revive is not_revivable', () {
    final engine = _failed()..ok(const Revive());
    setReputation(engine, 1);
    engine
      ..ok(const PickFromTray(50))
      ..ok(const SendHand('p1'))
      ..stepToSeconds(6);
    expect(engine.status, TripStatus.failed);
    engine.rejects(const Revive(), RejectionCode.notRevivable);
  });

  test('a revive while running is wrong_status', () {
    startTrip(_trip().build())
        .rejects(const Revive(), RejectionCode.wrongStatus);
  });

  test('in a no-fights trip the first fight fails it for good', () {
    final engine = startTrip(_trip(noFights: true).build())..stepToSeconds(41);
    expect(engine.status, TripStatus.failed);
    expect(engine.result!.fights, 1);
    expect(engine.state.revivable, isFalse);
    engine.rejects(const Revive(), RejectionCode.notRevivable);
  });

  test('so does the first false accusation', () {
    final engine = startTrip(_trip(noFights: true).build())..stepToSeconds(5);
    engine
      ..ok(const Tap('p1'))
      ..ok(const ResolveClaim('p1', insist: true));
    expect(engine.status, TripStatus.failed);
    expect(engine.state.revivable, isFalse);
  });

  test('a reputation failure there with no fight is revivable', () {
    final engine = _failed(noFights: true);
    expect(engine.status, TripStatus.failed);
    expect(engine.state.revivable, isTrue);
  });

  group('failing while paused', () {
    test('an answer that ends the trip goes from paused to failed', () {
      final engine = startTrip(_trip(noFights: true).build())..stepToSeconds(5);
      engine
        ..ok(const Tap('p1'))
        ..pause();
      final at = engine.state.tMs;
      final events = engine.ok(const ResolveClaim('p1', insist: true));
      expect(eventsOf<TripFailed>(events), hasLength(1));
      expect((engine.status, engine.state.tMs), (TripStatus.failed, at));
      engine.resume();
      expect(engine.status, TripStatus.failed);
      final replayed = replay(
        engine.definition,
        engine.params,
        engine.seed,
        engine.commandLog,
      );
      expect(replayed.toJson(), engine.result!.toJson());
      expect(replayed.durationMs, at);
    });

    test('so does a declined change request that takes reputation to 0', () {
      final engine = startTrip(
        (_trip()..event(
              EventId.changeRequest,
              5,
              passengers: ['p1'],
              amount: 1000,
            ))
            .build(),
      )..stepToSeconds(6);
      setReputation(engine, defaultParams().repChangeRequestDeclined);
      engine.pause();
      engine.ok(const ResolveChangeRequest('p1', agree: false));
      expect(engine.status, TripStatus.failed);
      expect(engine.state.revivable, isTrue);
    });
  });
}
