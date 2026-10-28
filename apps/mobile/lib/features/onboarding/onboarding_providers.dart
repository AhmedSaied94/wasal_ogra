// The first session's providers (specs/012-m07-onboarding/contracts/
// first-session.md "For other features"). Every write to its flags goes
// through [FirstSessionFlagsNotifier], so a redirect right after a write
// reads the new flags; this file and the store are the only ones that touch
// the database for it.
import 'package:material_ui/material_ui.dart' show Locale, debugPrint;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/features/onboarding/application/first_session_service.dart';
import 'package:wassal/features/onboarding/data/drift_first_session_store.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

part 'onboarding_providers.g.dart';

/// The only writer of `first_session`.
@Riverpod(keepAlive: true)
Future<DriftFirstSessionStore> firstSessionStore(Ref ref) async =>
    DriftFirstSessionStore(await ref.watch(appDatabaseProvider.future));

/// The `first_session` row, and the one way to change it. Boot awaits it
/// before handing over, so reads after boot are synchronous.
@Riverpod(keepAlive: true, name: 'firstSessionFlagsProvider')
class FirstSessionFlagsNotifier extends _$FirstSessionFlagsNotifier {
  @override
  Future<FirstSessionFlags> build() async =>
      (await ref.watch(firstSessionStoreProvider.future)).read();

  /// The flags now; the empty flags before they load.
  FirstSessionFlags get current => state.value ?? FirstSessionFlags.empty;

  // The times are the trusted clock's (data-model.md "first_session").

  Future<void> markOpeningDone() =>
      _write((store) async => store.markOpeningDone(await _nowMs()));

  Future<void> addSceneDue(String sceneId) =>
      _write((store) => store.addSceneDue(sceneId));

  Future<void> markSceneSeen(String sceneId) =>
      _write((store) => store.markSceneSeen(sceneId));

  Future<void> markFuelLessonDone() =>
      _write((store) async => store.markFuelLessonDone(await _nowMs()));

  /// Raises the step; never lowers it.
  Future<void> reachStep(int step) => _write((store) => store.reachStep(step));

  Future<void> markDone() =>
      _write((store) async => store.markDone(await _nowMs()));

  Future<int> _nowMs() async =>
      (await ref.read(trustedClockProvider.future)).nowMs();

  Future<void> _write(
    Future<Object?> Function(DriftFirstSessionStore store) write,
  ) async {
    final store = await ref.read(firstSessionStoreProvider.future);
    await write(store);
    state = AsyncData(await store.read());
  }
}

/// The testers' "coach on every tutorial trip" (research R21): in memory,
/// off at each launch, and only reachable from the playtest Home.
@Riverpod(keepAlive: true)
class CoachEverywhere extends _$CoachEverywhere {
  @override
  bool build() => false;

  bool get on => state;

  set on(bool value) => state = value;
}

/// What the active pack says of the first session: the tutorial trips and
/// the scenes that play by themselves (research R3, R5).
typedef TutorialPlan = ({
  List<String> tutorialTrips,
  String? openingScene,
  Map<String, String> afterTripScenes,
});

/// [TutorialPlan] for [content].
TutorialPlan tutorialPlanOf(ContentSource content) {
  final scenes = sessionScenesOf(content);
  return (
    tutorialTrips: tutorialTripsOf(content),
    openingScene: scenes.opening,
    afterTripScenes: scenes.afterTrip,
  );
}

@Riverpod(keepAlive: true)
TutorialPlan tutorialPlan(Ref ref) =>
    tutorialPlanOf(ref.watch(contentSourceProvider));

/// The first session, rebuilt when its facts change: the flags, the
/// economy's view and the active pack. Synchronous after startup.
@Riverpod(keepAlive: true)
FirstSession firstSession(Ref ref) {
  final flags =
      ref.watch(firstSessionFlagsProvider).value ?? FirstSessionFlags.empty;
  final view = ref.watch(economyViewProvider);
  final plan = ref.watch(tutorialPlanProvider);
  return FirstSession(
    FirstSessionFacts(
      flags: flags,
      tutorialTrips: plan.tutorialTrips,
      progress: view.progress,
      unfinishedTripId: view.unfinished?.tripId,
      fuelLiters: view.fuel.liters,
      fuelUnlimited: view.fuel.unlimitedUntilMs != null,
      tutorialGranted: view.tutorialGranted,
      displayName: view.displayName,
      nameRefused: view.nameRefused,
      openingSceneId: plan.openingScene,
      afterTripScenes: plan.afterTripScenes,
      coachEverywhere: ref.watch(coachEverywhereProvider),
    ),
  );
}

/// The tutorial trip whose first finish ended the tutorial in this run of
/// the app, until its result's «كمّل» is pressed (contracts/first-session.md
/// "The result screen"). In memory: a relaunch shows no result.
@Riverpod(keepAlive: true)
class TutorialEndedOn extends _$TutorialEndedOn {
  @override
  String? build() => null;

  String? get tripId => state;

  set tripId(String? value) => state = value;
}

/// Whether Home asked for a name in this run of the app: at most once a
/// launch (contracts/name.md "The re-ask"). In memory.
@Riverpod(keepAlive: true)
class NameAsked extends _$NameAsked {
  @override
  bool build() => false;

  bool get done => state;

  set done(bool value) => state = value;
}

/// M14 sets the ask after a scene here.
@Riverpod(keepAlive: true)
FirstSessionHooks firstSessionHooks(Ref ref) => const NoFirstSessionHooks();

/// The first session's bookkeeping, following the economy's views while it
/// is listened to: the app listens from startup to its end.
@Riverpod(keepAlive: true)
FirstSessionService firstSessionService(Ref ref) {
  final service = FirstSessionService(
    flags: ref.read(firstSessionFlagsProvider.notifier),
    plan: () => ref.read(tutorialPlanProvider),
    hooks: ref.read(firstSessionHooksProvider),
    onTutorialEnded: (tripId) =>
        ref.read(tutorialEndedOnProvider.notifier).tripId = tripId,
  );
  // One view at a time, in order: each write reads the flags the last one
  // left.
  var queue = Future<void>.value();
  ref.listen(economyViewProvider, (previous, next) {
    if (previous == null) return;
    queue = queue
        .then((_) => service.onView(previous, next))
        .catchError(
          (Object error) => debugPrint('onboarding flags write: $error'),
        );
  });
  return service;
}

/// The tutorial lesson [tripId] is coached by, or null (contracts/coach.md):
/// until its first finish, or always with the testers' switch. The trip
/// asks each time a run starts.
@riverpod
int? tutorialCoach(Ref ref, String tripId) =>
    ref.watch(firstSessionProvider).coachFor(tripId);

/// The seed of the Name card's first suggestion: the trusted clock, so each
/// install starts on another name. Tests inject it (contracts/name.md).
@riverpod
int nameSeed(Ref ref) => ref.watch(trustedClockProvider).requireValue.nowMs();

/// The driver's name as the game shows it (contracts/name.md "The name
/// shown"): the projection's, pending or accepted, else «الأسطى». It reads
/// only the economy, never M06's account copy (data-model.md "Two copies of
/// the name, two jobs").
@riverpod
String driverName(Ref ref) =>
    ref.watch(economyViewProvider).displayName ??
    lookupAppLocalizations(const Locale('ar')).driverNameDefault;
