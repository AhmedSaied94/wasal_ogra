import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';
import 'package:wassal/features/onboarding/data/drift_first_session_store.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

import 'economy.dart';

/// A player past the first session (specs/012-m07-onboarding): the opening
/// seen, the fuel lesson done and every step reached, so boot hands over to
/// الموقف and no trip is redirected. Written to the app's database the first
/// time the flags are read, before boot reads them.
///
/// Their tutorial is done too: the plan keeps the pack's scenes but no
/// tutorial trip, as every one were finished (FR-039), so no trip is coached
/// and the boosters are open.
///
/// `pumpWassalApp` uses it unless a test asks for a new player.
List<Override> returningPlayerOverrides() => [
  firstSessionStoreProvider.overrideWith((ref) async {
    final store = DriftFirstSessionStore(
      await ref.watch(appDatabaseProvider.future),
    );
    await store.markOpeningDone(0);
    await store.markFuelLessonDone(0);
    await store.reachStep(lastFirstSessionStep);
    return store;
  }),
  tutorialPlanProvider.overrideWith((ref) {
    final plan = tutorialPlanOf(ref.watch(contentSourceProvider));
    return (
      tutorialTrips: const <String>[],
      openingScene: plan.openingScene,
      afterTripScenes: plan.afterTripScenes,
    );
  }),
];

/// A player whose `first_session` row [seed] writes, the first time the
/// flags are read (with `pumpWassalApp(newPlayer: true)`).
List<Override> seededFirstSession(
  Future<void> Function(DriftFirstSessionStore store) seed,
) => [
  firstSessionStoreProvider.overrideWith((ref) async {
    final store = DriftFirstSessionStore(
      await ref.watch(appDatabaseProvider.future),
    );
    await seed(store);
    return store;
  }),
];

/// [name] recorded, then refused by the server as B03 refuses a name
/// (`validation_error`), as a sync would apply it.
Future<void> refuseName(TestEconomy economy, String name) async {
  final service = economy.service;
  final op = (await service.setDisplayName(
    service.newRequestId(),
    name,
  ) as OpApplied).op;
  await service.applyAnswer(
    SyncAnswer(
      stateVersion: 5,
      stateStale: false,
      results: [OpResult.rejected(op.op.txnId.value, 'validation_error')],
      wallet: const ServerWallet(
        jenehat: 0,
        bonat: 0,
        fuel: 5,
        fuelMax: 5,
        fuelUpdatedAtMs: testEpochMs,
      ),
    ),
    batch: [op],
    playerId: '0192f1c3-7d1e-7a4b-9c11-000000000001',
  );
}

/// The flags, with [failing] writes throwing once each, as a full disk
/// would: `fuelLesson` and `sceneSeen`.
final class FailingFlags extends FirstSessionFlagsNotifier {
  FailingFlags(Set<String> failing) : _failing = {...failing};

  final Set<String> _failing;

  Future<void>? _fail(String write) => _failing.remove(write)
      ? Future.error(Exception('$write: disk full'))
      : null;

  @override
  Future<void> markFuelLessonDone() =>
      _fail('fuelLesson') ?? super.markFuelLessonDone();

  @override
  Future<void> markSceneSeen(String sceneId) =>
      _fail('sceneSeen') ?? super.markSceneSeen(sceneId);
}
