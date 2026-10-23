import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../../../helpers/trip.dart';

// A passenger's face and pose (tasks.md T056, contracts/trip-view.md
// "Passenger look and mood"), at every moment of every fixture.

void main() {
  test('mood, alertness and talking follow the state', () {
    final moods = <int>{};
    final alertness = <Alertness>{};
    var talking = 0;
    for (final name in allFixtureNames()) {
      playWithMemory(loadFixture(name), (state, view, _) {
        final failed = state.status == TripStatus.failed;
        for (final v in view.passengers) {
          final p = state.passenger(v.passengerId)!;
          final at = '$name at ${state.tMs} ms, ${v.passengerId}';
          final share = p.patiencePermille;
          final mood = failed || p.impatient || p.outcome == AlightOutcome.fight
              ? 3
              : share != null && share <= 333
              ? 2
              : share != null && share <= 666
              ? 1
              : 0;
          expect(v.mood, mood, reason: at);
          moods.add(v.mood);

          expect(v.asleep, p.alertness == Alertness.asleep, reason: at);
          expect(v.waking, p.alertness == Alertness.waking, reason: at);
          expect(v.headphones, p.alertness == Alertness.muted, reason: at);
          expect(v.attentive, p.alertness == Alertness.attentive, reason: at);
          alertness.add(p.alertness);

          final speaking = view.bubbles.any(
            (b) => b.passengerId == v.passengerId,
          );
          expect(v.talking, speaking, reason: at);
          if (speaking) talking++;
        }
      });
    }
    // Every face and pose was seen.
    expect(moods, {0, 1, 2, 3});
    expect(alertness, Alertness.values.toSet());
    expect(talking, greaterThan(0));
  });
}
