import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';

import 'coached_player.dart';
import 'economy.dart';
import 'trip.dart';
import 'tutorial_content.dart';

// The coached player's own test: it takes each step's target and ends the
// trip.

void main() {
  test('takes the cell three times, then the rider', () async {
    final economy = await testEconomy(content: tutorialContent());
    final c = testController(economy, coachLesson: () => 1);
    await c.open('line_hay.02');
    final run = await playCoached(c);
    expect(run.steps, [CoachStepId.giveChange]);
    // The step's rider got their change: never a fight.
    expect(run.result.reputationLost[RepCause.fight], isNull);
  });

  test("lesson 0: the scrim's tap", () async {
    final economy = await testEconomy(content: tutorialContent());
    final c = testController(economy, coachLesson: () => 0);
    await c.open('line_hay.01');
    final run = await playCoached(c);
    expect(run.steps, [CoachStepId.fareArrived]);
    expect(c.engine!.state.status, isNot(TripStatus.running));
  });

  test('no lesson: no step, the clock alone', () async {
    final economy = await testEconomy(content: tutorialContent());
    final c = testController(economy);
    await c.open('line_hay.02');
    expect((await playCoached(c)).steps, isEmpty);
  });

  test('on its own: every owed rider gets their change', () async {
    final economy = await testEconomy(content: tutorialContent());
    final c = testController(economy);
    await c.open('line_hay.05');
    final run = await playCoached(c, onItsOwn: true);
    expect(run.steps, isEmpty);
    expect(run.result.reputationLost[RepCause.fight], isNull);
    expect(run.result.reputationLost[RepCause.shortChange], isNull);
  });
}
