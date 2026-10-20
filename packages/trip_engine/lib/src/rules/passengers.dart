// Passengers' alertness and patience (rules.md §3 step 2, §4.5, §7.3).
// Only aboard passengers' timers run.
import 'package:content_models/content_models.dart';

import '../capabilities.dart';
import '../events.dart';
import '../model/counters.dart';
import '../model/passenger.dart';
import 'fares.dart';
import 'reputation.dart';
import 'speech.dart';
import 'transition.dart';

/// Phase 2.1 and 2.2 (§3), each in passenger order: a waking sleeper whose
/// time has come wakes, then an awake sleeper whose time has come falls
/// asleep again.
void alertnessTimers(Transition tx) {
  for (var q = 0; q < tx.passengers.length; q++) {
    if (_due(tx, q, Alertness.waking)) wake(tx, q);
  }
  for (var q = 0; q < tx.passengers.length; q++) {
    if (tx.course.archetype(q) != Archetype.sleeper ||
        !_due(tx, q, Alertness.awake)) {
      continue;
    }
    final state = tx.passenger(q);
    tx
      ..setPassenger(
        q,
        state.copyWith(alertness: Alertness.asleep, alertUntilMs: null),
      )
      ..emit(PassengerFellAsleep(tx.tMs, passengerId: state.passengerId));
  }
}

/// Phase 2.3 (§3): an attentive passenger whose time is up is muted again.
void attentionTimers(Transition tx) {
  for (var q = 0; q < tx.passengers.length; q++) {
    if (!_due(tx, q, Alertness.attentive)) continue;
    final state = tx.passenger(q);
    tx
      ..setPassenger(
        q,
        state.copyWith(alertness: Alertness.muted, alertUntilMs: null, taps: 0),
      )
      ..emit(PassengerMuted(tx.tMs, passengerId: state.passengerId));
  }
}

/// Taps that make a muted passenger attentive (§4.5 case 3).
const int _callsToAttend = 2;

/// Tap case 3 (§4.5): a muted passenger is called, and attends on the
/// second call.
void callMuted(Transition tx, int q) {
  final state = tx.passenger(q);
  final taps = state.taps + 1;
  if (taps < _callsToAttend) {
    tx
      ..setPassenger(q, state.copyWith(taps: taps))
      ..emit(
        PassengerCalled(tx.tMs, passengerId: state.passengerId, taps: taps),
      );
    return;
  }
  tx
    ..setPassenger(
      q,
      state.copyWith(
        alertness: Alertness.attentive,
        alertUntilMs: tx.tMs + tx.params.tripHeadphonesAttentiveMs,
        taps: 0,
      ),
    )
    ..emit(PassengerAttentive(tx.tMs, passengerId: state.passengerId));
  say(tx, q, SpeechSlot.attentive);
}

// [q] is aboard and [alertness], and its timer has run out.
bool _due(Transition tx, int q, Alertness alertness) {
  final state = tx.passenger(q);
  final until = state.alertUntilMs;
  return state.presence == Presence.aboard &&
      state.alertness == alertness &&
      until != null &&
      until <= tx.tMs;
}

/// Tap case 1 (§4.5): an asleep passenger starts waking.
void startWaking(Transition tx, int q) {
  final state = tx.passenger(q);
  tx
    ..setPassenger(
      q,
      state.copyWith(
        alertness: Alertness.waking,
        alertUntilMs: tx.tMs + tx.params.tripWakeMs,
      ),
    )
    ..emit(PassengerWaking(tx.tMs, passengerId: state.passengerId));
}

/// [q] is awake until `t + trip_sleeper_awake_ms` and says `woke`.
void wake(Transition tx, int q) {
  final state = tx.passenger(q);
  tx
    ..setPassenger(
      q,
      state.copyWith(
        alertness: Alertness.awake,
        alertUntilMs: tx.tMs + tx.params.tripSleeperAwakeMs,
      ),
    )
    ..emit(PassengerWoke(tx.tMs, passengerId: state.passengerId));
  say(tx, q, SpeechSlot.woke);
}

/// Patience starts the first time [q]'s balance is above 0 (§7.3).
void startPatience(Transition tx, int q) {
  final state = tx.passenger(q);
  if (state.balance <= 0 || state.patienceStartMs != null) return;
  final patience = tx.course.archetype(q) == Archetype.hurry
      ? scale(tx.params.tripPatienceMs, tx.params.tripPatiencePctHurry)
      : tx.params.tripPatienceMs;
  tx.setPassenger(
    q,
    state.copyWith(patienceMs: patience, patienceStartMs: patience),
  );
}

/// Phase 6 (§3): every owed, aboard passenger with patience left loses one
/// step of it, or more while traffic is active.
void drainPatience(Transition tx) {
  final drain = tx.trafficActive
      ? scale(stepMs, tx.params.tripPatienceDrainPctTraffic)
      : stepMs;
  for (var q = 0; q < tx.passengers.length; q++) {
    final state = tx.passenger(q);
    final (left, start) = (state.patienceMs, state.patienceStartMs);
    if (state.presence != Presence.aboard ||
        !state.isOwed ||
        left == null ||
        start == null ||
        left <= 0) {
      continue;
    }
    final next = left > drain ? left - drain : 0;
    final half = !state.halfPatienceSpoken && next * 2 <= start;
    tx.setPassenger(
      q,
      state.copyWith(patienceMs: next, halfPatienceSpoken: half ? true : null),
    );
    if (half) say(tx, q, SpeechSlot.wantsChange, amount: state.balance);
    if (next == 0) _runOut(tx, q);
  }
}

// Patience reached 0: once per passenger, as it never refills.
void _runOut(Transition tx, int q) {
  final state = tx.passenger(q);
  tx
    ..setPassenger(q, state.copyWith(impatient: true))
    ..counters = tx.counters.copyWith(impatient: tx.counters.impatient + 1);
  loseReputation(tx, RepCause.impatient, tx.params.repImpatient);
  tx.emit(PatienceRanOut(tx.tMs, passengerId: state.passengerId));
  say(tx, q, SpeechSlot.impatient);
}
