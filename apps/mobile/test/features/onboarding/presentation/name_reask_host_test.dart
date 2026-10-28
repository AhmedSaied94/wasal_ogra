import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/config/tunable_snapshot.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/name_sheet.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_records.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/first_session.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/trip.dart';

// The re-ask (contracts/name.md "The re-ask"): on an arrival at Home, outside
// a trip, at most once a launch, the Name sheet asks for a name the server
// refused, or for one never given once a trip has started.

const _seed = 24;

/// A player who has played: a trip in their progress.
EconomyState _played(int nowMs) =>
    EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
      progress: const {
        'line_hay.01': TripProgress(bestStars: 1, plays: 1, bestTimeMs: 1),
      },
    );

/// [tripId] started and left unfinished, with its replay record, as a kill
/// leaves it.
Future<void> _leaveUnfinished(TestEconomy economy, String tripId) async {
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
  await economy.service.startTrip(id, tripId: tripId);
}

Future<void> _launch(
  WidgetTester tester,
  TestEconomy economy, {
  String? at,
}) async {
  await pumpWassalApp(
    tester,
    economy: economyOverridesOf(economy),
    initialLocation: at,
    settle: at == null,
    overrides: [nameSeedProvider.overrideWithValue(_seed)],
  );
  await tester.pumpAndSettle();
}

/// Closes the sheet as the player would, with ✕.
Future<void> _dismiss(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.byType(NameSheet), findsNothing);
}

Future<void> _go(WidgetTester tester, String location) async {
  appRouter(tester).go(location);
  await pumpFrames(tester);
}

void main() {
  testWidgets('a refused name: the sheet with its line, once a launch', (
    tester,
  ) async {
    final economy = await testEconomy(firstState: _played);
    await refuseName(economy, 'حمادة');
    await _launch(tester, economy);
    expect(find.byType(NameSheet), findsOneWidget);
    final l10n = AppLocalizations.of(appContext(tester));
    expect(find.text(l10n.nameRefusedLine), findsOneWidget);

    await _dismiss(tester);
    await _go(tester, '/lines');
    await _go(tester, '/home');
    await tester.pumpAndSettle();
    expect(find.byType(NameSheet), findsNothing);
  });

  testWidgets('no name once a trip has started: the sheet, without the line', (
    tester,
  ) async {
    await _launch(tester, await testEconomy(firstState: _played));
    expect(find.byType(NameSheet), findsOneWidget);
    final l10n = AppLocalizations.of(appContext(tester));
    expect(find.text(l10n.nameRefusedLine), findsNothing);
  });

  testWidgets('a name and no refusal: nothing', (tester) async {
    final economy = await testEconomy(firstState: _played);
    final service = economy.service;
    await service.setDisplayName(service.newRequestId(), 'سيد');
    await _launch(tester, economy);
    expect(find.byType(NameSheet), findsNothing);
  });

  testWidgets('never during a trip; on the arrival at Home after it', (
    tester,
  ) async {
    final economy = await testEconomy(firstState: _played);
    await refuseName(economy, 'حمادة');
    // Killed in a trip: boot opens it again, and Home isn't on the way.
    await _leaveUnfinished(economy, 'line_hay.01');
    await preloadTripArt(tester);
    await pumpWassalApp(
      tester,
      economy: economyOverridesOf(economy),
      overrides: [nameSeedProvider.overrideWithValue(_seed)],
    );
    expect(currentLocation(tester), '/trip/line_hay.01');
    expect(find.byType(NameSheet), findsNothing);

    await _go(tester, '/home');
    await tester.pumpAndSettle();
    expect(find.byType(NameSheet), findsOneWidget);
  });

  testWidgets('each launch asks again, until a name is accepted', (
    tester,
  ) async {
    final economy = await testEconomy(firstState: _played);
    await refuseName(economy, 'حمادة');
    await _launch(tester, economy);
    await _dismiss(tester);

    // A new launch: the memory of this one is gone.
    await _launch(tester, economy);
    expect(find.byType(NameSheet), findsOneWidget);
    await tester.tap(find.byKey(NameSheet.ctaKey));
    await tester.pumpAndSettle();
    expect(find.byType(NameSheet), findsNothing);

    await _launch(tester, economy);
    expect(find.byType(NameSheet), findsNothing);
  });
}
