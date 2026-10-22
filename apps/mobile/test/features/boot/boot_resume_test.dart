import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/config/tunable_snapshot.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_records.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';

import '../../helpers/economy.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/trip.dart';

// The launch's hand-off (tasks.md T047, contracts/trip-controller.md
// "Launch").

/// Writes a record for [tripId] under a new id; [started] tells the
/// economy too, as a trip killed while it ran left it.
Future<TxnId> record(
  TestEconomy economy,
  String tripId, {
  bool started = false,
}) async {
  final id = economy.service.newRequestId();
  final definition = economy.content.trip(tripId)!;
  await DriftTripRecords(economy.db).create(
    TripRecordHeader(
      startTxn: id,
      tripId: tripId,
      contentVersion: 1,
      definition: definition,
      seed: definition.seed,
      params: TripParams.fromTunables(
        tunableSnapshot(bundledConfig()),
        definition.lineId,
      ),
      createdAtMs: economy.clock.nowMs(),
    ),
  );
  if (started) await economy.service.startTrip(id, tripId: tripId);
  return id;
}

/// A stale record with a command, and an intent with no record.
Future<void> leftovers(TestEconomy economy) async {
  final stale = await record(economy, 'line_hay.02');
  await DriftTripRecords(economy.db)
      .appendCommand(stale, const LoggedCommand(0, PickFromTray(500)));
  await economy.db
      .into(economy.db.tripIntentTable)
      .insert(
        TripIntentTableCompanion.insert(
          requestTxn: economy.service.newRequestId().value,
          startTxn: economy.service.newRequestId().value,
          kind: 'use_booster',
          booster: 'traffic_jam',
        ),
      );
}

/// Launches the app over [economy] and returns every path it went to.
Future<List<String>> launch(WidgetTester tester, TestEconomy economy) async {
  final startup = Completer<void>();
  final container = await pumpWassalApp(
    tester,
    economy: economyOverridesOf(economy),
    overrides: [
      appStartupProvider.overrideWith((ref) async {
        await appStartup(ref);
        await startup.future;
      }),
    ],
  );
  final router = container.read(routerProvider);
  final paths = [router.state.uri.path];
  void changed() => paths.add(router.state.uri.path);
  router.routerDelegate.addListener(changed);
  addTearDown(() => router.routerDelegate.removeListener(changed));
  startup.complete();
  await tester.pumpAndSettle();
  return paths;
}

void main() {
  testWidgets('an unfinished trip opens paused; stale records go first', (
    tester,
  ) async {
    final economy = await testEconomy();
    await leftovers(economy);
    final start = await record(economy, 'line_hay.01', started: true);

    final paths = await launch(tester, economy);
    expect(currentLocation(tester), '/trip/line_hay.01');
    // Home was never reached, so its arrival didn't fire.
    expect(paths, isNot(contains('/home')));
    final c = controllerOf(tester);
    expect(c.session!.startTxn, start);
    expect(c.phase, TripPhase.paused);
    expect(find.byType(PauseCard), findsOneWidget);
    expect(await rowCount(economy, 'trip_record'), 1);
    expect(await rowCount(economy, 'trip_record_command'), 0);
    expect(await rowCount(economy, 'trip_intent'), 0);
  });

  testWidgets('nothing unfinished: Home, and every record goes', (
    tester,
  ) async {
    final economy = await testEconomy();
    await leftovers(economy);

    await launch(tester, economy);
    expect(currentLocation(tester), '/home');
    expect(await rowCount(economy, 'trip_record'), 0);
    expect(await rowCount(economy, 'trip_record_command'), 0);
    expect(await rowCount(economy, 'trip_intent'), 0);
  });
}
