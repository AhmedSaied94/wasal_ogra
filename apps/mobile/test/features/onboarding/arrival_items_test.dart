// M07's two arrival items (specs/013-m08-home-result, contracts/seams.md
// `ArrivalItem`, research R9): a due scene, then the name sheet on the next
// arrival; the sheet at most once a launch, never in a trip; the first
// notification ask inside the scene's item; and no `/home` redirect.
// The name cases are M07's re-ask cases (contracts/name.md "The re-ask"),
// moved here with `NameReaskHost`.
import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/config/tunable_snapshot.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/features/home/application/arrival_queue.dart';
import 'package:wassal/features/onboarding/application/first_session_service.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/name_sheet.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_records.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/first_session.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

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

Future<void> _launch(WidgetTester tester, TestEconomy economy) async {
  await pumpWassalApp(
    tester,
    economy: economyOverridesOf(economy),
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

/// M14's hook, held open until the test lets it go.
final class _HeldHooks implements FirstSessionHooks {
  final asked = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> afterScene() {
    asked.complete();
    return release.future;
  }
}

/// A named player who finished the first three tutorial trips, the scene
/// after trip 3 due, and the name refused by the server.
Future<void> _sceneAndRefusedName(
  WidgetTester tester, {
  FirstSessionHooks hooks = const NoFirstSessionHooks(),
  List<Override> overrides = const [],
}) async {
  final economy = await testEconomy(
    content: tutorialContent(),
    firstState: (nowMs) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
          progress: {
            for (final trip in tutorialTripIds.take(3))
              trip: const TripProgress(
                bestStars: 1,
                plays: 1,
                firstCompletedAtMs: 1,
              ),
          },
        ),
  );
  await refuseName(economy, 'حمادة');
  await preloadTripArt(tester);
  await pumpWassalApp(
    tester,
    newPlayer: true,
    content: contentTestOverrides(assets: tutorialBundledAssets()),
    economy: economyOverridesOf(economy),
    overrides: [
      nameSeedProvider.overrideWithValue(_seed),
      firstSessionHooksProvider.overrideWithValue(hooks),
      ...seededFirstSession((store) async {
        await store.markOpeningDone(0);
        await store.reachStep(4);
        await store.addSceneDue('the_stand');
      }),
      ...overrides,
    ],
  );
}

Future<void> _skipScene(WidgetTester tester) async {
  await tester.tap(find.byKey(ScenePlayer.skipKey));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('a due scene and a refused name', () {
    testWidgets('the scene on one arrival, the sheet on the next', (
      tester,
    ) async {
      await _sceneAndRefusedName(tester);
      expect(
        Uri.parse(currentLocation(tester)).path,
        '/onboarding/scene/the_stand',
      );
      expect(find.byType(NameSheet), findsNothing);

      await _skipScene(tester);
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/home');
      // The arrival back from the scene is the scene's.
      expect(find.byType(NameSheet), findsNothing);

      await _go(tester, '/lines');
      await _go(tester, '/home');
      await tester.pumpAndSettle();
      expect(find.byType(NameSheet), findsOneWidget);
    });

    testWidgets("M07's afterScene runs inside the scene's item", (
      tester,
    ) async {
      final hooks = _HeldHooks();
      await _sceneAndRefusedName(tester, hooks: hooks);
      await tester.tap(find.byKey(ScenePlayer.skipKey));
      await pumpFrames(tester);
      expect(hooks.asked.isCompleted, isTrue);
      // Held on the scene until the ask is done.
      expect(
        Uri.parse(currentLocation(tester)).path,
        '/onboarding/scene/the_stand',
      );

      hooks.release.complete();
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/home');
      expect(find.byType(NameSheet), findsNothing);
    });
  });

  group('the name sheet', () {
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

    testWidgets('no name once a trip has started: the sheet, without the '
        'line', (tester) async {
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
  });

  testWidgets('the router no longer sends /home to a due scene', (
    tester,
  ) async {
    // Without the queue's items, a due scene stays due on Home.
    await _sceneAndRefusedName(
      tester,
      overrides: [arrivalItemsProvider.overrideWithValue(const [])],
    );
    expect(currentLocation(tester), '/home');
  });
}
