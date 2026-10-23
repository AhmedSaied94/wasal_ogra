// The settled query (rules.md §16): nothing is left for the player, so M02
// runs the rest of the trip faster. No rule reads it.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/src/replay.dart' show playLog, startReplay;
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/fixture_io.dart';
import '../support/scripts.dart';

// p1 pays an exact 700 at 1 s, and gets off at gamaa.
TripBuilder _trip() => TripBuilder()
  ..station('kobri', 10)
  ..station('gamaa', 40)
  ..passenger(
    'p1',
    seat: 'A_r',
    dest: 'gamaa',
    payment: [500, 100, 100],
    paysAt: 1,
  );

void main() {
  test('an exact fare at the driver leaves nothing for the player', () {
    final engine = startTrip(_trip().build());
    expect(engine.isSettled, isFalse, reason: 'p1 has not paid');
    engine.stepTo(1000);
    expect(engine.state.tokens, isNotEmpty);
    expect(engine.isSettled, isFalse, reason: 'the fare is on its way');
    engine.stepToSeconds(5);
    expect(engine.isSettled, isTrue);
    engine.pause();
    expect(engine.isSettled, isTrue, reason: 'paused');
  });

  test('an event still to come holds it', () {
    final engine = startTrip(
      (_trip()..event(EventId.traffic, 20, seconds: 5)).build(),
    )..stepToSeconds(5);
    expect(engine.isSettled, isFalse);
    engine.stepToSeconds(21);
    expect(engine.isSettled, isTrue);
  });

  test('someone waiting at a later station holds it', () {
    final engine = startTrip(
      (_trip()..passenger(
            'p2',
            seat: 'A_m',
            board: 'kobri',
            dest: 'gamaa',
            payment: [500, 100, 100],
            paysAt: 12,
          ))
          .build(),
    )..stepToSeconds(5);
    expect(engine.isSettled, isFalse);
    engine.stepToSeconds(15);
    expect(engine.isSettled, isTrue);
  });

  test('change owed holds it, and so does a fare short of its price', () {
    for (final payment in [
      [1000],
      [500, 100],
    ]) {
      final engine = startTrip(
        (_trip()..passenger(
              'p2',
              seat: 'A_m',
              dest: 'gamaa',
              payment: payment,
              paysAt: 1,
            ))
            .build(),
      )..stepToSeconds(5);
      expect(engine.passenger('p2').balance, isNot(0));
      expect(engine.isSettled, isFalse, reason: '$payment');
    }
  });

  test('a sleeper aboard holds it, awake and paid, until he gets off', () {
    final engine = startTrip(
      (_trip()..passenger(
            'p2',
            seat: 'A_m',
            dest: 'kobri',
            payment: [500, 100, 100],
            paysAt: 1,
            archetype: Archetype.sleeper,
          ))
          .build(),
    );
    engine.ok(const Tap('p2'));
    engine.stepToSeconds(5);
    expect(engine.passenger('p2').fareSent, isTrue);
    expect(engine.passenger('p2').balance, 0);
    expect(engine.isSettled, isFalse);
    engine.stepToSeconds(11);
    expect(engine.passenger('p2').presence, Presence.gone);
    expect(engine.isSettled, isTrue);
  });

  test('a tap on a paid passenger opens a claim, which holds it', () {
    final engine = startTrip(_trip().build())..stepToSeconds(5);
    engine.ok(const Tap('p1'));
    expect(engine.state.claims.keys, ['p1']);
    expect(engine.isSettled, isFalse);
    engine.ok(const ResolveClaim('p1', insist: false));
    expect(engine.isSettled, isTrue);
  });

  test("a believed false claimer and a group's member don't hold it", () {
    final claimer = startTrip(
      (_trip()..passenger(
            'p2',
            seat: 'A_m',
            dest: 'gamaa',
            payment: [500, 100, 100],
            paysAt: 1,
            archetype: Archetype.falseClaimer,
          ))
          .build(),
    )..stepToSeconds(2);
    claimer.ok(const ResolveClaim('p2', insist: false));
    claimer.stepToSeconds(5);
    expect(claimer.passenger('p2').neverPays, isTrue);
    expect(claimer.isSettled, isTrue);

    final group = startTrip(
      (TripBuilder()
            ..station('gamaa', 40)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'gamaa',
              payment: [500, 100, 100, 500, 100, 100],
              paysAt: 1,
              archetype: Archetype.groupPayer,
              group: 'g1',
              groupSize: 2,
            )
            ..passenger(
              'p2',
              seat: 'A_m',
              dest: 'gamaa',
              payment: [1000],
              group: 'g1',
              groupSize: 2,
            ))
          .build(),
    )..stepToSeconds(5);
    expect(group.passenger('p2').fareSent, isFalse);
    expect(group.isSettled, isTrue);
  });

  test('an ended trip is not settled', () {
    final engine = startTrip(_trip().build())..stepToSeconds(41);
    expect(engine.status, TripStatus.finished);
    expect(engine.isSettled, isFalse);
  });

  test('every fixture: once settled after its last command, the rest only '
      'reaches stations', () {
    for (final file in fixtureFiles()) {
      final fixture = loadFixture(file);
      final engine = startReplay(
        fixture.definition,
        fixture.params,
        fixture.seed,
      );
      playLog(engine, fixture.commandLog);
      while (engine.status == TripStatus.running && !engine.isSettled) {
        engine.step();
      }
      if (engine.status != TripStatus.running) continue;
      final name = fixtureName(file);
      final counters = engine.state.counters;
      final mistakes = engine.state.mistakes;
      final events = <DomainEvent>[];
      while (engine.status == TripStatus.running) {
        expect(engine.isSettled, isTrue, reason: '$name stays settled');
        events.addAll(engine.step());
      }
      expect(engine.status, TripStatus.finished, reason: name);
      expect(eventsOf<ReputationChanged>(events), isEmpty, reason: name);
      expect(engine.state.mistakes, mistakes, reason: name);
      final after = engine.state.counters;
      expect(
        (after.fights, after.missedStops, after.impatient, after.caughtLiars),
        (
          counters.fights,
          counters.missedStops,
          counters.impatient,
          counters.caughtLiars,
        ),
        reason: name,
      );
      expect(
        eventsOf<PassengerAlighted>(events).map((e) => e.outcome),
        everyElement(anyOf(AlightOutcome.thanked, AlightOutcome.leftUnpaid)),
        reason: name,
      );
    }
  });

  test('the sample trips settle well before the end of the line', () {
    for (final file in fixtureFiles()) {
      final name = fixtureName(file);
      if (!name.startsWith('solver__')) continue;
      final fixture = loadFixture(file);
      final engine = startReplay(
        fixture.definition,
        fixture.params,
        fixture.seed,
      );
      playLog(engine, fixture.commandLog);
      while (engine.status == TripStatus.running && !engine.isSettled) {
        engine.step();
      }
      expect(engine.isSettled, isTrue, reason: name);
      final settledAt = engine.state.tMs;
      engine.stepTo(1 << 30);
      expect(
        engine.state.tMs - settledAt,
        greaterThanOrEqualTo(15000),
        reason: name,
      );
    }
  });
}
