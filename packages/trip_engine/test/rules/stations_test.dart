// Stations (rules.md §9.2–§9.5) and the end of the trip (§11).
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

const _exact = [500, 100, 100, 100, 50];

/// At kobri (30 s, fare 850): p1 owed 150, p2 settled, p4 never pays. p3
/// rides on to gamaa.
TripBuilder _trip() => TripBuilder()
  ..station('kobri', 30, fare: 850)
  ..station('gamaa', 60, fare: 850)
  ..passenger('p1', seat: 'A_r', dest: 'kobri', payment: [1000], paysAt: 0)
  ..passenger('p2', seat: 'B_r', dest: 'kobri', payment: _exact, paysAt: 0)
  ..passenger('p3', seat: 'C_r', dest: 'gamaa', payment: _exact, paysAt: 0)
  ..passenger('p4', seat: 'A_m', dest: 'kobri', payment: [1000]);

void main() {
  test('the warning comes trip_station_warning_ms before the station', () {
    final engine = startTrip(_trip().build());
    expect(eventsOf<StationWarning>(engine.stepTo(21978)), isEmpty);
    final events = engine.step();
    final warning = eventsOf<StationWarning>(events).single;
    expect(warning.tMs, 22011);
    expect(warning.stationId, 'kobri');
    expect(warning.atMs, 30000);
    expect(warning.alighting, ['p1', 'p2', 'p4']);
    expect(warning.owed, ['p1']);
    final speech = eventsOf<PassengerSpeaks>(events).single;
    expect(
      (speech.passengerId, speech.slot, speech.stationId),
      ('p1', SpeechSlot.stopNear, 'kobri'),
    );
    expect(speech.amountPiasters, isNull);
    expect(engine.state.schedule.first.warned, isTrue);
  });

  test('getting off: fight, thanked and left unpaid, in passenger order', () {
    final engine = startTrip(_trip().build())..stepTo(29997);
    final events = engine.step();
    expect(engine.state.tMs, 30030);
    expect(eventsOf<StationReached>(events).single.stationId, 'kobri');
    expect(
      eventsOf<PassengerAlighted>(events)
          .map((e) => (e.passengerId, e.outcome)),
      [
        ('p1', AlightOutcome.fight),
        ('p2', AlightOutcome.thanked),
        ('p4', AlightOutcome.leftUnpaid),
      ],
    );
    final fight = eventsOf<ReputationChanged>(events).single;
    expect((fight.delta, fight.cause), (-30, RepCause.fight));
    expect(engine.state.counters.fights, 1);
    expect(engine.state.counters.lostFares, 1);
    expect(engine.state.mistakes.single.toJson(), {
      'passenger_id': 'p1',
      'kind': 'unreturned',
      'amount_piasters': 150,
    });
    final speech = eventsOf<PassengerSpeaks>(events).single;
    expect(
      (speech.passengerId, speech.slot, speech.amountPiasters),
      ('p1', SpeechSlot.fight, 150),
    );
    expect(engine.passenger('p1').presence, Presence.gone);
    expect(engine.passenger('p1').outcome, AlightOutcome.fight);
    expect(engine.state.nextStationIndex, 1);
    expect(engine.state.nextStation!.stationId, 'gamaa');
  });

  group('boarding', () {
    test('at a station whose seat is free', () {
      final engine = startTrip(
        (_trip()..passenger(
              'p5',
              seat: 'C_l',
              dest: 'gamaa',
              board: 'kobri',
              payment: [1000],
            ))
            .build(),
      );
      expect(engine.passenger('p5').presence, Presence.waiting);
      final events = engine.stepTo(30030);
      final boarded = eventsOf<PassengerBoarded>(events).single;
      expect(
        (boarded.passengerId, boarded.seatId, boarded.tMs),
        ('p5', 'C_l', 30030),
      );
      expect(spoken(events, 'p5'), [SpeechSlot.boards]);
      expect(engine.passenger('p5').presence, Presence.aboard);
    });

    test('into the seat of someone getting off at the same station', () {
      final engine = startTrip(
        (_trip()..passenger(
              'p5',
              seat: 'A_r',
              dest: 'gamaa',
              board: 'kobri',
              payment: [1000],
            ))
            .build(),
      )..stepTo(30030);
      expect(engine.passenger('p5').presence, Presence.aboard);
    });

    test('later, the moment the seat is freed', () {
      final engine = startTrip(
        (TripBuilder()
              ..station('kobri', 10)
              ..station('gamaa', 20)
              ..station('souq', 30)
              ..passenger(
                'p1',
                seat: 'B_m',
                dest: 'gamaa',
                payment: _exact,
                paysAt: 0,
              )
              ..passenger(
                'p2',
                seat: 'B_m',
                dest: 'souq',
                board: 'kobri',
                payment: [1000],
              ))
            .build(),
      )..stepToSeconds(15);
      expect(engine.passenger('p2').presence, Presence.waiting);
      expect(engine.passenger('p2').pickupDue, isTrue);
      final events = engine.stepTo(20031);
      expect(eventsOf<PassengerBoarded>(events).single.passengerId, 'p2');
      expect(engine.passenger('p2').presence, Presence.aboard);
    });

    test('never after their destination has passed', () {
      final engine = startTrip(
        (TripBuilder()
              ..station('kobri', 10)
              ..station('gamaa', 20)
              ..station('souq', 30)
              ..passenger(
                'p1',
                seat: 'B_m',
                dest: 'gamaa',
                payment: _exact,
                paysAt: 0,
              )
              ..passenger(
                'p2',
                seat: 'B_m',
                dest: 'gamaa',
                board: 'kobri',
                payment: [1000],
              ))
            .build(),
      )..stepToSeconds(40);
      expect(engine.passenger('p2').presence, Presence.waiting);
      expect(engine.status, TripStatus.finished);
    });
  });

  test(
    'the last station finishes the trip, after money in transit is settled',
    () {
      final engine = startTrip(
        (TripBuilder()
              ..station('kobri', 1)
              ..passenger(
                'p1',
                seat: 'C_r',
                dest: 'kobri',
                payment: [1000],
                paysAt: 0,
              )
              ..passenger('p2', seat: 'A_r', dest: 'kobri', payment: _exact))
            .build(),
      );
      engine
        ..ok(const PickFromTray(100))
        ..ok(const SendHand('p2'));
      final events = engine.stepToSeconds(5);
      expect(engine.status, TripStatus.finished);
      expect(engine.state.tMs, 1023);
      expect(engine.state.tokens, isEmpty);
      expect(
        eventsOf<MoneyArrivedAtDriver>(events).single.amountPiasters,
        1000,
      );
      expect(engine.state.tray.count(100), 4, reason: 'the change came back');
      final finished = eventsOf<TripFinished>(events).single;
      expect(finished.result.outcome, TripOutcome.finished);
      expect(finished.result.durationMs, 1023);
      expect(engine.result!.toJson(), finished.result.toJson());
      expect(engine.step(), isEmpty);
    },
  );
}
