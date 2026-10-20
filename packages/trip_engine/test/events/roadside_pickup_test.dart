// roadside_pickup and skipped events (rules.md §8, §9.5).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

// p2 waits for the free A_m; p3 for A_r, which p1 frees at kobri (10 s).
TripBuilder _trip() => TripBuilder()
  ..station('kobri', 10)
  ..station('gamaa', 40)
  ..passenger(
    'p1',
    seat: 'A_r',
    dest: 'kobri',
    payment: [500, 100, 100],
    paysAt: 1,
  )
  ..passenger('p2', seat: 'A_m', dest: 'gamaa', payment: [500, 100, 100])
  ..passenger('p3', seat: 'A_r', dest: 'gamaa', payment: [500, 100, 100])
  ..event(EventId.roadsidePickup, 5, passengers: ['p2', 'p3']);

void main() {
  test('listed passengers start waiting', () {
    final engine = startTrip(_trip().build());
    expect(engine.passenger('p2').presence, Presence.waiting);
    expect(engine.passenger('p3').presence, Presence.waiting);
  });

  test('one whose seat is free boards at the event, with a speech', () {
    final engine = startTrip(_trip().build());
    final events = engine.stepToSeconds(6);
    final boarded = eventsOf<PassengerBoarded>(events).single;
    expect(
      (boarded.passengerId, boarded.seatId, boarded.tMs),
      ('p2', 'A_m', 5016),
    );
    expect(spoken(events, 'p2'), [SpeechSlot.boards]);
    expect(engine.passenger('p3').pickupDue, isTrue);
    expect(engine.passenger('p3').presence, Presence.waiting);
  });

  test('one whose seat is taken boards the moment it is freed', () {
    final engine = startTrip(_trip().build());
    final events = engine.stepToSeconds(12);
    final atKobri = [
      for (final e in events)
        if (e is PassengerAlighted || e is PassengerBoarded) e.name,
    ];
    expect(atKobri, [
      'PassengerBoarded',
      'PassengerAlighted',
      'PassengerBoarded',
    ]);
    final p3 = engine.passenger('p3');
    expect((p3.presence, p3.pickupDue), (Presence.aboard, false));
  });

  test('an event naming a passenger who is not aboard is skipped', () {
    final engine = startTrip(
      (_trip()
            ..event(EventId.dropMeHere, 6, passengers: ['p3'])
            ..event(
              EventId.changeRequest,
              12,
              passengers: ['p1'],
              amount: 1000,
            ))
          .build(),
    );
    final events = engine.stepToSeconds(13);
    expect(eventsOf<EventSkipped>(events).map((e) => (e.index, e.eventId)), [
      (1, EventId.dropMeHere),
      (2, EventId.changeRequest),
    ]);
    expect(engine.passenger('p3').deadlineMs, isNull);
    expect(engine.state.changeRequests, isEmpty);
  });

  test('a second change request while one is open is skipped', () {
    final engine = startTrip(
      (_trip()
            ..event(EventId.changeRequest, 6, passengers: ['p2'], amount: 1000)
            ..event(EventId.changeRequest, 7, passengers: ['p2'], amount: 2000))
          .build(),
    );
    final events = engine.stepToSeconds(8);
    expect(eventsOf<ChangeRequestRaised>(events), hasLength(1));
    expect(eventsOf<EventSkipped>(events).single.index, 2);
  });
}
