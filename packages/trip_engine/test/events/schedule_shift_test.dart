// traffic and open_road (rules.md §8, §9.1): the schedule shifts from the
// next station on; events keep the unshifted trip clock.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripBuilder _trip() => TripBuilder()
  ..station('kobri', 30)
  ..station('gamaa', 40)
  ..passenger('p1', seat: 'A_r', dest: 'gamaa', payment: [1000], paysAt: 1);

List<int> _stations(TripEngine engine) => [
  for (final station in engine.state.schedule) station.atMs,
];

void main() {
  test('traffic moves the next station and every later one', () {
    final engine = startTrip(
      (_trip()..event(EventId.traffic, 5, seconds: 10)).build(),
    );
    final events = engine.stepToSeconds(5);
    expect(eventsOf<ScheduleShifted>(events).single.deltaMs, 10000);
    expect(_stations(engine), [40000, 50000]);
    expect(engine.state.trafficActive, isTrue);
  });

  test(
    'traffic stays active until the next station, and drains patience faster',
    () {
      final engine = startTrip(
        (_trip()..event(EventId.traffic, 5, seconds: 10)).build(),
      )..stepToSeconds(5);
      final before = engine.passenger('p1').patienceMs!;
      engine.step();
      expect(engine.passenger('p1').patienceMs, before - 49);
      engine.stepTo(40029);
      expect(engine.state.trafficActive, isFalse);
    },
  );

  test('open road moves them sooner', () {
    final engine = startTrip(
      (_trip()..event(EventId.openRoad, 5, seconds: 10)).build(),
    );
    final events = engine.stepToSeconds(5);
    expect(eventsOf<ScheduleShifted>(events).single.deltaMs, -10000);
    expect(_stations(engine), [20000, 30000]);
  });

  test('open road never brings the next station closer than the warning', () {
    final engine = startTrip(
      (_trip()..event(EventId.openRoad, 15, seconds: 10)).build(),
    );
    final events = engine.stepToSeconds(15);
    // At 15015, kobri can come no sooner than 15015 + 8000.
    expect(eventsOf<ScheduleShifted>(events).single.deltaMs, 23015 - 30000);
    expect(_stations(engine), [23015, 33015]);
  });

  test('shifts add up', () {
    final engine = startTrip(
      (_trip()
            ..event(EventId.traffic, 2, seconds: 10)
            ..event(EventId.traffic, 4, seconds: 5)
            ..event(EventId.openRoad, 6, seconds: 3))
          .build(),
    )..stepToSeconds(7);
    expect(_stations(engine), [42000, 52000]);
  });

  test('events run on the unshifted trip clock', () {
    final engine = startTrip(
      (_trip()
            ..event(EventId.traffic, 2, seconds: 10)
            ..event(EventId.bump, 25))
          .build(),
    );
    final events = engine.stepToSeconds(26);
    expect(eventsOf<EventStarted>(events).map((e) => (e.eventId, e.tMs)), [
      (EventId.traffic, 2013),
      (EventId.bump, 25014),
    ]);
  });
}
