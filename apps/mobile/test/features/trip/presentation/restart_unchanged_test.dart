import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Key;
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/presentation/cards/failure_card.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';

import '../../../helpers/content.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/first_session.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/routing.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// «عيد المشوار» is M02's, unchanged (specs/013-m08-home-result research
// R17, Clarifications Q2): on the pause and the failure cards it starts the
// same trip again at once, for a liter, with no pre-trip card, story and
// tutorial trips included.

/// Taps [restart] and checks the trip started again: same route, no card,
/// the clock at 0, one liter and one more start.
Future<void> _expectRestarted(
  WidgetTester tester,
  TestEconomy economy, {
  required String tripId,
  required Key restart,
}) async {
  final liters = economy.service.view.fuel.liters;
  final starts = await opCount(economy, 'trip_start');
  await tester.tap(find.byKey(restart));
  await tester.pumpAndSettle();
  expect(currentLocation(tester), '/trip/$tripId');
  expect(find.byType(PreTripCard), findsNothing);
  final c = controllerOf(tester);
  expect(c.phase, TripPhase.running);
  expect(c.engine!.state.tMs, 0);
  expect(economy.service.view.fuel.liters, liters - 1);
  expect(await opCount(economy, 'trip_start'), starts + 1);
}

void main() {
  testWidgets('from the pause card', (tester) async {
    final economy = await stockedEconomy();
    await pumpTrip(tester, economy: economy);
    await pressBack(tester);
    await _expectRestarted(
      tester,
      economy,
      tripId: 'line_hay.01',
      restart: PauseCard.restartKey,
    );
  });

  testWidgets('from the failure card', (tester) async {
    final f = loadFixture('ending__failed');
    final economy = await stockedEconomy();
    await pumpTrip(
      tester,
      tripId: f.definition.tripId,
      economy: economy,
      fixed: FixedTrip(
        definition: f.definition,
        params: f.params,
        seed: f.seed,
      ),
    );
    final c = controllerOf(tester);
    while (c.phase == TripPhase.running) {
      c.advance(const Duration(milliseconds: engineStepMs));
    }
    await tester.pumpAndSettle();
    expect(find.byType(FailureCard), findsOneWidget);
    await _expectRestarted(
      tester,
      economy,
      tripId: f.definition.tripId,
      restart: FailureCard.restartKey,
    );
  });

  testWidgets('a story trip', (tester) async {
    final economy = await stockedEconomy();
    await pumpTrip(tester, tripId: 'line_hay.03', economy: economy);
    await pressBack(tester);
    await _expectRestarted(
      tester,
      economy,
      tripId: 'line_hay.03',
      restart: PauseCard.restartKey,
    );
  });

  testWidgets('a tutorial trip in the first session', (tester) async {
    final economy = await testEconomy(content: tutorialContent());
    final container = await pumpTrip(
      tester,
      tripId: 'line_hay.02',
      economy: economy,
      newPlayer: true,
      content: contentTestOverrides(assets: tutorialBundledAssets()),
      overrides: seededFirstSession((store) async {
        await store.markOpeningDone(0);
        await store.reachStep(2);
      }),
    );
    expect(container.read(firstSessionProvider).inFirstSession, isTrue);
    await pressBack(tester);
    await _expectRestarted(
      tester,
      economy,
      tripId: 'line_hay.02',
      restart: PauseCard.restartKey,
    );
  });
}
