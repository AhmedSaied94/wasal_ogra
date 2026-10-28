import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/fuel_lesson_screen.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart' show Locale;

import '../../../helpers/content.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/first_session.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// المعلم's fuel lesson (contracts/fuel-lesson.md Part 2): the gauge from the
// tank to full, the gift on the button with the lesson marked and the trip
// next, an earlier gift taken in stride, no way back, nothing written
// before the button, and the refill line from `fuel_regen_minutes`.

const _numbers = NumberFormatter(DigitStyle.arabicIndic);
final _l10n = lookupAppLocalizations(const Locale('ar'));

String _gauge(int liters) =>
    _l10n.fuelLessonGauge(_numbers.integer(liters), _numbers.integer(5));

/// A new player four trips in, with [liters] in the tank, on the lesson
/// before trip 5.
Future<(ProviderContainer, TestEconomy)> _lesson(
  WidgetTester tester, {
  int liters = 1,
  bool granted = false,
  List<Override> overrides = const [],
}) async {
  final economy = await testEconomy(
    content: tutorialContent(),
    firstState: (nowMs) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
          displayName: () => 'حمادة',
          fuel: FuelState(liters: liters, countedFromMs: nowMs),
          tutorialGranted: granted,
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
    content: contentTestOverrides(assets: tutorialBundledAssets()),
    economy: economyOverridesOf(economy),
    trip: tripTestOverrides(),
    overrides: [
      ...seededFirstSession((store) async {
        await store.markOpeningDone(0);
        await store.reachStep(7);
      }),
      ...overrides,
    ],
  );
  // One frame on the lesson: the gauge as it opens.
  container.read(routerProvider).go('/onboarding/fuel?then=line_hay.05');
  await tester.pump();
  await tester.pump();
  return (container, economy);
}

String _gaugeLabel(WidgetTester tester) =>
    tester.getSemantics(find.byKey(FuelLessonScreen.gaugeKey)).label;

Future<void> _tapCta(WidgetTester tester) async {
  await tester.tap(find.byKey(FuelLessonScreen.ctaKey));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// [text] on the lesson, not on Home's fuel pill beneath it.
Finder _inLesson(String text) => find.descendant(
  of: find.byType(FuelLessonScreen),
  matching: find.text(text),
);

void main() {
  testWidgets('the gauge starts at the tank, then sweeps to full', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _lesson(tester);
    expect(_inLesson(_numbers.ratio(1, 5)), findsOneWidget);
    await pumpFrames(tester);
    expect(_inLesson(_numbers.ratio(5, 5)), findsOneWidget);
    expect(_gaugeLabel(tester), _gauge(5));
    semantics.dispose();
  });

  testWidgets('reduced motion: the gauge is drawn full', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _lesson(tester);
    expect(_inLesson(_numbers.ratio(5, 5)), findsOneWidget);
  });

  testWidgets('the button: the gift, the lesson done, then the trip', (
    tester,
  ) async {
    final (container, economy) = await _lesson(tester);
    await _tapCta(tester);
    expect(economy.service.state.tutorialGranted, isTrue);
    // Full, less the liter trip 5 has just taken.
    expect(economy.service.view.fuel.liters, 5 - 1);
    expect(economy.service.view.unfinished?.tripId, 'line_hay.05');
    expect(
      container.read(firstSessionFlagsProvider).value?.fuelLessonDoneAtMs,
      isNotNull,
    );
    expect(currentLocation(tester), '/trip/line_hay.05');
  });

  testWidgets('a failed lesson write: reported, the button back, then on', (
    tester,
  ) async {
    final (container, economy) = await _lesson(
      tester,
      overrides: [
        firstSessionFlagsProvider.overrideWith(
          () => FailingFlags({'fuelLesson'}),
        ),
      ],
    );
    await _tapCta(tester);
    expect(tester.takeException(), isA<Exception>());
    expect(economy.service.state.tutorialGranted, isTrue);
    expect(
      container.read(firstSessionFlagsProvider).value?.fuelLessonDoneAtMs,
      isNull,
    );
    expect(currentLocation(tester), '/onboarding/fuel?then=line_hay.05');

    // The gift reads as granted; the flag is written this time.
    await _tapCta(tester);
    expect(tester.takeException(), isNull);
    expect(
      container.read(firstSessionFlagsProvider).value?.fuelLessonDoneAtMs,
      isNotNull,
    );
    expect(currentLocation(tester), '/trip/line_hay.05');
  });

  testWidgets('a gift granted meanwhile: on without an error', (tester) async {
    final (container, _) = await _lesson(tester, granted: true);
    await _tapCta(tester);
    expect(tester.takeException(), isNull);
    expect(
      container.read(firstSessionFlagsProvider).value?.fuelLessonDoneAtMs,
      isNotNull,
    );
    expect(currentLocation(tester), '/trip/line_hay.05');
  });

  testWidgets('back does nothing', (tester) async {
    await _lesson(tester);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    expect(currentLocation(tester), '/onboarding/fuel?then=line_hay.05');
  });

  testWidgets('before the button nothing is written (a kill there repeats '
      'the lesson)', (tester) async {
    final (container, economy) = await _lesson(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(economy.service.state.tutorialGranted, isFalse);
    expect(economy.service.view.fuel.liters, 1);
    expect(
      container.read(firstSessionFlagsProvider).value?.fuelLessonDoneAtMs,
      isNull,
    );
  });

  testWidgets('the refill line from fuel_regen_minutes', (tester) async {
    final (container, _) = await _lesson(tester);
    final minutes = container
        .read(configSourceProvider)
        .read(Tunable.fuelRegenMinutes);
    expect(
      find.text(_l10n.fuelLessonRefill(minutes, _numbers.integer(minutes))),
      findsOneWidget,
    );
  });

  test('the refill line agrees with its number', () {
    expect(_l10n.fuelLessonRefill(5, '5'), contains('دقايق'));
    expect(_l10n.fuelLessonRefill(20, '20'), contains('دقيقة'));
  });
}
