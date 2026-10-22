// The five sample trips offline on a real device (specs/008-m02-trip-screen
// SC-001): the real database and clock, no network, each trip played to the
// end through the screen's controls by the scripted player. CI doesn't run
// this. On a device in airplane mode:
//
//   fvm flutter test integration_test/trip_offline_test.dart --flavor dev
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';

import '../test/helpers/pump_app.dart';
import '../test/helpers/trip.dart';
import 'trip_helpers.dart';

/// The sample pack's trips, each with its 3-star run.
const _samples = {
  'line_hay.01': 'sample__line_hay_01_three_stars',
  'line_hay.02': 'sample__line_hay_02_three_stars',
  'line_hay.03': 'sample__line_hay_03_three_stars',
  'line_gamaa.01': 'sample__line_gamaa_01_three_stars',
  'line_gamaa.02': 'sample__line_gamaa_02_three_stars',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A fresh install, so the tank holds the five trips.
  setUpAll(deleteAppDatabase);

  for (final MapEntry(key: tripId, value: name) in _samples.entries) {
    testWidgets('$tripId plays to the end offline', (tester) async {
      final fixture = loadFixture(name);
      expect(fixture.definition.tripId, tripId);
      final container = await launchOffline(tester, fixture);
      final before = container.read(economyViewProvider).jenehat;

      container.read(routerProvider).go('/trip/$tripId');
      await pumpUntil(
        tester,
        () =>
            find.byType(TripDashboard).evaluate().isNotEmpty &&
            controllerOf(tester).phase == TripPhase.running,
      );
      final run = await ScriptedPlayer(tester, fixture).drive(
        settle: () => pumpUntil(
          tester,
          () => currentLocation(tester) == '/trip/$tripId/result',
        ),
      );

      final result = run.result;
      expect(result, isNotNull, reason: '${run.exit}');
      if (!run.inexact) {
        expect(result!.toJson(), fixture.expectedResult.toJson());
      }
      expect(
        container.read(economyViewProvider).jenehat,
        before + result!.earningsJenehat,
      );
      final db = await tester.runAsync(
        () => container.read(appDatabaseProvider.future),
      );
      final records = await tester.runAsync(
        () => db!.select(db.tripRecordTable).get(),
      );
      expect(records, isEmpty);
      await quitApp(tester);
    });
  }
}
