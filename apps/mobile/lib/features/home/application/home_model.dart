// What Home draws (specs/013-m08-home-result, data-model `HomeModel`,
// contracts/home.md): one value over the economy, the pack, the account,
// the server's status and M07's first session.
import 'package:content_models/content_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/features/home/application/home_slots.dart';
import 'package:wassal/features/home/application/last_finished_trip.dart';
import 'package:wassal/features/home/domain/line_card.dart';
import 'package:wassal/features/home/domain/next_trip.dart';
import 'package:wassal/features/home/domain/savings_target.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

part 'home_model.g.dart';

/// The start button's state (research R11).
enum HomeFuelState {
  /// «يلا نطلع!» with «−١».
  normal,

  /// «البنزين خلص» and the next liter's countdown.
  empty,

  /// An unlimited window: «يلا نطلع!» without «−١».
  unlimited,
}

/// What the player is told of the server (M06).
enum HomeReach { online, offline, maintenance }

/// The level a player without one from the server shows.
const firstDriverLevel = 1;

final class HomeModel {
  const HomeModel({
    required this.driverName,
    required this.driverLevel,
    required this.jenehat,
    required this.bonat,
    required this.fuel,
    required this.fuelState,
    required this.reach,
    required this.next,
    required this.line,
    required this.vehicle,
    required this.lastStation,
    required this.savings,
    required this.storySceneWaiting,
    required this.showDebug,
  });

  final String driverName;
  final int driverLevel;
  final int jenehat;
  final int bonat;
  final FuelView fuel;
  final HomeFuelState fuelState;
  final HomeReach reach;

  /// Null only for a pack with no startable trip: the button is disabled.
  final NextTrip? next;
  final LineCardFigures? line;

  /// The next trip's vehicle, in the scene.
  final VehicleId vehicle;

  /// The line's last station: the caller calls it.
  final String? lastStation;

  /// The roof sign: the line's last station. Null on the tuktuk, which has
  /// none.
  String? get signStation => vehicle == VehicleId.tuktuk ? null : lastStation;
  final SavingsTarget savings;
  final bool storySceneWaiting;

  /// The apartment tab's «new» dot (FR-009).
  bool get apartmentDot => savings.affordable;

  /// The testers' tools (internal builds).
  final bool showDebug;

  bool get offline => reach == HomeReach.offline;

  @override
  bool operator ==(Object other) =>
      other is HomeModel &&
      other.driverName == driverName &&
      other.driverLevel == driverLevel &&
      other.jenehat == jenehat &&
      other.bonat == bonat &&
      other.fuel == fuel &&
      other.fuelState == fuelState &&
      other.reach == reach &&
      other.next == next &&
      other.line == line &&
      other.vehicle == vehicle &&
      other.lastStation == lastStation &&
      other.savings == savings &&
      other.storySceneWaiting == storySceneWaiting &&
      other.showDebug == showDebug;

  @override
  int get hashCode => Object.hash(
    driverName,
    driverLevel,
    jenehat,
    bonat,
    fuel,
    fuelState,
    reach,
    next,
    line,
    vehicle,
    lastStation,
    savings,
    storySceneWaiting,
    showDebug,
  );
}

/// Home's next trip: M07's tutorial trip in the first session (FR-011),
/// otherwise FR-010's rule. A tutorial trip the rules refuse (a story trip
/// whose chapter waits) is never offered (FR-012, SC-003a).
NextTrip? homeNextTrip(
  ContentSource content,
  PlayerProgress progress,
  FirstSession session, {
  required String? lastFinishedTripId,
}) {
  if (session.nextTutorialTrip case final tripId?) {
    if (NextTrip.of(content, tripId) case final next?
        when tripPlayable(content, progress, tripId)) {
      return next;
    }
  }
  return nextTrip(content, progress, lastFinishedTripId: lastFinishedTripId);
}

/// [fuel]'s button state: a window first; an empty tank only when M07's
/// fuel lesson isn't about to fill it (R8).
HomeFuelState homeFuelState(FuelView fuel, {required bool lessonDue}) {
  if (fuel.unlimitedUntilMs != null) return HomeFuelState.unlimited;
  if (fuel.liters < 1 && !lessonDue) return HomeFuelState.empty;
  return HomeFuelState.normal;
}

@riverpod
HomeModel homeModel(Ref ref) {
  final content = ref.watch(contentSourceProvider);
  final view = ref.watch(economyViewProvider);
  final progress = ref.watch(playerProgressProvider);
  final session = ref.watch(firstSessionProvider);
  final status = ref.watch(serverStatusProvider);
  final last =
      ref.watch(lastFinishedTripProvider) ?? lastFirstCompleted(view.progress);

  final next = homeNextTrip(
    content,
    progress,
    session,
    lastFinishedTripId: last,
  );
  final vehicle = switch (next) {
    final next? => content.trip(next.tripId)?.vehicleId,
    null => null,
  };
  final line = next == null ? null : content.line(next.lineId);
  return HomeModel(
    driverName: ref.watch(driverNameProvider),
    driverLevel: ref.watch(profileProvider)?.driverLevel ?? firstDriverLevel,
    jenehat: view.jenehat,
    bonat: view.bonat,
    fuel: view.fuel,
    fuelState: homeFuelState(
      view.fuel,
      lessonDue: next != null && session.fuelLessonDue(next.tripId),
    ),
    reach: switch (status) {
      ServerStatusState(reach: Reach.offline) => HomeReach.offline,
      ServerStatusState(maintenance: _?) => HomeReach.maintenance,
      _ => HomeReach.online,
    },
    next: next,
    line: next == null ? null : lineCardFigures(content, progress, next),
    vehicle: vehicle ?? VehicleId.tuktuk,
    lastStation: line?.stations.lastOrNull?.name.arEg,
    savings: savingsTarget(content, progress, view.jenehat),
    storySceneWaiting: ref.watch(storySceneWaitingProvider),
    showDebug: ref.watch(flavorProvider) != Flavor.prod,
  );
}
