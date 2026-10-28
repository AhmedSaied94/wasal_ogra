// What the trip screen shows besides the view: the phase's details, the
// cards' contents, and where to go once the trip ends
// (contracts/trip-controller.md).
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

export 'package:wassal/features/trip/domain/trip_view.dart' show TripPhase;

/// Why the trip paused.
enum PauseReason { button, back, lifecycle, debugPanel }

/// An economy call that failed to write and waits for «حاول تاني».
enum TripRetry { start, result, purchase, revive }

/// Where the screen goes once the trip ends.
sealed class TripExit extends ViewValue {
  const TripExit();
}

/// The result route, with the trip's result.
final class ExitToResult extends TripExit {
  const ExitToResult(this.tripId, this.result);

  final String tripId;
  final TripResult result;

  @override
  Map<String, Object?> get fields => {'tripId': tripId, 'result': result};
}

final class ExitToHome extends TripExit {
  const ExitToHome();

  @override
  Map<String, Object?> get fields => const {};
}

/// Another trip is unfinished: go there instead.
final class ExitToTrip extends TripExit {
  const ExitToTrip(this.tripId);

  final String tripId;

  @override
  Map<String, Object?> get fields => {'tripId': tripId};
}

/// The purchase card of a booster with none left.
final class BoosterCardModel extends ViewValue {
  const BoosterCardModel({
    required this.booster,
    required this.priceBonat,
    required this.bonat,
    required this.shortBy,
  });

  final BoosterId booster;
  final int? priceBonat;
  final int bonat;

  /// BONAT missing, after the economy refused for funds.
  final int? shortBy;

  @override
  Map<String, Object?> get fields => {
    'booster': booster,
    'priceBonat': priceBonat,
    'bonat': bonat,
    'shortBy': shortBy,
  };
}

/// Everything the trip screen reads, in one value.
final class TripModel extends ViewValue {
  const TripModel({
    required this.phase,
    this.view,
    this.retry,
    this.nextLiterAtMs,
    this.exit,
    this.boosterCard,
    this.pauseReason,
    this.restartEnabled = false,
    this.coach,
    this.coachBubble,
  });

  final TripPhase phase;

  /// Null until the engine starts.
  final TripView? view;
  final TripRetry? retry;

  /// The no-fuel card's countdown, on trusted time.
  final int? nextLiterAtMs;
  final TripExit? exit;
  final BoosterCardModel? boosterCard;
  final PauseReason? pauseReason;

  /// «عيد المشوار» needs a liter, or unlimited fuel.
  final bool restartEnabled;

  /// The tutorial step showing while the trip runs
  /// (specs/012-m07-onboarding/contracts/coach.md).
  final CoachView? coach;

  /// The coach line in بلية's bubble: the step's, or the last one's while
  /// its bubble finishes its time.
  final CoachLine? coachBubble;

  @override
  Map<String, Object?> get fields => {
    'phase': phase,
    'view': view,
    'retry': retry,
    'nextLiterAtMs': nextLiterAtMs,
    'exit': exit,
    'boosterCard': boosterCard,
    'pauseReason': pauseReason,
    'restartEnabled': restartEnabled,
    'coach': coach,
    'coachBubble': coachBubble,
  };
}
