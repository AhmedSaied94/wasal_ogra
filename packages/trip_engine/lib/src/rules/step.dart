// One 33 ms logic step, in the fixed order of rules.md §3.
import '../events.dart';
import '../model/state.dart';
import '../params.dart';
import 'aids.dart';
import 'authored_events.dart';
import 'chain.dart';
import 'course.dart';
import 'fares.dart';
import 'passengers.dart';
import 'reputation.dart';
import 'stations.dart';
import 'transition.dart';

/// The state after one step from [state], and what happened. A trip that
/// isn't running doesn't move (§3.1).
(TripState, List<DomainEvent>) stepTrip(
  Course course,
  TripParams params,
  TripState state,
  String Function() logHash,
) {
  if (state.status != TripStatus.running) return (state, const []);
  final tx = Transition(course, params, state, logHash)..tMs += stepMs;
  _timers(tx);
  authoredEvents(tx);
  scheduledPayments(tx);
  moveTokens(tx);
  drainPatience(tx);
  warnStation(tx);
  reachDeadlines(tx);
  reachStations(tx);
  failureCheck(tx);
  endCheck(tx);
  return (tx.freeze(), tx.events);
}

// §3.2: alertness timers, the ledger peek, dropped tokens, pending breaks.
void _timers(Transition tx) {
  alertnessTimers(tx);
  attentionTimers(tx);
  ledgerPeekTimer(tx);
  dropDeadlines(tx);
  completeBreaks(tx);
}
