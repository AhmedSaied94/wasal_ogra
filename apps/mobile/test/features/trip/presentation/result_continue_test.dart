import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/first_session_continue.dart';

import '../../../helpers/content.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/first_session.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// «كمّل» on the result placeholder (contracts/first-session.md "The result
// screen"): through the first session, and once after the trip that ends
// it, to the next tutorial trip or Home. Never afterwards; Home stays
// linked.

Finder get _continue => find.byKey(FirstSessionContinue.buttonKey);

/// A new player past the opening and the fuel lesson, who finished tutorial
/// trips 1 to [finished], on [tripId]'s result.
Future<ProviderContainer> _result(
  WidgetTester tester,
  String tripId, {
  required int finished,
  bool newPlayer = true,
}) async {
  final economy = await testEconomy(
    content: tutorialContent(),
    firstState: (nowMs) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
          displayName: () => 'حمادة',
          progress: {
            for (final trip in tutorialTripIds.take(finished))
              trip: const TripProgress(
                bestStars: 1,
                plays: 1,
                firstCompletedAtMs: 1,
              ),
          },
        ),
  );
  await preloadTripArt(tester);
  return pumpWassalApp(
    tester,
    newPlayer: newPlayer,
    initialLocation: '/trip/$tripId/result',
    content: contentTestOverrides(assets: tutorialBundledAssets()),
    economy: economyOverridesOf(economy),
    trip: tripTestOverrides(),
    overrides: newPlayer
        ? seededFirstSession((store) async {
            await store.markOpeningDone(0);
            await store.markFuelLessonDone(0);
            await store.reachStep(2 + finished);
          })
        : const [],
  );
}

/// Taps «كمّل» and lets the next page open (a trip never settles).
Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(_continue);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('in the first session: «كمّل» to the next tutorial trip', (
    tester,
  ) async {
    await _result(tester, 'line_hay.01', finished: 1);
    expect(_continue, findsOneWidget);
    expect(
      find.byKey(PlaceholderScreen.linkKey(RouteNames.home)),
      findsWidgets,
    );
    await _tapContinue(tester);
    expect(currentLocation(tester), '/trip/line_hay.02');
  });

  testWidgets('after the trip that ends the tutorial: «كمّل» to Home', (
    tester,
  ) async {
    final container = await _result(tester, 'line_hay.05', finished: 5);
    container.read(tutorialEndedOnProvider.notifier).tripId = 'line_hay.05';
    await tester.pump();
    expect(_continue, findsOneWidget);
    await _tapContinue(tester);
    expect(currentLocation(tester), '/home');
    expect(container.read(tutorialEndedOnProvider), isNull);
  });

  testWidgets('afterwards: no «كمّل»', (tester) async {
    await _result(tester, 'line_hay.05', finished: 5);
    expect(_continue, findsNothing);
    expect(
      find.byKey(PlaceholderScreen.linkKey(RouteNames.home)),
      findsWidgets,
    );
  });

  testWidgets('a returning player: no «كمّل»', (tester) async {
    await _result(tester, 'line_hay.02', finished: 0, newPlayer: false);
    expect(_continue, findsNothing);
  });
}
