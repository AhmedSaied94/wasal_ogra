// The first session (specs/012-m07-onboarding/contracts/first-session.md,
// research R1–R4, R10–R12): every "what comes next" answered from stored
// facts, so a kill, a restore or a content switch rebuilds the same answer.
// Pure, and holds no state of its own.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';

/// How many trips of the start line the tutorial has, at most (R3).
const tutorialTripCount = 5;

/// The tutorial trip the fuel lesson comes before: the fifth (lesson 4,
/// contracts/coach.md). A pack with fewer tutorial trips gets the lesson
/// only on an empty tank (quickstart Part B #16).
const fuelLessonTripIndex = 4;

/// The highest step of the first session (R12).
const lastFirstSessionStep = 8;

/// The step the opening scene (or the Name card, without one) writes.
const openingStep = 1;

/// The step trip 1's start writes.
const _firstTripStep = 2;

/// The step the after-trip scene writes when it finishes or is skipped.
const sceneSeenStep = 5;

/// The step written once the ask after the scene (M14's) is passed.
const askStep = 6;

/// The `first_session` row (data-model.md). An absent row is [empty].
final class FirstSessionFlags {
  const FirstSessionFlags({
    this.openingDoneAtMs,
    this.scenesDue = const [],
    this.scenesSeen = const [],
    this.fuelLessonDoneAtMs,
    this.stepReached = 0,
    this.doneAtMs,
  });

  static const empty = FirstSessionFlags();

  final int? openingDoneAtMs;

  /// Scene ids made due by a first finish on this phone, in order.
  final List<String> scenesDue;
  final List<String> scenesSeen;
  final int? fuelLessonDoneAtMs;

  /// 0 to [lastFirstSessionStep], never lowered.
  final int stepReached;
  final int? doneAtMs;

  @override
  bool operator ==(Object other) =>
      other is FirstSessionFlags &&
      other.openingDoneAtMs == openingDoneAtMs &&
      _listEquals(other.scenesDue, scenesDue) &&
      _listEquals(other.scenesSeen, scenesSeen) &&
      other.fuelLessonDoneAtMs == fuelLessonDoneAtMs &&
      other.stepReached == stepReached &&
      other.doneAtMs == doneAtMs;

  @override
  int get hashCode => Object.hash(
    openingDoneAtMs,
    Object.hashAll(scenesDue),
    Object.hashAll(scenesSeen),
    fuelLessonDoneAtMs,
    stepReached,
    doneAtMs,
  );

  @override
  String toString() =>
      'FirstSessionFlags(opening $openingDoneAtMs, due $scenesDue, seen '
      '$scenesSeen, fuel $fuelLessonDoneAtMs, step $stepReached, done '
      '$doneAtMs)';
}

/// What the first session is decided from. It holds no state of its own.
final class FirstSessionFacts {
  const FirstSessionFacts({
    required this.flags,
    required this.tutorialTrips,
    required this.progress,
    required this.fuelLiters,
    required this.fuelUnlimited,
    required this.tutorialGranted,
    this.unfinishedTripId,
    this.displayName,
    this.nameRefused = false,
    this.openingSceneId,
    this.afterTripScenes = const {},
    this.coachEverywhere = false,
  });

  final FirstSessionFlags flags;

  /// [tutorialTripsOf] the active pack.
  final List<String> tutorialTrips;
  final Map<String, TripProgress> progress;
  final String? unfinishedTripId;

  /// The tank now, and whether an unlimited window is open.
  final int fuelLiters;
  final bool fuelUnlimited;
  final bool tutorialGranted;
  final String? displayName;
  final bool nameRefused;

  /// The pack's `opening` scene, if it has one.
  final String? openingSceneId;

  /// The pack's `after_trip` scenes, by the trip they follow.
  final Map<String, String> afterTripScenes;

  /// The testers' "coach on every tutorial trip" (R21).
  final bool coachEverywhere;

  /// The first trip has started: a result, or a start without one.
  bool get hasStartedATrip => progress.isNotEmpty || unfinishedTripId != null;
}

/// What must come before a trip starts.
sealed class BeforeStart {
  const BeforeStart();
}

/// A scene made due by a first finish, not seen yet.
final class DueScene extends BeforeStart {
  const DueScene(this.sceneId);

  final String sceneId;

  @override
  bool operator ==(Object other) =>
      other is DueScene && other.sceneId == sceneId;

  @override
  int get hashCode => sceneId.hashCode;

  @override
  String toString() => 'DueScene($sceneId)';
}

/// المعلم's fuel lesson and the tutorial gift (contracts/fuel-lesson.md).
final class FuelLessonDue extends BeforeStart {
  const FuelLessonDue();

  @override
  bool operator ==(Object other) => other is FuelLessonDue;

  @override
  int get hashCode => 0;
}

/// A trip counts as finished on a first finish on this phone, or a best
/// time in the server's state, which sends no first-finish time (FR-039).
bool isFinished(TripProgress? progress) =>
    progress != null &&
    (progress.firstCompletedAtMs != null || progress.bestTimeMs != null);

final class FirstSession {
  const FirstSession(this.facts);

  final FirstSessionFacts facts;

  FirstSessionFlags get _flags => facts.flags;

  /// Where boot goes after M06's first-open wait, when no trip is
  /// unfinished (R4).
  String launchTarget(FirstOpenOutcome outcome) {
    // A tutorial trip's start also raised the step: the record of a
    // trip_start that a refusal or a replaced state took out of the view.
    if (outcome == FirstOpenOutcome.restored ||
        facts.hasStartedATrip ||
        _flags.stepReached >= _firstTripStep) {
      return '/home';
    }
    if (_flags.openingDoneAtMs == null && facts.openingSceneId != null) {
      return '/onboarding/intro';
    }
    if (facts.displayName == null) return '/onboarding/name';
    final trips = facts.tutorialTrips;
    return trips.isEmpty ? '/home' : '/trip/${trips.first}';
  }

  /// The first due scene not seen yet.
  String? get dueScene {
    for (final scene in _flags.scenesDue) {
      if (!_flags.scenesSeen.contains(scene)) return scene;
    }
    return null;
  }

  /// What comes before [tripId] starts, or null (R10, R11).
  BeforeStart? beforeStart(String tripId) {
    if (dueScene case final scene?) return DueScene(scene);
    return fuelLessonDue(tripId) ? const FuelLessonDue() : null;
  }

  /// المعلم's fuel lesson is due before [tripId] (R11): the fifth tutorial
  /// trip's first play, or any tutorial trip on an empty tank with no
  /// unlimited window, until the gift is granted or the lesson done. A due
  /// scene doesn't hide it, though [beforeStart] puts the scene first: Home
  /// keeps «يلا نطلع!» for it (specs/013-m08-home-result, research R8).
  bool fuelLessonDue(String tripId) {
    if (facts.tutorialGranted || _flags.fuelLessonDoneAtMs != null) {
      return false;
    }
    final index = facts.tutorialTrips.indexOf(tripId);
    if (index < 0) return false;
    final firstPlay =
        index == fuelLessonTripIndex &&
        (facts.progress[tripId]?.plays ?? 0) == 0;
    final dry = facts.fuelLiters < 1 && !facts.fuelUnlimited;
    return firstPlay || dry;
  }

  /// What an arrival at Home plays first: a due scene. The name sheet is
  /// the next arrival item (specs/013-m08-home-result, research R9).
  DueScene? onArrivalAtHome() => switch (dueScene) {
    final scene? => DueScene(scene),
    null => null,
  };

  /// The result screen's main action in the first session (R12): the next
  /// tutorial trip not finished, or Home. [playable] refuses a trip the
  /// rules won't start (FR-012, SC-003a), such as a story trip whose
  /// chapter waits: the result goes Home instead of a dead end.
  String nextAfterResult(
    String tripId, {
    bool Function(String tripId)? playable,
  }) {
    if (!facts.tutorialTrips.contains(tripId)) return '/home';
    return switch (nextTutorialTrip) {
      final trip? when playable == null || playable(trip) => '/trip/$trip',
      _ => '/home',
    };
  }

  /// The first tutorial trip not finished, while in the first session; else
  /// null. Home's next trip until the tutorial is done
  /// (specs/013-m08-home-result, research R8).
  String? get nextTutorialTrip {
    if (!inFirstSession) return null;
    for (final trip in facts.tutorialTrips) {
      if (!isFinished(facts.progress[trip])) return trip;
    }
    return null;
  }

  /// Every tutorial trip the pack has is finished (FR-039).
  bool get tutorialDone =>
      facts.tutorialTrips.every((trip) => isFinished(facts.progress[trip]));

  bool get inFirstSession => !tutorialDone && facts.hasStartedATrip;

  /// The lesson of [tripId] (its index in the tutorial), until its first
  /// finish, or always with the testers' switch (R14, R21).
  int? coachFor(String tripId) {
    final index = facts.tutorialTrips.indexOf(tripId);
    if (index < 0) return null;
    if (facts.coachEverywhere) return index;
    return isFinished(facts.progress[tripId]) ? null : index;
  }

  /// The locked boosters bar shows until the tutorial is done (FR-038).
  bool get boostersLocked => !tutorialDone;

  /// Home asks for a name the server refused, or for one never given once a
  /// trip has started (contracts/name.md "The re-ask"); before that, the
  /// Name card asks.
  bool get askName =>
      facts.nameRefused || (facts.displayName == null && facts.hasStartedATrip);

  int get stepReached => _flags.stepReached;

  /// The `after_trip` scene that plays after [tripId]'s first finish.
  String? afterTripScene(String tripId) => facts.afterTripScenes[tripId];
}

/// The step a start of [tripId] reaches (R12): trips 1–3 are steps 2–4,
/// trip 4 is 7 and trip 5 is 8, after the scene (5) and the ask (6).
int? stepOnStart(List<String> tutorialTrips, String tripId) =>
    switch (tutorialTrips.indexOf(tripId)) {
      0 => 2,
      1 => 3,
      2 => 4,
      3 => 7,
      4 => 8,
      _ => null,
    };

/// The tutorial (R3): the first [tutorialTripCount] trips, by number, of the
/// first line whose unlock is `start`. Empty when no line starts unlocked.
List<String> tutorialTripsOf(ContentSource content) {
  for (final line in content.lines) {
    if (line.unlock.kind == UnlockKind.start) {
      return List.unmodifiable([
        for (final trip in content.tripsOf(line.lineId).take(tutorialTripCount))
          trip.tripId,
      ]);
    }
  }
  return const [];
}

/// The scenes the app plays by itself (R5): the `opening` and the
/// `after_trip` ones by trip, from every chapter.
({String? opening, Map<String, String> afterTrip}) sessionScenesOf(
  ContentSource content,
) {
  String? opening;
  final afterTrip = <String, String>{};
  for (final chapter in content.chapters) {
    for (final scene in chapter.scenes) {
      switch (scene.plays) {
        case ScenePlays(kind: ScenePlaysKind.opening):
          opening ??= scene.sceneId;
        case ScenePlays(kind: ScenePlaysKind.afterTrip, :final tripId?):
          afterTrip.putIfAbsent(tripId, () => scene.sceneId);
        case _:
          break;
      }
    }
  }
  return (opening: opening, afterTrip: Map.unmodifiable(afterTrip));
}

/// The scene [sceneId] of the pack, or null.
Scene? sceneOf(ContentSource content, String sceneId) {
  for (final chapter in content.chapters) {
    for (final scene in chapter.scenes) {
      if (scene.sceneId == sceneId) return scene;
    }
  }
  return null;
}

/// The chapter holding [sceneId], or null.
Chapter? chapterOfScene(ContentSource content, String sceneId) {
  for (final chapter in content.chapters) {
    if (chapter.scenes.any((s) => s.sceneId == sceneId)) return chapter;
  }
  return null;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
