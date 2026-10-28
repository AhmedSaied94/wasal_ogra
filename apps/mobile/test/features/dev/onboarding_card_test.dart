import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/features/dev/onboarding_card.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/fuel_lesson_screen.dart';
import 'package:wassal/features/onboarding/presentation/name_screen.dart';
import 'package:wassal/features/onboarding/presentation/scene_page.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';
import 'package:wassal/features/trip/presentation/playtest/trip_list.dart';

import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/first_session.dart';
import '../../helpers/home.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

// The testers' «Onboarding» card on the playtest Home (specs/012-m07-
// onboarding, US6, research R21, tasks.md T098): each first-session screen
// on demand and back to Home, "coach on every tutorial trip", the tutorial
// trips marked in the trip list; nothing of it on prod.

/// A tester past the tutorial, on Home of a [flavor] build with the
/// tutorial fixture's pack, the testers' sheet open (M08) where there is
/// one.
Future<ProviderContainer> _home(
  WidgetTester tester, {
  Flavor flavor = Flavor.staging,
}) async {
  final economy = await testEconomy(
    content: tutorialContent(),
    firstState: (nowMs) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
          displayName: () => 'حمادة',
          tutorialGranted: true,
          progress: {
            for (final trip in tutorialTripIds)
              trip: const TripProgress(
                bestStars: 3,
                plays: 1,
                firstCompletedAtMs: 1,
              ),
          },
        ),
  );
  await preloadTripArt(tester);
  final container = await pumpWassalApp(
    tester,
    flavor: flavor,
    newPlayer: true,
    content: contentTestOverrides(assets: tutorialBundledAssetsAllFlavors()),
    economy: economyOverridesOf(economy),
    overrides: seededFirstSession((store) async {
      await store.markOpeningDone(0);
      await store.markFuelLessonDone(0);
      await store.reachStep(lastFirstSessionStep);
      for (final scene in tutorialPlanOf(
        tutorialContent(),
      ).afterTripScenes.values) {
        await store.markSceneSeen(scene);
      }
    }),
  );
  if (flavor != Flavor.prod) await openDebugSheet(tester);
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Ends the scene on screen with «تخطّي».
Future<void> _skip(WidgetTester tester) async {
  await tester.tap(find.byKey(ScenePlayer.skipKey));
  await tester.pumpAndSettle();
}

void main() {
  final plan = tutorialPlanOf(tutorialContent());

  testWidgets('the opening scene, then the Name card, then Home', (
    tester,
  ) async {
    await _home(tester);
    expect(plan.openingScene, isNotNull);
    await _tap(tester, find.byKey(OnboardingCard.openingKey));
    expect(currentLocation(tester), '/onboarding/intro?then=%2Fhome');
    expect(find.byType(ScenePage), findsOneWidget);

    await _skip(tester);
    expect(currentLocation(tester), '/onboarding/name?then=%2Fhome');
    await _tap(tester, find.byKey(NameScreen.ctaKey));
    expect(currentLocation(tester), '/home');
  });

  testWidgets('the Name card, then Home', (tester) async {
    await _home(tester);
    await _tap(tester, find.byKey(OnboardingCard.nameKey));
    expect(currentLocation(tester), '/onboarding/name?then=%2Fhome');
    expect(find.byType(NameScreen), findsOneWidget);
    await _tap(tester, find.byKey(NameScreen.ctaKey));
    expect(currentLocation(tester), '/home');
  });

  testWidgets('each after-trip scene, then Home', (tester) async {
    await _home(tester);
    expect(plan.afterTripScenes, isNotEmpty);
    for (final scene in plan.afterTripScenes.values) {
      await _tap(tester, find.byKey(OnboardingCard.sceneKey(scene)));
      expect(currentLocation(tester), '/onboarding/scene/$scene?then=%2Fhome');
      expect(find.byType(ScenePage), findsOneWidget);
      await _skip(tester);
      expect(currentLocation(tester), '/home');
    }
  });

  testWidgets('the fuel lesson, then Home', (tester) async {
    await _home(tester);
    await _tap(tester, find.byKey(OnboardingCard.fuelKey));
    expect(currentLocation(tester), '/onboarding/fuel');
    expect(find.byType(FuelLessonScreen), findsOneWidget);
    await _tap(tester, find.byKey(FuelLessonScreen.ctaKey));
    expect(currentLocation(tester), '/home');
  });

  testWidgets('the switch coaches a finished tutorial trip', (tester) async {
    final container = await _home(tester);
    final trip = tutorialTripIds[1];
    expect(container.read(tutorialCoachProvider(trip)), isNull);

    final toggle = find.byKey(OnboardingCard.coachEverywhereKey);
    expect(tester.widget<AppSwitch>(toggle).value, isFalse);
    await _tap(tester, toggle);
    expect(tester.widget<AppSwitch>(toggle).value, isTrue);
    expect(container.read(coachEverywhereProvider), isTrue);
    expect(container.read(tutorialCoachProvider(trip)), 1);
    // A trip outside the tutorial stays uncoached.
    expect(container.read(tutorialCoachProvider('line_gamaa.01')), isNull);

    await _tap(tester, toggle);
    expect(container.read(tutorialCoachProvider(trip)), isNull);
  });

  testWidgets('the trip list marks the tutorial trips', (tester) async {
    await _home(tester);
    for (final (i, trip) in tutorialTripIds.indexed) {
      final mark = find.byKey(TripList.tutorialKey(trip));
      expect(mark, findsOneWidget, reason: trip);
      expect(
        find.descendant(of: mark, matching: find.textContaining('${i + 1}')),
        findsNothing,
        reason: 'Arabic-Indic digits, not Western',
      );
    }
    expect(find.byKey(TripList.tutorialKey('line_gamaa.01')), findsNothing);
  });

  testWidgets('a prod build has neither the card nor the marks', (
    tester,
  ) async {
    await _home(tester, flavor: Flavor.prod);
    expect(find.byType(OnboardingCard), findsNothing);
    expect(find.byKey(OnboardingCard.coachEverywhereKey), findsNothing);
    expect(find.byType(TripList), findsNothing);
    for (final trip in tutorialTripIds) {
      expect(find.byKey(TripList.tutorialKey(trip)), findsNothing);
    }
  });
}
