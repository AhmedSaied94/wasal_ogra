// A trip survives the app's end (specs/008-m02-trip-screen FR-055): on the
// real database file, the app's scope is disposed mid-trip and a fresh one
// pumped over the same file. CI doesn't run this. On a device:
//
//   fvm flutter test integration_test/trip_relaunch_test.dart --flavor dev
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';

import '../test/helpers/pump_app.dart';
import '../test/helpers/trip.dart';
import 'trip_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a trip left mid-way opens paused at the same clock', (
    tester,
  ) async {
    await tester.runAsync(deleteAppDatabase);
    final fixture = loadFixture('sample__line_hay_01_three_stars');
    final half = fixture.commandLog.length ~/ 2;

    var container = await launchOffline(tester, fixture);
    container.read(routerProvider).go('/trip/line_hay.01');
    await pumpUntil(
      tester,
      () =>
          find.byType(TripDashboard).evaluate().isNotEmpty &&
          controllerOf(tester).phase == TripPhase.running,
    );
    var c = controllerOf(tester);
    await playCommands(c, fixture.commandLog.take(half));
    advanceMs(c, 500);
    // The app leaves the foreground, then its process ends.
    c.pause(PauseReason.lifecycle);
    await tester.pump();
    final left = c.engine!.state.toJson();
    await quitApp(tester);

    container = await launchOffline(
      tester,
      fixture,
      landing: '/trip/line_hay.01',
    );
    await pumpUntil(
      tester,
      () =>
          find.byType(PauseCard).evaluate().isNotEmpty &&
          controllerOf(tester).phase == TripPhase.paused,
    );
    c = controllerOf(tester);
    expect(c.engine!.state.toJson(), left);

    await tester.tap(find.text('كمّل المشوار'));
    await tester.pump();
    expect(c.phase, TripPhase.running);
    await playCommands(c, fixture.commandLog.skip(half));
    runOut(c);
    await pumpUntil(
      tester,
      () => currentLocation(tester) == '/trip/line_hay.01/result',
    );
    expect(
      container.read(economyViewProvider).lastResult!.toJson(),
      fixture.expectedResult.toJson(),
    );
    await quitApp(tester);
  });
}
