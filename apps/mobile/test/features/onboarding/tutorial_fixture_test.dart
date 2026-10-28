import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../../helpers/content.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

// The self-test of test/helpers/tutorial_content.dart (tasks.md T004).

void main() {
  test('the five tutorial trips are line_hay.01–05, in order', () {
    final trips = tutorialContent().tripsOf(LineId.lineHay);
    expect(trips.map((t) => t.tripId), tutorialTripIds);
  });

  test('every tutorial trip starts on the engine with the bundled params', () {
    for (final id in tutorialTripIds) {
      final definition = tutorialTrip(id);
      expect(
        () => TripEngine.start(definition, bundledParams(definition.lineId)),
        returnsNormally,
        reason: id,
      );
    }
  });

  test(
    "the draft's line_hay replaces the sample's; the rest is the sample's",
    () {
      final tutorial = tutorialContent();
      final sample = sampleActiveContent().source;
      final stations = tutorial.line(LineId.lineHay)!.stations;
      expect(stations.map((s) => s.stationId), contains('ishreen'));
      expect(
        tutorial.tripsOf(LineId.lineGamaa).map((t) => t.tripId),
        sample.tripsOf(LineId.lineGamaa).map((t) => t.tripId),
      );
      expect(tutorial.chapters.map((c) => c.chapterId), [
        for (final c in sample.chapters) c.chapterId,
      ]);
    },
  );

  test("the sleeper's pools are there, and the sample's stay", () {
    final tutorial = tutorialContent();
    for (final key in [
      'sleeper.boards',
      'sleeper.missed_stop',
      'sleeper.woke',
    ]) {
      expect(tutorial.speechPool(key)?.lines, isNotEmpty, reason: key);
    }
    expect(tutorial.speechPool('passenger.boards')?.lines, isNotEmpty);
  });
}
