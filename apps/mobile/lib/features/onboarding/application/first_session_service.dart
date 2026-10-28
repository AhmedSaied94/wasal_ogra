// The first session's bookkeeping (specs/012-m07-onboarding/contracts/
// first-session.md "Events that write the flags"): from the economy's views,
// a tutorial trip's start raises the step, a first finish seen on this
// phone makes its after-trip scene due, and the tutorial's end is recorded
// once. The scene page writes through it too. A restored progress carries
// best times, never a first finish, so it makes nothing due.
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

/// What runs after an after-trip scene, before the game goes on: M14's
/// notification ask. Nothing until then.
abstract interface class FirstSessionHooks {
  Future<void> afterScene();
}

final class NoFirstSessionHooks implements FirstSessionHooks {
  const NoFirstSessionHooks();

  @override
  Future<void> afterScene() async {}
}

final class FirstSessionService {
  FirstSessionService({
    required this._flags,
    required this._plan,
    required this._hooks,
    required this._onTutorialEnded,
  });

  final FirstSessionFlagsNotifier _flags;
  final TutorialPlan Function() _plan;
  final FirstSessionHooks _hooks;

  /// The tutorial trip whose first finish, seen here, ended the tutorial.
  final void Function(String tripId) _onTutorialEnded;

  /// The economy's view went from [previous] to [next].
  Future<void> onView(EconomyView previous, EconomyView next) async {
    final plan = _plan();
    final started = next.unfinished;
    if (started != null && started.startTxn != previous.unfinished?.startTxn) {
      final step = stepOnStart(plan.tutorialTrips, started.tripId);
      if (step != null) await _flags.reachStep(step);
    }
    String? finishedNow;
    for (final MapEntry(key: tripId, value: progress)
        in next.progress.entries) {
      // Not a replay of a trip the server's state had finished.
      final firstNow =
          progress.firstCompletedAtMs != null &&
          !isFinished(previous.progress[tripId]);
      if (!firstNow) continue;
      finishedNow = tripId;
      if (plan.afterTripScenes[tripId] case final scene?) {
        await _flags.addSceneDue(scene);
      }
    }
    final tutorialDone = plan.tutorialTrips.every(
      (trip) => isFinished(next.progress[trip]),
    );
    if (_flags.current.doneAtMs == null && tutorialDone) {
      await _flags.markDone();
      if (finishedNow != null && plan.tutorialTrips.contains(finishedNow)) {
        _onTutorialEnded(finishedNow);
      }
    }
  }

  /// An after-trip scene finished or was skipped.
  Future<void> sceneSeen(String sceneId) async {
    await _flags.markSceneSeen(sceneId);
    await _flags.reachStep(sceneSeenStep);
  }

  /// The ask after a scene: M14's hook, then its step.
  Future<void> afterScene() async {
    await _hooks.afterScene();
    await _flags.reachStep(askStep);
  }
}
