// drop_me_here (rules.md §3 step 8.1, §8, §9.2, §9.3): a passenger gets off
// at their deadline instead of their station.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

// p1 in A_r owes 300 from 1023; p2 boards at kobri (10 s) into A_r once p1
// has left it; p3 rides to gamaa in A_m.
TripEngine _trip({int? seconds}) => startTrip(
  (TripBuilder()
        ..station('kobri', 10)
        ..station('gamaa', 40)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'gamaa',
          payment: [1000],
          paysAt: 1,
        )
        ..passenger(
          'p2',
          seat: 'A_r',
          board: 'kobri',
          dest: 'gamaa',
          payment: [500, 100, 100],
        )
        ..passenger('p3', seat: 'A_m', dest: 'gamaa', payment: [500, 100, 100])
        ..event(EventId.dropMeHere, 5, passengers: ['p1'], seconds: seconds))
      .build(),
);

void main() {
  test('the deadline is t + seconds', () {
    final engine = _trip(seconds: 10);
    final events = engine.stepToSeconds(6);
    final changed = eventsOf<StopChanged>(events).single;
    expect((changed.passengerId, changed.deadlineMs), ('p1', 5016 + 10000));
    expect(spoken(events, 'p1'), contains(SpeechSlot.dropMeHere));
  });

  test('without seconds it is t + trip_station_warning_ms', () {
    final engine = _trip()..stepToSeconds(6);
    expect(engine.passenger('p1').deadlineMs, 5016 + 8000);
  });

  test('at the deadline they get off as at a stop, and the seat is taken', () {
    final engine = _trip(seconds: 10);
    final events = engine.stepTo(15048);
    final off = eventsOf<PassengerAlighted>(events).single;
    expect(
      (off.passengerId, off.outcome, off.tMs),
      ('p1', AlightOutcome.fight, 15048),
    );
    expect(engine.result, isNull);
    final boarded = eventsOf<PassengerBoarded>(events).single;
    expect((boarded.passengerId, boarded.tMs), ('p2', 15048));
  });

  test('tokens are handed over at the deadline', () {
    final engine = _trip(seconds: 10)..stepToSeconds(14);
    for (final piece in [100, 100]) {
      engine.ok(PickFromTray(piece));
    }
    engine.ok(const SendHand('p1'));
    final tray = engine.state.tray.total;
    engine.stepTo(15048);
    expect(engine.state.tokens, isEmpty);
    expect(engine.state.tray.total, tray + 200);
  });

  test("their station's warning no longer lists them", () {
    final engine = _trip(seconds: 30);
    final events = engine.stepToSeconds(33);
    final warning = eventsOf<StationWarning>(events).last;
    expect(warning.stationId, 'gamaa');
    expect(warning.alighting, ['p3']);
  });
}
