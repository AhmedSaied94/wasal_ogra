// The coached player (specs/012-m07-onboarding/contracts/coach.md "Tests",
// FR-047): a new player who does only what بلية points at. A cell is a pick,
// the drawer the coins that make the change, a rider a tap (a throw with
// money in hand), lesson 0's scrim a tap; otherwise the clock runs.
//
// Trip 5 has no step (its lesson is the fuel, before it), so a player who
// waits for one can never earn its star. There, [playCoached]'s `onItsOwn`
// player does what lesson 1 taught, with no one showing: each owed rider's
// change, as the coach would point it out.
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';

import 'trip.dart';

/// A coached run: how it ended, and the steps it was shown, in order.
typedef CoachedRun = ({TripResult result, List<CoachStepId> steps});

/// Taps the player may make at one moment before the clock moves on: a
/// target that answers nothing must not hold the trip still.
const _tapsPerMoment = 12;

/// Plays [c]'s open trip to its end, and waits for its result's write.
/// [onItsOwn]: when no step shows, give owed riders their change as lesson
/// 1 taught.
Future<CoachedRun> playCoached(
  TripController c, {
  bool onItsOwn = false,
  int maxMs = 600000,
}) async {
  final steps = <CoachStepId>[];
  var taps = 0;
  for (var t = 0; t < maxMs && c.phase == TripPhase.running;) {
    final shown = c.model.coach;
    if (shown != null && !steps.contains(shown.lessonStep)) {
      steps.add(shown.lessonStep);
    }
    final step = shown ?? (onItsOwn ? _lessonOne(c) : null);
    if (step != null && taps < _tapsPerMoment && _take(c, step)) {
      taps++;
      continue;
    }
    taps = 0;
    c.advance(const Duration(milliseconds: 33));
    t += 33;
  }
  await settle();
  final result = c.engine?.result;
  if (result == null) throw StateError('the trip never ended');
  return (result: result, steps: steps);
}

/// What lesson 1's step would point at now, for the first owed rider.
CoachView? _lessonOne(TripController c) {
  final session = c.session!;
  return TutorialCoach.step(
    CoachInput(
      lesson: CoachStepId.giveChange.index,
      state: session.engine.state,
      warning: null,
      memory: CoachMemory.empty,
      bubbleMinMs: session.facts.bubbleMinMs,
      destinations: session.facts.destinations,
    ),
  ).view;
}

/// Takes [step]'s active target; false when it asks only to look.
bool _take(TripController c, CoachView step) {
  if (step.endsOnAnyTap) {
    c.coachTapped();
    return true;
  }
  switch (step.target) {
    case TrayCellTarget(:final denomination):
      c.pick(denomination);
      return true;
    case PassengerTarget(:final passengerId):
      if (c.view!.hand.isEmpty) {
        c.tap(passengerId);
      } else {
        c.send(passengerId);
      }
      return true;
    case TrayTarget():
      final coin = _nextCoin(c, step.line);
      if (coin == null) return false;
      c.pick(coin);
      return true;
    case StationCountdownTarget():
      return false;
  }
}

/// The largest coin in the drawer that still fits the change.
int? _nextCoin(TripController c, CoachLine line) {
  if (line is! GiveChangeLine) return null;
  final view = c.view!;
  final rest = line.amountPiasters - view.hand.totalPiasters;
  for (final d in trayDenominations.reversed) {
    final count = view.tray.where((s) => s.denomination == d).first.count;
    if (d <= rest && count > 0) return d;
  }
  return null;
}
