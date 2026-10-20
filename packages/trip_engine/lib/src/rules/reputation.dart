// Reputation changes and the failure check (rules.md §10).
import '../events.dart';
import '../model/counters.dart';
import '../model/result.dart';
import '../model/state.dart';
import 'scoring.dart';
import 'transition.dart';

/// Adds [amount], capping the result at 100.
void gainReputation(Transition tx, RepCause cause, int amount) {
  final before = tx.reputation;
  final after = before + amount > maxReputation
      ? maxReputation
      : before + amount;
  tx.reputation = after;
  tx.emit(
    ReputationChanged(
      tx.tMs,
      delta: after - before,
      cause: cause,
      value: after,
    ),
  );
}

/// Subtracts [amount] and records it under [cause].
void loseReputation(Transition tx, RepCause cause, int amount) {
  tx.reputation -= amount;
  if (amount > 0) tx.addReputationLost(cause, amount);
  tx.emit(
    ReputationChanged(
      tx.tMs,
      delta: -amount,
      cause: cause,
      value: tx.reputation,
    ),
  );
}

/// After each step and each accepted command (§10.2): a running or paused
/// trip fails when reputation is gone, or at the first fight of a trip that
/// requires none. A fight failure can't be revived.
void failureCheck(Transition tx) {
  if (tx.status != TripStatus.running && tx.status != TripStatus.paused) return;
  final fought = tx.course.rules.noFightsRequired && tx.counters.fights > 0;
  if (tx.reputation > 0 && !fought) return;
  if (fought) tx.revivable = false;
  tx.status = TripStatus.failed;
  tx.result = buildResult(tx, TripOutcome.failed);
  tx.emit(
    TripFailed(
      tx.tMs,
      reputationLost: Map.unmodifiable(tx.reputationLost),
      revivable: tx.revivable,
    ),
  );
}
