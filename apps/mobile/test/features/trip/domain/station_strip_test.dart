import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/station_strip.dart';

import '../../../helpers/trip.dart';

void main() {
  test('chips by station order, with names, prices and the student icon', () {
    final definition = sampleTrip('line_hay.01');
    final facts = factsFor(definition);
    final engine = TripEngine.start(definition, facts.params);
    final strip = stationStrip(engine.state, facts);
    expect(strip.chips.map((c) => c.stationId), ['madrasa', 'forn']);
    expect(strip.chips.map((c) => c.slot), [0, 1]);
    expect(strip.chips.map((c) => c.farePiasters), [700, 700]);
    expect(strip.chips.every((c) => c.studentIcon), isTrue);
    expect(strip.chips.first.name, isNotNull);
    expect(strip.chips.first.next, isTrue);
    expect(strip.chips.first.reached, isFalse);
    expect(strip.countdownMs, 30000);
    expect(strip.warning, isFalse);
    expect(strip.vehiclePermille, 0);
  });

  test('without the line, chips have no names', () {
    final definition = sampleTrip('line_hay.01');
    final facts = factsFor(definition, withLine: false);
    final engine = TripEngine.start(definition, facts.params);
    expect(stationStrip(engine.state, facts).chips.first.name, isNull);
  });

  test('countdown, warning and the vehicle follow the clock', () {
    final definition = sampleTrip('line_hay.01');
    final facts = factsFor(definition);
    final engine = TripEngine.start(definition, facts.params);
    final warningMs = facts.params.tripStationWarningMs;
    engine.stepTo(30000 - warningMs - 33 * 3);
    var strip = stationStrip(engine.state, facts);
    expect(strip.warning, isFalse);
    engine.stepTo(30000 - warningMs + 33);
    strip = stationStrip(engine.state, facts);
    expect(strip.warning, isTrue);
    expect(strip.countdownMs, lessThanOrEqualTo(warningMs));
    // Halfway to the first of two stations is a quarter of the strip.
    expect(strip.vehiclePermille, inInclusiveRange(350, 500));
  });

  test('a reached station is marked and the next one leads', () {
    final definition = sampleTrip('line_hay.01');
    final facts = factsFor(definition);
    final engine = TripEngine.start(definition, facts.params);
    engine.stepTo(31000);
    final strip = stationStrip(engine.state, facts);
    expect(strip.chips[0].reached, isTrue);
    expect(strip.chips[1].next, isTrue);
    expect(strip.vehiclePermille, greaterThanOrEqualTo(500));
  });

  test('a fare increase raises every price', () {
    final fixture = loadFixture('event__fare_increase');
    final facts = factsFor(fixture.definition, params: fixture.params);
    final engine = TripEngine.start(
      fixture.definition,
      fixture.params,
      seed: fixture.seed,
    );
    final before = stationStrip(
      engine.state,
      facts,
    ).chips.map((c) => c.farePiasters).toList();
    while (engine.state.fareIncreasePiasters == 0 &&
        engine.status == TripStatus.running) {
      engine.step();
    }
    final increase = engine.state.fareIncreasePiasters;
    expect(increase, greaterThan(0));
    final after = stationStrip(engine.state, facts).chips;
    for (final (i, chip) in after.indexed) {
      expect(chip.farePiasters, before[i] + increase);
    }
  });

  test('a shifted schedule moves the countdown', () {
    final fixture = loadFixture('event__traffic');
    final facts = factsFor(fixture.definition, params: fixture.params);
    final engine = TripEngine.start(
      fixture.definition,
      fixture.params,
      seed: fixture.seed,
    );
    final firstAt = engine.state.schedule.first.atMs;
    var shifted = false;
    while (!shifted && engine.status == TripStatus.running) {
      shifted = engine.step().any((e) => e is ScheduleShifted);
    }
    expect(shifted, isTrue);
    final strip = stationStrip(engine.state, facts);
    expect(
      strip.countdownMs,
      engine.state.nextStation!.atMs - engine.state.tMs,
    );
    expect(engine.state.schedule.first.atMs, isNot(firstAt));
  });

  test('after the last station there is no countdown', () {
    final definition = sampleTrip('line_hay.01');
    final facts = factsFor(definition);
    final engine = TripEngine.start(definition, facts.params);
    engine.stepTo(56000);
    final strip = stationStrip(engine.state, facts);
    expect(strip.countdownMs, isNull);
    expect(strip.vehiclePermille, 1000);
  });
}
