import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/first_session.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';
import '../design_check.dart';

// `FuelLesson` as a new player reaches it before trip 5 of the tutorial:
// four trips played, one liter left, and the gauge settled at full, as the
// board draws it.

Future<void> pumpFuelLesson(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  final economy = await testEconomy(
    content: tutorialContent(),
    firstState: (nowMs) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
          displayName: () => 'حمادة',
          fuel: FuelState(liters: 1, countedFromMs: nowMs),
          progress: {
            for (final trip in tutorialTripIds.take(4))
              trip: const TripProgress(
                bestStars: 1,
                plays: 1,
                firstCompletedAtMs: 1,
              ),
          },
        ),
  );
  await preloadTripArt(tester);
  final container = await pumpWassalApp(
    tester,
    newPlayer: true,
    digits: digits,
    content: contentTestOverrides(assets: tutorialBundledAssets()),
    economy: economyOverridesOf(economy),
    trip: tripTestOverrides(),
    overrides: seededFirstSession((store) async {
      await store.markOpeningDone(0);
      await store.reachStep(7);
    }),
  );
  applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  container.read(routerProvider).go('/onboarding/fuel?then=line_hay.05');
  // The card comes in, then the needle sweeps to full.
  await tester.pump();
  await tester.pump(MotionTokens.dialogIn);
  await tester.pumpAndSettle();
}
