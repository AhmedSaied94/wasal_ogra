import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';

import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

// `Tutorial` (HANDOFF §11 `Tutorial`, specs/012-m07-onboarding/contracts/
// coach.md "The overlay"): a new player on the fixture's `line_hay.02`, the
// tuktuk, when its first rider's change is due. بلية's coach cuts its hole
// on the «١» cell and says how many, and the boosters are the locked bar.
// The real engine and the real coach, to the moment.

/// The trip the sample opens.
const tutorialTripId = 'line_hay.02';

/// The trip screen on the reference frame, the coach on the «١» cell with
/// بلية's bubble up.
Future<void> pumpTutorial(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpTrip(
    tester,
    tripId: tutorialTripId,
    digits: digits,
    newPlayer: true,
    economy: await testEconomy(content: tutorialContent()),
    content: contentTestOverrides(assets: tutorialBundledAssets()),
  );
  final c = controllerOf(tester);
  bool due() =>
      c.model.coach?.target == const TrayCellTarget(100) &&
      c.model.coachBubble != null;
  for (var t = 0; t < 60000 && !due(); t += 33) {
    c.advance(const Duration(milliseconds: 33));
  }
  expect(due(), isTrue, reason: 'the coach never pointed at the «١» cell');
  // The anchors report after a frame, the layer draws on the next, the
  // scrim fades in and the hole settles.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
