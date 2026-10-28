import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/config/tunable_snapshot.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_records.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';

import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/first_session.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

// The first session's redirects (contracts/first-session.md "Router"): a
// trip's start goes through a due scene or the fuel lesson first, Home plays
// a due scene, the unfinished trip is never held up, and `then` only leads
// to a trip or Home.

const _name = 'حمادة';

TripProgress _finished(int at) =>
    TripProgress(bestStars: 1, plays: 1, firstCompletedAtMs: at);

/// A player named [_name] who finished tutorial trips 1 to [finished], with
/// [liters] in the tank.
EconomyState Function(int nowMs) _player({int finished = 0, int liters = 5}) =>
    (nowMs) => EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
      displayName: () => _name,
      fuel: FuelState(liters: liters, countedFromMs: nowMs),
      progress: {
        for (final trip in tutorialTripIds.take(finished)) trip: _finished(1),
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
  String location, {
  required EconomyState Function(int nowMs) player,
  Set<String> scenesDue = const {},
  bool fuelLessonDone = false,
  String? unfinished,
  List<Override> overrides = const [],
}) async {
  final economy = await testEconomy(
    content: tutorialContent(),
    firstState: player,
  );
  if (unfinished != null) await _leaveUnfinished(economy, unfinished);
  await preloadTripArt(tester);
  await pumpWassalApp(
    tester,
    newPlayer: true,
    initialLocation: location,
    content: contentTestOverrides(assets: tutorialBundledAssets()),
    economy: economyOverridesOf(economy),
    trip: tripTestOverrides(),
    overrides: [
      ...seededFirstSession((store) async {
        await store.markOpeningDone(0);
        await store.reachStep(4);
        for (final scene in scenesDue) {
          await store.addSceneDue(scene);
        }
        if (fuelLessonDone) await store.markFuelLessonDone(0);
      }),
      ...overrides,
    ],
  );
}

/// Skips the scene and lets the writes and the page change finish (a trip
/// with a sleeper never settles: his breathing loops).
Future<void> _skipScene(WidgetTester tester) async {
  await tester.tap(find.byKey(ScenePlayer.skipKey));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('a trip: the due scene first, then the trip', (tester) async {
    await _launch(
      tester,
      '/trip/line_hay.04',
      player: _player(finished: 3),
      scenesDue: {'the_stand'},
    );
    expect(
      Uri.parse(currentLocation(tester)),
      Uri(
        path: '/onboarding/scene/the_stand',
        queryParameters: {'then': '/trip/line_hay.04'},
      ),
    );
    await _skipScene(tester);
    expect(currentLocation(tester), '/trip/line_hay.04');
  });

  testWidgets('a failed scene write: reported, the scene again, then on', (
    tester,
  ) async {
    await _launch(
      tester,
      '/trip/line_hay.04',
      player: _player(finished: 3),
      scenesDue: {'the_stand'},
      overrides: [
        firstSessionFlagsProvider.overrideWith(
          () => FailingFlags({'sceneSeen'}),
        ),
      ],
    );
    final scene = currentLocation(tester);
    await _skipScene(tester);
    expect(tester.takeException(), isA<Exception>());
    expect(currentLocation(tester), scene);
    // The scene starts again, and its skip works again.
    expect(find.byKey(ScenePlayer.skipKey), findsOneWidget);
    await _skipScene(tester);
    expect(tester.takeException(), isNull);
    expect(currentLocation(tester), '/trip/line_hay.04');
  });

  testWidgets("trip 5's first start: the fuel lesson first", (tester) async {
    await _launch(tester, '/trip/line_hay.05', player: _player(finished: 4));
    expect(currentLocation(tester), '/onboarding/fuel?then=line_hay.05');
  });

  testWidgets('an empty tank in the tutorial: the fuel lesson', (tester) async {
    await _launch(
      tester,
      '/trip/line_hay.02',
      player: _player(finished: 1, liters: 0),
    );
    expect(currentLocation(tester), '/onboarding/fuel?then=line_hay.02');
  });

  testWidgets('the lesson done: the trip itself', (tester) async {
    await _launch(
      tester,
      '/trip/line_hay.05',
      player: _player(finished: 4),
      fuelLessonDone: true,
    );
    expect(currentLocation(tester), '/trip/line_hay.05');
  });

  testWidgets('Home with a due scene plays it, then Home', (tester) async {
    await _launch(
      tester,
      '/home',
      player: _player(finished: 3),
      scenesDue: {'the_stand'},
    );
    expect(
      Uri.parse(currentLocation(tester)),
      Uri(
        path: '/onboarding/scene/the_stand',
        queryParameters: {'then': '/home'},
      ),
    );
    await _skipScene(tester);
    expect(currentLocation(tester), '/home');
  });

  testWidgets('the unfinished trip is never redirected', (tester) async {
    await _launch(
      tester,
      '/trip/line_hay.05',
      player: _player(finished: 4),
      unfinished: 'line_hay.05',
      scenesDue: {'the_stand'},
    );
    expect(currentLocation(tester), '/trip/line_hay.05');
  });

  for (final then in ['https://example.com/x', '/lines', '/trip/nope']) {
    testWidgets('then $then becomes Home', (tester) async {
      await _launch(
        tester,
        Uri(
          path: '/onboarding/scene/the_stand',
          queryParameters: {'then': then},
        ).toString(),
        player: _player(finished: 3),
        scenesDue: {'the_stand'},
      );
      await _skipScene(tester);
      expect(currentLocation(tester), '/home');
    });
  }
}
